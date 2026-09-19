#!/bin/sh
# udpxy 容器入口脚本
# 用法一：用环境变量控制（推荐，见 docker-compose.yml）
# 用法二：docker run ... -p 4022 -m eth0   —— 原始参数原样透传给 udpxy
set -e

UDPXY_BIN="/usr/local/bin/udpxy"
log() { echo "[udpxy] $*"; }

# 参数以 - 开头 => 认为是原始 udpxy 参数，直接透传
case "$1" in
  -*)
    log "透传原始参数: $*"
    exec "$UDPXY_BIN" "$@"
    ;;
esac

# ---- 组装参数 ----------------------------------------------------------
# -T  前台运行（容器必须，否则进程一退容器就结束）
# -v  输出访问日志
# -S  开启客户端统计（提供 /status 页面）
set -- "$UDPXY_BIN" -T -S

[ "${UDPXY_VERBOSE:-1}" = "1" ] && set -- "$@" -v

# 必需：监听端口
PORT="${UDPXY_PORT:-4022}"
set -- "$@" -p "$PORT"

# 可选参数，设置后才追加
[ -n "${UDPXY_BINDADDR:-}" ]   && set -- "$@" -a "$UDPXY_BINDADDR"
[ -n "${UDPXY_MAXCLIENTS:-}" ] && set -- "$@" -c "$UDPXY_MAXCLIENTS"
[ -n "${UDPXY_SOURCE:-}" ]     && set -- "$@" -m "$UDPXY_SOURCE"
[ -n "${UDPXY_BUFSIZE:-}" ]    && set -- "$@" -B "$UDPXY_BUFSIZE"
[ -n "${UDPXY_RENEW:-}" ]      && [ "$UDPXY_RENEW" != "0" ] && set -- "$@" -M "$UDPXY_RENEW"
[ -n "${UDPXY_LOGFILE:-}" ]    && set -- "$@" -l "$UDPXY_LOGFILE"
[ -n "${UDPXY_MSGBUFRESERVE:-}" ] && set -- "$@" -R "$UDPXY_MSGBUFRESERVE"
[ -n "${UDPXY_MSGBUFHOLD:-}" ]    && set -- "$@" -H "$UDPXY_MSGBUFHOLD"
[ -n "${UDPXY_NICE:-}" ]          && set -- "$@" -n "$UDPXY_NICE"
[ -n "${UDPXY_EXTRA_ARGS:-}" ]    && set -- "$@" ${UDPXY_EXTRA_ARGS}

log "监听端口   : ${PORT}"
log "绑定地址   : ${UDPXY_BINDADDR:-0.0.0.0}"
log "组播源接口 : ${UDPXY_SOURCE:-0.0.0.0}"
log "最大客户端 : ${UDPXY_MAXCLIENTS:-3}"
log "启动命令   : $*"

exec "$@"
