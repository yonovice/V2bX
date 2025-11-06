#!/usr/bin/env bash
#
# V2bX 平滑更新脚本
# 功能：拉取最新代码或指定版本，构建并替换二进制，备份当前二进制，保留配置与日志，重启服务。
# 使用：sudo bash scripts/update.sh [--version <tag>]

set -euo pipefail

red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

projectRootDir="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
binaryInstallPath="/bin/V2bX"
backupDir="/etc/V2bX/backup"
targetVersion=""

parseArgs() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) targetVersion="$2"; shift 2 ;;
      -h|--help) echo "用法：sudo bash scripts/update.sh [--version <tag>]"; exit 0 ;;
      *) warn "未知参数：$1"; shift 1 ;;
    esac
  done
}

requireRoot() {
  if [[ $(id -u) -ne 0 ]]; then
    err "请以 root 用户运行此脚本。"; exit 1
  fi
}

ensureGo() {
  if ! command -v go >/dev/null 2>&1; then
    err "未检测到 go 环境，请先执行 scripts/install.sh 安装。"; exit 1
  fi
}

prepareBackup() {
  mkdir -p "${backupDir}"
  if [[ -f "${binaryInstallPath}" ]]; then
    cp -f "${binaryInstallPath}" "${backupDir}/V2bX.$(date +%Y%m%d%H%M%S)" || true
  fi
}

updateCode() {
  cd "${projectRootDir}"
  if [[ -n "${targetVersion}" ]]; then
    git fetch --tags || true
    git checkout "${targetVersion}" || err "切换版本失败：${targetVersion}"
  else
    git pull --rebase || true
  fi
}

buildBinary() {
  cd "${projectRootDir}"
  GOEXPERIMENT=jsonv2 go mod download
  GOEXPERIMENT=jsonv2 go build -v -o V2bX -tags "sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor"
  install -m 0755 V2bX "${binaryInstallPath}"
}

restartService() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart V2bX.service || systemctl start V2bX.service
  fi
}

main() {
  parseArgs "$@"
  requireRoot
  ensureGo
  prepareBackup
  updateCode
  buildBinary
  restartService
  ok "V2bX 已更新完成"
}

main "$@"