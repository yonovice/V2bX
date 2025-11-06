#!/usr/bin/env bash
#
# 从 GitHub 拉取并一键安装 V2bX
# 功能：
# - 克隆/更新 GitHub 仓库至临时目录
# - 调用项目内的 scripts/install.sh 完成安装
# - 支持参数转发（add-node 等）
# - 基础错误处理与回滚（二进制存在则不覆盖，失败提示手动回滚）
#
# 使用示例：
#   sudo bash install-from-github.sh --repo https://github.com/<user>/<repo>.git \
#     --api-host https://panel.local --api-key abc123 --node-id 1001 --node-type vless --listen-ip 0.0.0.0 --tls

set -euo pipefail

red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

repoUrl=""
branchName="main"
tempDir=""

printUsage() {
  cat <<EOF
用法：sudo bash scripts/install-from-github.sh --repo <url> [--branch <name>] [其他 install.sh 参数]

示例：
  sudo bash scripts/install-from-github.sh --repo https://github.com/user/V2bX.git \
    --api-host https://panel.local --api-key abc123 --node-id 1001 --node-type vless --listen-ip 0.0.0.0 --tls
EOF
}

requireRoot() {
  if [[ $(id -u) -ne 0 ]]; then
    err "请以 root 用户运行此脚本。"; exit 1
  fi
}

installGit() {
  # 根据发行版自动安装 git
  if command -v apt-get >/dev/null 2>&1; then
    ok "检测到 Debian/Ubuntu 系，自动安装 git";
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y git >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    ok "检测到 CentOS/RHEL 系，自动安装 git";
    yum install -y git >/dev/null 2>&1 || true
  elif command -v dnf >/dev/null 2>&1; then
    ok "检测到 Fedora/RHEL 系，自动安装 git";
    dnf install -y git >/dev/null 2>&1 || true
  elif command -v apk >/dev/null 2>&1; then
    ok "检测到 Alpine 系，自动安装 git";
    apk update >/dev/null 2>&1 || true
    apk add --no-cache git >/dev/null 2>&1 || true
  elif command -v pacman >/dev/null 2>&1; then
    ok "检测到 Arch 系，自动安装 git";
    pacman -Sy --noconfirm git >/dev/null 2>&1 || true
  elif command -v zypper >/dev/null 2>&1; then
    ok "检测到 openSUSE 系，自动安装 git";
    zypper refresh >/dev/null 2>&1 || true
    zypper install -y git >/dev/null 2>&1 || true
  else
    warn "未识别到常见包管理器，暂不支持自动安装 git。"
    return 1
  fi
  # 再次校验安装结果
  if command -v git >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

ensureGit() {
  if ! command -v git >/dev/null 2>&1; then
    warn "未检测到 git，正在自动安装（需要网络与包管理器）..."
    if installGit; then
      ok "git 安装成功。"
    else
      err "自动安装 git 失败，请手动安装后重试。例如：apt-get install -y git 或 yum install -y git"
      exit 1
    fi
  fi
}

parseArgs() {
  if [[ $# -lt 1 ]]; then
    printUsage; exit 1
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repoUrl="$2"; shift 2 ;;
      --branch) branchName="$2"; shift 2 ;;
      -h|--help) printUsage; exit 0 ;;
      *) # 其余参数全部透传给 install.sh
        forwardArgs+=("$1"); shift 1 ;;
    esac
  done
  if [[ -z "${repoUrl}" ]]; then
    err "必须提供 --repo <url>"; printUsage; exit 1
  fi
}

cloneRepo() {
  tempDir="$(mktemp -d -t v2bx-XXXXXX)"
  ok "使用临时目录：${tempDir}"
  git clone --depth 1 -b "${branchName}" "${repoUrl}" "${tempDir}"
}

runInstall() {
  if [[ ! -f "${tempDir}/scripts/install.sh" ]]; then
    err "仓库中不存在 scripts/install.sh"; exit 1
  fi
  ok "开始执行安装脚本"
  (cd "${tempDir}" && sudo bash scripts/install.sh "${forwardArgs[@]}" )
  ok "安装完成"
}

cleanup() {
  [[ -n "${tempDir}" && -d "${tempDir}" ]] && rm -rf "${tempDir}" || true
}

declare -a forwardArgs

main() {
  parseArgs "$@"
  requireRoot
  ensureGit
  trap cleanup EXIT
  cloneRepo
  runInstall
}

main "$@"
