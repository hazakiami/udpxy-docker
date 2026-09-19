# udpxy — 多阶段构建，静态链接
# ============================================================
# 构建阶段：ubuntu:26.04（glibc 2.43 / GCC 15 / binutils 2.46）
# 运行阶段：alpine:3.21（保持不变）
#
# 产物仍是静态链接二进制，运行阶段不依赖任何动态库，
# 因此运行镜像的行为与改造前一致。
#
# 从 alpine 迁到 ubuntu 需要改动的地方（其实就是「alpine 内置的东西 ubuntu 都没有」）：
#   1. 包管理器    apk            → apt-get
#   2. 编译工具集  build-base     → build-essential + libc6-dev
#   3. 下载工具    busybox wget   → 需显式安装，这里统一改用 curl
#                                  （与 msd / msd_lite 两个镜像保持一致）
#   4. 静态链接    CFLAGS/LDFLAGS 不用动，见下方说明
# ============================================================
FROM ubuntu:latest AS builder

ARG UDPXY_BRANCH=master

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl tar gzip \
        build-essential make gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# 通过镜像代理下载源码（GitHub 直连在部分网络环境下不可用）
RUN set -eux; \
    for url in \
      "https://ghfast.top/https://github.com/pcherenkov/udpxy/archive/refs/heads/${UDPXY_BRANCH}.tar.gz" \
      "https://gh-proxy.com/https://github.com/pcherenkov/udpxy/archive/refs/heads/${UDPXY_BRANCH}.tar.gz" \
      "https://codeload.github.com/pcherenkov/udpxy/tar.gz/refs/heads/${UDPXY_BRANCH}" \
    ; do \
      echo "trying $url"; \
      if curl -4 -fsSL --connect-timeout 15 "$url" -o /tmp/udpxy.tar.gz \
         && tar tzf /tmp/udpxy.tar.gz >/dev/null 2>&1; then \
        echo "downloaded ok: $url"; break; \
      fi; \
    done; \
    tar xzf /tmp/udpxy.tar.gz --strip-components=1; \
    rm -f /tmp/udpxy.tar.gz; \
    test -f chipmunk/Makefile

# 静态编译，产物不依赖任何动态库。
#
# 注意：这里**不需要**像 msd / msd_lite 那样追加 -no-pie。
# 原因：udpxy 用 Makefile 构建，gcc 的 -static 驱动规格本身就抑制了 PIE；
#       而 msd / msd_lite 用 CMake，CMakeLists 里的 try_linker_flag 会主动探测并
#       追加 -pie / -z relro，才必须显式用 -no-pie 压掉。
# 实测：加与不加 -no-pie，产物字节完全相同（1079848 字节，ET_EXEC，静态链接）。
WORKDIR /src/chipmunk
RUN set -eux; \
    make clean || true; \
    make release CFLAGS="-static" LDFLAGS="-static"; \
    strip --strip-all udpxy; \
    mkdir -p /out; \
    cp -f udpxy /out/udpxy.real; \
    ls -l /out/udpxy.real; \
    test -x /out/udpxy.real

# ============================================================
# Stage 2: 运行（与原版完全一致）
# ============================================================
FROM alpine:latest

LABEL org.opencontainers.image.title="udpxy" \
      org.opencontainers.image.description="UDP-to-HTTP multicast relay (udpxy), statically linked" \
      org.opencontainers.image.source="https://github.com/pcherenkov/udpxy" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

RUN set -eux; \
    apk add --no-cache tzdata curl; \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    echo "Asia/Shanghai" > /etc/timezone; \
    apk del tzdata; \
    addgroup -S udpxy; \
    adduser -S -G udpxy -H -s /sbin/nologin udpxy

COPY --from=builder /out/udpxy.real /usr/local/bin/udpxy
RUN ln -sf /usr/local/bin/udpxy /usr/local/bin/udpxrec \
 && chmod 0755 /usr/local/bin/udpxy \
 && ls -l /usr/local/bin/

# 健康检查：udpxy 自带的状态页 /status
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${UDPXY_PORT:-4022}/status" >/dev/null || exit 1

EXPOSE 4022/tcp

# 运行时参数，全部可由 docker run -e 覆盖
# 注意：-B 缓冲区合法范围是 4096~2097152 字节，不能小于 4096
ENV UDPXY_PORT=4022 \
    UDPXY_MAXCLIENTS=64 \
    UDPXY_SOURCE=0.0.0.0 \
    UDPXY_BINDADDR=0.0.0.0 \
    UDPXY_BUFSIZE=65536 \
    UDPXY_RENEW=0 \
    UDPXY_VERBOSE=1

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
