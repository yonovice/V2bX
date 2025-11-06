#!/usr/bin/env bash
#
# V2bX 配置管理脚本
# 功能：备份/恢复/校验/格式化（json5->json），以及快速查看当前节点数量
# 使用：sudo bash scripts/config.sh <backup|restore|validate|nodes|view>

set -euo pipefail

red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

configFilePath="/etc/V2bX/config.json"
backupDir="/etc/V2bX/backup"

usage() {
  echo "用法：sudo bash scripts/config.sh <backup|restore <file>|validate|nodes|view>"
}

requireRoot() {
  if [[ $(id -u) -ne 0 ]]; then
    err "请以 root 用户运行此脚本。"; exit 1
  fi
}

cmd="${1:-}"
[[ -z "${cmd}" ]] && { usage; exit 1; }

requireRoot

case "$cmd" in
  backup)
    mkdir -p "${backupDir}"
    cp -f "${configFilePath}" "${backupDir}/config.$(date +%Y%m%d%H%M%S).json"
    ok "已备份配置到 ${backupDir}"
    ;;
  restore)
    file="${2:-}"
    [[ -z "${file}" ]] && { err "请提供备份文件路径"; usage; exit 1; }
    cp -f "${file}" "${configFilePath}"
    ok "已恢复配置到 ${configFilePath}"
    ;;
  validate)
    # 使用 jq 校验 JSON 语法
    if ! command -v jq >/dev/null 2>&1; then
      warn "未检测到 jq，尝试安装"
      if command -v apt >/dev/null 2>&1; then apt update -y && apt install -y jq; fi
      if command -v yum >/dev/null 2>&1; then yum install -y jq; fi
      if command -v pacman >/dev/null 2>&1; then pacman -Sy --noconfirm jq; fi
    fi
    jq . "${configFilePath}" >/dev/null && ok "配置 JSON 语法校验通过" || err "配置语法错误"
    ;;
  nodes)
    if command -v jq >/dev/null 2>&1; then
      count=$(jq '.Nodes | length' "${configFilePath}")
      echo "当前节点数量：${count}"
    else
      warn "未安装 jq，尝试以 grep 估算"
      count=$(grep -c '"NodeID"' "${configFilePath}" || true)
      echo "估算节点数量：${count}"
    fi
    ;;
  view)
    sed -n '1,200p' "${configFilePath}" | cat
    ;;
  *)
    usage; exit 1 ;;
esac