#!/usr/bin/env bash
#
# 从 GitHub Releases 安装 V2bX（免 Git）
# 功能：
# - 系统与架构检测（Linux x86_64/arm64）
# - 自动获取 GitHub 最新/指定版本的发布资产并下载
# - 安装到系统路径 /usr/local/bin/V2bX
# - 创建基础配置目录与模板 /etc/v2bx/config.json
# - 创建并启用 systemd 服务 v2bx.service
# - 详细中文提示与常见错误处理
#
# 用法示例：
#   sudo bash scripts/install-from-releases.sh                          # 安装最新版本
#   sudo bash scripts/install-from-releases.sh --version v1.2.3         # 安装指定版本 tag
#   sudo bash scripts/install-from-releases.sh --dry-run                # 仅演示，不实际安装

set -euo pipefail

red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

repoOwner="yonovice"
repoName="V2bX"
versionTag=""   # 空表示 latest
dryRun=false

printUsage() {
  cat <<EOF
用法：sudo bash scripts/install-from-releases.sh [--version <tag>] [--dry-run]

选项：
  --version <tag>   指定发布版本（例如 v1.2.3），缺省为最新发布
  --dry-run         仅演示下载与安装路径，不实际写入系统

安装路径：
  二进制：/usr/local/bin/V2bX
  配置：  /etc/v2bx/config.json
  日志：  /var/log/v2bx/
  服务：  /etc/systemd/system/v2bx.service

示例：
  sudo bash scripts/install-from-releases.sh
  sudo bash scripts/install-from-releases.sh --version v1.2.3
EOF
}

requireRoot() {
  if [[ $(id -u) -ne 0 ]]; then
    err "请以 root 用户运行此脚本。"; exit 1
  fi
}

detectOSArch() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  case "$os" in
    linux) ;; 
    *) err "暂不支持当前系统：$os（仅支持 Linux）"; exit 1;;
  esac
  case "$arch" in
    x86_64|amd64) arch="amd64";;
    aarch64|arm64) arch="arm64";;
    *) err "暂不支持当前架构：$arch（仅支持 amd64/arm64）"; exit 1;;
  esac
  ok "系统：$os，架构：$arch"
}

ensureFetcher() {
  # 需要 curl 或 wget 之一
  if command -v curl >/dev/null 2>&1; then
    fetcher="curl"
  elif command -v wget >/dev/null 2>&1; then
    fetcher="wget"
  else
    warn "未检测到 curl/wget，尝试自动安装下载工具..."
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y curl >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
      yum install -y curl >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y curl >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
      apk add --no-cache curl >/dev/null 2>&1 || true
    elif command -v pacman >/dev/null 2>&1; then
      pacman -Sy --noconfirm curl >/dev/null 2>&1 || true
    elif command -v zypper >/dev/null 2>&1; then
      zypper install -y curl >/dev/null 2>&1 || true
    fi
    if command -v curl >/dev/null 2>&1; then fetcher="curl"; else
      if command -v wget >/dev/null 2>&1; then fetcher="wget"; else
        err "无法安装 curl/wget，请手动安装后重试。"; exit 1
      fi
    fi
  fi
}

getLatestReleaseUrl() {
  # 使用 GitHub API 获取最新发布的资产 URL，匹配包含 linux 与架构的文件名
  apiUrl="https://api.github.com/repos/${repoOwner}/${repoName}/releases/latest"
  if [[ "$fetcher" == "curl" ]]; then
    body=$(curl -sL "$apiUrl")
  else
    body=$(wget -qO- "$apiUrl")
  fi
  # 提取所有资产下载地址
  # 这里尝试匹配常见命名：linux-amd64、linux_arm64、amd64、arm64 等
  downloadUrl=$(echo "$body" | sed -n 's/.*"browser_download_url": "\([^"]*\)".*/\1/p' | \
    grep -i 'linux' | grep -Ei "${arch}|amd64|x86_64|arm64|aarch64" | head -n1 || true)
  if [[ -z "$downloadUrl" ]]; then
    warn "未找到匹配系统与架构的发布资产。可能尚未提供 Releases。"
    return 1
  fi
  echo "$downloadUrl"
}

getTaggedReleaseUrl() {
  apiUrl="https://api.github.com/repos/${repoOwner}/${repoName}/releases/tags/${versionTag}"
  if [[ "$fetcher" == "curl" ]]; then
    body=$(curl -sL "$apiUrl")
  else
    body=$(wget -qO- "$apiUrl")
  fi
  downloadUrl=$(echo "$body" | sed -n 's/.*"browser_download_url": "\([^"]*\)".*/\1/p' | \
    grep -i 'linux' | grep -Ei "${arch}|amd64|x86_64|arm64|aarch64" | head -n1 || true)
  if [[ -z "$downloadUrl" ]]; then
    warn "未找到匹配系统与架构的发布资产（tag: ${versionTag}）。"
    return 1
  fi
  echo "$downloadUrl"
}

downloadAndInstall() {
  local url="$1"
  local tmpFile
  tmpFile="$(mktemp -t v2bx-asset-XXXXXX)"
  ok "开始下载发布资产：$url"
  if [[ "$fetcher" == "curl" ]]; then
    curl -L "$url" -o "$tmpFile"
  else
    wget -O "$tmpFile" "$url"
  fi
  # 判断文件类型：可能是压缩包或裸二进制
  fileType=$(file -b "$tmpFile" || echo "")
  installBin="/usr/local/bin/V2bX"
  if echo "$fileType" | grep -qi "archive\|compressed"; then
    workDir="$(mktemp -d -t v2bx-unpack-XXXXXX)"
    ok "检测到压缩包，解压到临时目录：$workDir"
    tar -xf "$tmpFile" -C "$workDir" || unzip -o "$tmpFile" -d "$workDir" || true
    # 寻找 V2bX 可执行文件
    binPath=$(find "$workDir" -type f -name 'V2bX' -perm -u+x | head -n1 || true)
    if [[ -z "$binPath" ]]; then
      # 尝试非可执行文件名
      binPath=$(find "$workDir" -type f -name 'V2bX' | head -n1 || true)
    fi
    if [[ -z "$binPath" ]]; then
      err "压缩包中未找到 V2bX 可执行文件。"; exit 1
    fi
    if [[ "$dryRun" == true ]]; then
      ok "[dry-run] 将安装 $binPath 到 $installBin"
    else
      install -m 0755 "$binPath" "$installBin"
    fi
    rm -rf "$workDir"
  else
    ok "检测到二进制文件"
    if [[ "$dryRun" == true ]]; then
      ok "[dry-run] 将安装 $tmpFile 到 $installBin"
    else
      install -m 0755 "$tmpFile" "$installBin"
    fi
  fi
  rm -f "$tmpFile"
  ok "二进制安装完成：$installBin"
}

setupConfigAndService() {
  configDir="/etc/v2bx"
  logDir="/var/log/v2bx"
  serviceFile="/etc/systemd/system/v2bx.service"
  [[ "$dryRun" == true ]] && ok "[dry-run] 创建配置与服务文件" && return 0
  mkdir -p "$configDir" "$logDir"
  cat > "$configDir/config.json" <<'JSON'
{
  "Log": {
    "Level": "info",
    "AccessPath": "/var/log/v2bx/access.log",
    "ErrorPath": "/var/log/v2bx/error.log"
  },
  "Nodes": [
    {
      "PanelType": "V2board",
      "ApiHost": "https://panel.example.com",
      "ApiKey": "replace-with-your-api-key",
      "NodeID": 1,
      "Core": "xray",
      "ListenIP": "0.0.0.0"
    }
  ]
}
JSON
  ok "基础配置模板生成：$configDir/config.json"
  cat > "$serviceFile" <<'SERVICE'
[Unit]
Description=V2bX Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/V2bX server -c /etc/v2bx/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICE
  ok "systemd 服务文件生成：$serviceFile"
  systemctl daemon-reload
  systemctl enable v2bx || true
}

startService() {
  if [[ "$dryRun" == true ]]; then
    ok "[dry-run] 将启动 v2bx 服务"
  else
    systemctl start v2bx || {
      warn "服务启动失败，请通过 'journalctl -u v2bx -e' 查看日志。"
      exit 1
    }
    ok "v2bx 服务已启动。查看状态：systemctl status v2bx"
  fi
}

parseArgs() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) versionTag="$2"; shift 2 ;;
      --dry-run) dryRun=true; shift 1 ;;
      -h|--help) printUsage; exit 0 ;;
      *) warn "未知参数：$1"; shift 1 ;;
    esac
  done
}

main() {
  parseArgs "$@"
  requireRoot
  detectOSArch
  ensureFetcher
  url=""
  if [[ -n "$versionTag" ]]; then
    ok "获取指定版本发布资产：$versionTag"
    url=$(getTaggedReleaseUrl) || true
  else
    ok "获取最新版本发布资产"
    url=$(getLatestReleaseUrl) || true
  fi
  if [[ -z "$url" ]]; then
    err "未获取到可用的发布资产。可能该仓库尚未发布 Releases。\n可改用：scripts/install-from-github.sh（自动拉取源码安装）。"; exit 1
  fi
  downloadAndInstall "$url"
  setupConfigAndService
  startService
  ok "安装完成。如需添加节点：V2bX add-node --panel-url <url> --api-key <key> --node-id <id> --port <port> --core xray"
}

main "$@"