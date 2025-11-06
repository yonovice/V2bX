#!/usr/bin/env bash
#
# V2bX 完全卸载脚本
# 功能：停止并禁用 systemd 服务，移除二进制、配置、日志、logrotate 配置与服务单元。
# 使用：sudo bash scripts/uninstall.sh

set -euo pipefail

red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

requireRoot() {
  if [[ $(id -u) -ne 0 ]]; then
    err "请以 root 用户运行此脚本。"; exit 1
  fi
}

confirm() {
  warn "确定要卸载 V2bX 吗？将移除服务与所有相关文件 (Y/n)"
  local ans
  read -r -p "请输入选择: " ans || true
  if [[ -n "${ans}" && "${ans}" != "Y" && "${ans}" != "y" ]]; then
    echo "已取消卸载"; exit 0
  fi
}

stopService() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop V2bX.service || true
    systemctl disable V2bX.service || true
  fi
}

removeFiles() {
  rm -f /etc/systemd/system/V2bX.service || true
  rm -rf /etc/V2bX/ || true
  rm -f /bin/V2bX || true
  rm -f /usr/local/bin/V2bX || true
  rm -f /etc/logrotate.d/V2bX || true
  rm -f /var/log/V2bX.log || true
}

reloadSystemd() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
    systemctl reset-failed || true
  fi
}

main() {
  requireRoot
  confirm
  stopService
  removeFiles
  reloadSystemd
  ok "V2bX 已卸载完成"
}

main "$@"