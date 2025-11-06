#!/usr/bin/env bash
#
# V2bX 服务管理脚本
# 功能：start/stop/restart/status/log/config 路径显示
# 使用：sudo bash scripts/v2bx.sh <start|stop|restart|status|log|config>

set -euo pipefail

red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

binaryInstallPath="/bin/V2bX"
configFilePath="/etc/V2bX/config.json"
logFilePath="/var/log/V2bX.log"

usage() {
  echo "用法：sudo bash scripts/v2bx.sh <start|stop|restart|status|log|config>"
}

requireRoot() {
  if [[ $(id -u) -ne 0 ]]; then
    err "请以 root 用户运行此脚本。"; exit 1
  fi
}

cmd="$1" || { usage; exit 1; }

requireRoot

case "$cmd" in
  start)
    systemctl start V2bX.service
    ok "V2bX 已启动"
    ;;
  stop)
    systemctl stop V2bX.service
    ok "V2bX 已停止"
    ;;
  restart)
    systemctl restart V2bX.service
    ok "V2bX 已重启"
    ;;
  status)
    systemctl status V2bX.service --no-pager || true
    ;;
  log)
    journalctl -u V2bX.service -e --no-pager -f || true
    ;;
  config)
    echo "二进制：${binaryInstallPath}"
    echo "配置：  ${configFilePath}"
    echo "日志：  ${logFilePath}"
    ;;
  *)
    usage; exit 1 ;;
esac