# udpxy — 多阶段构建，静态链接
# ============================================================
# 构建阶段与运行阶段统一使用 alpine:3.21（musl），好处：
#   1. 构建/运行同一 libc，且 musl 静态二进制远小于 glibc 静态二进制
#      （实测 glibc 静态版 1,079,848 字节 vs musl 静态版 157,368 字节）
#   2. musl 自带 DNS 解析器，静态链接下不依赖运行时 NSS 共享库
#   3. apk 源已替换为清华镜像，避免 dl-cdn.alpinelinux.org 在国内过慢
# ============================================================
FROM alpine:latest AS builder

ARG UDPXY_BRANCH=master

RUN set -eux; \
    sed -i 's|dl-cdn.alpinelinux.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apk/repositories; \
    grep -q 'mirrors.tuna.tsinghua.edu.cn' /etc/apk/repositories; \
    apk add --no-cache \
        build-base make gcc tar gzip curl ca-certificates

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
# 这里不需要 -no-pie：udpxy 用 Makefile 构建，gcc 的 -static 驱动规格本身就抑制了 PIE。
# （对比：msd / msd_lite 用 CMake，CMakeLists 里的 try_linker_flag 会主动探测并追加
#   -pie / -z relro，才必须显式用 -no-pie 压掉。）
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
# Stage 2: 运行
# ============================================================
FROM alpine:latest

LABEL org.opencontainers.image.title="udpxy" \
      org.opencontainers.image.description="UDP-to-HTTP multicast relay (udpxy), statically linked" \
      org.opencontainers.image.source="https://github.com/pcherenkov/udpxy" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"

# 运行阶段也要装包，同样先换清华源
RUN set -eux; \
    sed -i 's|dl-cdn.alpinelinux.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apk/repositories; \
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
