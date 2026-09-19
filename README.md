# udpxy — UDP-to-HTTP 组播中继（静态链接）

把经典的 **udpxy（UDP-to-HTTP multicast relay proxy）** 编译打包为极简 Docker 镜像。用于把运营商 IPTV 的 **UDP / RTP 组播流** 转换成 **HTTP 单播流**，让手机、平板、播放器（VLC / Kodi / 电视盒子）在内网任意位置直接播放。

udpxy 是这一领域**最经典、兼容性最好**的方案，被大量 OpenWrt 路由器和 IPTV 部署广泛使用。本镜像为**静态链接**版本，无任何动态库依赖。

- 上游项目：[pcherenkov/udpxy](https://github.com/pcherenkov/udpxy)（GPL-3.0-or-later）
- 本镜像特点：**静态链接**、21.2 MB、多阶段构建、内置健康检查、时区设为 `Asia/Shanghai`

---

## 镜像信息

| 项目 | 值 |
|---|---|
| 镜像 | `hazaki/udpxy:latest` |
| udpxy 版本 | **1.0-25.2**（上游最新 tag，运行日志标识 `udpxy 1.0-25.2 (prod)`） |
| 镜像大小 | **21.2 MB** |
| 构建基础镜像 | `ubuntu:26.04`（glibc 2.43 / GCC 15 / binutils 2.46） |
| 运行基础镜像 | `alpine:3.21` |
| 链接方式 | **静态链接**（无动态库依赖，可跨发行版运行） |
| 暴露端口 | **4022/tcp** |
| 架构 | `linux/amd64` |
| 时区 | `Asia/Shanghai` |
| 健康检查 | 内置，探测 `/status` 状态页 |
| 许可证 | GPL-3.0-or-later |

镜像内含两个可执行入口（同一个二进制）：

| 路径 | 说明 |
|---|---|
| `/usr/local/bin/udpxy` | 主程序，组播转 HTTP 服务 |
| `/usr/local/bin/udpxrec` | 录制工具（符号链接到 udpxy） |

---

## 快速开始

### docker run

```bash
docker run -d \
  --name udpxy \
  --network host \
  -e UDPXY_PORT=4022 \
  -e UDPXY_SOURCE=eth0 \
  --restart unless-stopped \
  hazaki/udpxy:latest
```

### docker-compose

```yaml
services:
  udpxy:
    image: hazaki/udpxy:latest
    container_name: udpxy
    restart: unless-stopped

    # 必须使用 host 网络：容器需要加入宿主机的组播组
    network_mode: host

    environment:
      UDPXY_PORT: "4022"
      UDPXY_MAXCLIENTS: "64"
      # 监听地址，0.0.0.0 表示所有网卡
      UDPXY_BINDADDR: "0.0.0.0"
      # ⚠️ 改成接收 IPTV 组播的网卡名，用 `ip a` 查看
      UDPXY_SOURCE: "eth0"
      # 缓冲区，合法范围 4096 ~ 2097152 字节（不可小于 4096）
      UDPXY_BUFSIZE: "65536"
      # 组播订阅续订周期(秒)，0 = 不续订
      UDPXY_RENEW: "0"
```

启动后即可拉流：

```bash
curl -o channel.ts http://127.0.0.1:4022/udp/239.255.42.99:1234
```

---

## 播放地址

假设服务器 IP 为 `192.168.1.10`：

| 类型 | 地址 |
|---|---|
| UDP 组播 | `http://192.168.1.10:4022/udp/<组播地址>:<端口>` |
| RTP 组播 | `http://192.168.1.10:4022/rtp/<组播地址>:<端口>` |
| 状态页 | `http://192.168.1.10:4022/status` |
| 重启服务 | `http://192.168.1.10:4022/restart` |

示例：

```
http://192.168.1.10:4022/udp/239.255.42.99:1234     # UDP 组播
http://192.168.1.10:4022/rtp/239.255.42.99:1234     # RTP 组播
http://192.168.1.10:4022/status                     # 状态页
```

在 VLC 中：**媒体 → 打开网络串流**，粘贴上面的地址即可。

---

## 环境变量

udpxy 使用**命令行参数**而非配置文件。入口脚本把环境变量拼装成参数后启动，全部变量均可选（有默认值）。

| 变量 | 默认值 | 对应参数 | 说明 |
|---|---|---|---|
| `UDPXY_PORT` | `4022` | `-p` | 监听端口 |
| `UDPXY_BINDADDR` | `0.0.0.0` | `-a` | 监听地址（绑定的本地接口） |
| `UDPXY_MAXCLIENTS` | `64` | `-c` | 最大并发客户端数 |
| `UDPXY_SOURCE` | `0.0.0.0` | `-m` | **订阅组播的网卡名/地址**（建议填网卡名，如 `eth0`） |
| `UDPXY_BUFSIZE` | `65536` | `-B` | 缓冲区大小，合法范围 **4096 ~ 2097152** 字节 |
| `UDPXY_RENEW` | `0` | `-M` | 组播订阅续订周期（秒），`0` = 不续订 |
| `UDPXY_VERBOSE` | `1` | `-v` | 是否输出访问日志，`1` = 开启 |
| `UDPXY_LOGFILE` | 空 | `-l` | 日志文件路径，留空则输出到 stdout |
| `UDPXY_MSGBUFRESERVE` | 空 | `-R` | 消息缓冲保留量 |
| `UDPXY_MSGBUFHOLD` | 空 | `-H` | 消息缓冲保持时间 |
| `UDPXY_NICE` | 空 | `-n` | 进程 nice 值 |
| `UDPXY_EXTRA_ARGS` | 空 | — | 追加的原始参数，直接拼接到命令行末尾 |

> ⚠️ **`UDPXY_BUFSIZE` 不能小于 4096**，否则 udpxy 会报错退出。
>
> 💡 容器启动时始终自动带上 `-T -S`：
> `-T` = 前台运行（容器必须，否则进程一退容器就结束）；`-S` = 开启客户端统计（提供 `/status` 页面）。

---

## 使用方式

### 方式一：环境变量（推荐）

见上方快速开始。启动日志会打印实际拼出的命令行，便于核对：

```
[udpxy] 启动命令   : /usr/local/bin/udpxy -T -S -v -p 4022 -a 0.0.0.0 -c 64 -m eth0 -B 65536
```

### 方式二：透传 udpxy 原生参数

当第一个参数以 `-` 开头时，入口脚本会原样透传给 udpxy 二进制（此时环境变量不再生效）：

```bash
docker run -d --name udpxy --network host \
  hazaki/udpxy:latest -T -S -v -p 4022 -m eth0 -c 64 -B 65536
```

> 提示：udpxy 的 `-h` / `-V` 参数**并不被识别**（会报 `unrecognized option`），
> 查看版本请直接打开 `/status` 页面。需要完整参数说明请参考上游文档。

---

## 重要注意事项

### 1. 必须使用 host 网络

udpxy 依靠 **IGMP 组播**接收 IPTV 流，Docker bridge 网络下组播无法正常收发，
必须 `--network host`（compose 里用 `network_mode: host`）才能加入宿主机的组播组。

host 模式下端口由进程直接占用，**无需 `ports` 映射**。

### 2. `UDPXY_SOURCE` 建议填网卡名

`-m` 用于指定订阅组播使用的本地接口。填 `eth0` 这类**网卡名**最稳妥；
填 `0.0.0.0` 表示由内核路由决定，在多网卡机器上可能选错出口导致收不到流。

### 3. 合理设置 `UDPXY_MAXCLIENTS`

默认 `64`。每个客户端会占用缓冲区（`UDPXY_BUFSIZE` 相关内存），
客户端数 × 缓冲区过大会显著增加内存占用。家用场景设 `5 ~ 20` 即可。

### 4. 组播源需先通

udpxy 只做转发，前提是**服务器本身能收到上游 IPTV 组播**。
若 `/udp/...` 请求一直挂起无数据，请先在宿主机上确认能收到该组播组
（`tcpdump -i eth0 -n udp port <端口>`），并检查 `UDPXY_SOURCE` 是否指向正确网卡。

### 5. 容器以 root 运行

镜像内创建了 `udpxy` 非特权用户，但**未切换**（Dockerfile 无 `USER` 指令），
容器默认仍以 root 运行。如需降权可自行加 `--user`。

---

## 运维命令

```bash
docker logs -f udpxy                                     # 查看日志
docker inspect udpxy --format '{{.State.Health.Status}}' # 健康状态
curl -s http://127.0.0.1:4022/status | head -40          # 状态页
ss -tln | grep 4022                                      # 监听检查
docker restart udpxy                                     # 重启
```

`/status` 状态页会显示当前客户端数、累计流量、上游源地址等，页面底部带版本与构建时间：

```
udpxy v. 1.0 (Build 25) standard - [Sun Sep 20 05:45:23 2026]
```

---

## 验证记录

在 Ubuntu 26.04 / Docker 29.8.1 上实测（ffmpeg 构造 H.264 640x480 @1.5 Mbps 真实 MPEG-TS 流）：

| 测试项 | 结果 |
|---|---|
| 镜像构建（--no-cache 全新构建） | ✅ 成功，编译**零警告** |
| 容器启动 | ✅ `Up (healthy)`，日志 `udpxy 1.0-25.2 (prod)` |
| 健康检查 `/status` | ✅ HTTP 200 |
| `/udp/<组播>:<端口>` 拉流 | ✅ HTTP 200，4,971,848 字节 / 25 秒，解码 **487 帧 @640x480** |
| TS 流合法性 | ✅ 同步字节 `0x47` 命中率 **100%**（26,446 / 26,446 个 188 字节块） |
| 抽帧验证 | ✅ 成功导出 51,719 字节 PNG |
| `/status` 状态页 | ✅ 正常渲染，版本行 `udpxy v. 1.0 (Build 25)` |
| 时区 | ✅ 日志时间戳为 `CST`（Asia/Shanghai） |
| Env / Entrypoint / Healthcheck | ✅ 与旧版镜像逐项一致 |
| 运行期错误日志 | ✅ 0 条 |

---

## 镜像传输（离线部署）

```bash
# 源机导出
docker save hazaki/udpxy:latest -o udpxy.tar

# 目标机导入
docker load -i udpxy.tar
```

---

## 已知事项

- **udpxy 与 udpxrec 是同一个二进制**：udpxrec 只是符号链接。构建时先拷贝实体文件再建软链，
  避免多阶段 `COPY --from` 只取到软链接导致镜像不可用。
- **构建用 `make release CFLAGS="-static"`**：产物不依赖任何动态库。
  上游 Makefile 自带 `-W -Wall -Werror --pedantic`，任何编译警告都会直接让构建失败 ——
  反过来说，构建能过就代表代码在 GCC 15 下零警告。
- **构建阶段用 `ubuntu:26.04`（glibc 静态链接），运行阶段仍是 `alpine:3.21`**：
  产物是 glibc 静态二进制，不依赖 musl，可直接跑在 alpine 上（已实测）。
  代价是**体积明显变大**：

  | | alpine/musl 静态 | ubuntu/glibc 静态 | 变化 |
  |---|---|---|---|
  | 二进制 | 157,368 字节（153 KiB） | 1,079,848 字节（1.03 MiB） | **×6.9** |
  | 镜像 | 19.9 MB | 21.2 MB | +1.3 MB |

  glibc 的静态库本身比 musl 大得多，这是静态链接 glibc 的固有代价。
  两者功能完全一致（ET_EXEC、非 PIE、`ldd` 均报 `not a valid dynamic program`）。
- **从 alpine 迁到 ubuntu 构建时需要注意的三点**（本镜像 Dockerfile 已处理）：
  `apk` → `apt-get`；`build-base` → `build-essential` + `libc6-dev`；
  alpine 自带 busybox `wget`，ubuntu 需自行安装下载工具（本镜像统一用 `curl`）。
- **本镜像不需要 `-no-pie`**：udpxy 用 Makefile 构建，gcc 的 `-static` 驱动规格本身就抑制了 PIE。
  实测加与不加 `-no-pie` 产物字节完全相同。
  （对比：`msd` / `msd_lite` 用 CMake，`CMakeLists` 里的 `try_linker_flag` 会主动追加 `-pie`，才必须显式压掉。）


---

## 相关镜像

| 镜像 | 说明 |
|---|---|
| `hazaki/udpxy`（本镜像） | 经典 UDP-to-HTTP 中继，兼容性好 |
| `hazaki/msd_lite` | 轻量版现代实现，原生 RTP、多线程、资源占用更低 |
| `hazaki/msd` | 完整版，额外支持频道列表 / MPEG2-TS PID 过滤 / 零拷贝 / HTTP 源转发 |

### udpxy vs msd_lite 怎么选？

| 特性 | **udpxy** | msd_lite |
|---|---|---|
| 配置方式 | 纯命令行参数 | XML（也可用环境变量） |
| RTP 支持 | 需显式配置 | ✅ 原生 |
| 多线程 | ❌ | ✅ |
| 预缓存 | 有限 | ✅ 可调 |
| 资源占用 | 较高 | ✅ 更低 |
| 状态页 | `/status` | `/stat` |
| 生态与兼容性 | ✅ 老客户端/老配置兼容最好 | 较新 |

> 新部署建议优先选 `msd_lite`；已有 udpxy 配置或客户端兼容性要求高时选 `udpxy`。

---

## 许可证与致谢

本镜像是 [pcherenkov/udpxy](https://github.com/pcherenkov/udpxy) 的容器化封装，
遵循上游 **GPL-3.0-or-later** 许可证。
udpxy 与 udpxrec 版权归 Pavel V. Cherenkov 所有（2008-2018），感谢其出色工作。

> udpxy 仅做组播流到 HTTP 的协议转换，**不提供、不包含任何流媒体内容**。
> 请确保你转发的内容来源合法，并遵守当地法律法规。
