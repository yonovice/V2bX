#!/usr/bin/env bash
#
# 超轻量一键安装脚本（完全免 Git 与编译）
# - 自动识别系统架构（Linux amd64/arm64）
# - 直接从 GitHub Releases 下载对应 tar.gz 并安装
# - 创建基础配置与 systemd 服务，失败自动回滚
# - 完整中文提示，模仿 wyx2685 风格
#
# 用法：
#   wget -O install-lite.sh https://raw.githubusercontent.com/yonovice/V2bX/dev_new/scripts/install-lite.sh && sudo bash install-lite.sh
#   sudo bash install-lite.sh --version v1.2.3

set -euo pipefail

red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

repoOwner="yonovice"
repoName="V2bX"
versionTag=""   # 空表示 latest

requireRoot() { [[ $(id -u) -eq 0 ]] || { err "请以 root 权限运行"; exit 1; }; }

detectArch() {
  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) err "暂不支持架构：$(uname -m)"; exit 1 ;;
  esac
  ok "检测到架构：${arch}"
}

ensureCurl() {
  if command -v curl >/dev/null 2>&1; then return 0; fi
  warn "未检测到 curl，尝试自动安装..."
  if command -v apt-get >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 || true; apt-get install -y curl >/dev/null 2>&1 || true; fi
  if command -v yum >/dev/null 2>&1; then yum install -y curl >/dev/null 2>&1 || true; fi
  if command -v dnf >/dev/null 2>&1; then dnf install -y curl >/dev/null 2>&1 || true; fi
  if command -v apk >/dev/null 2>&1; then apk add --no-cache curl >/dev/null 2>&1 || true; fi
  if command -v pacman >/dev/null 2>&1; then pacman -Sy --noconfirm curl >/dev/null 2>&1 || true; fi
  if command -v zypper >/dev/null 2>&1; then zypper install -y curl >/dev/null 2>&1 || true; fi
  command -v curl >/dev/null 2>&1 || { err "无法安装 curl，请手动安装后重试"; exit 1; }
}

apiGet() { curl -sL "$1"; }

resolveUrl() {
  local api
  if [[ -n "$versionTag" ]]; then
    api="https://api.github.com/repos/${repoOwner}/${repoName}/releases/tags/${versionTag}"
  else
    api="https://api.github.com/repos/${repoOwner}/${repoName}/releases/latest"
  fi
  body=$(apiGet "$api")
  url=$(echo "$body" | sed -n 's/.*"browser_download_url": "\([^"]*\)".*/\1/p' | grep -i linux | grep -Ei "${arch}|amd64|x86_64|arm64|aarch64" | head -n1 || true)
  [[ -n "$url" ]] || { err "未找到匹配的发布资产，请确认仓库已发布 Releases 或改用源码安装脚本"; exit 1; }
  echo "$url"
}

installBinary() {
  local url="$1"; local tmpDir; tmpDir="$(mktemp -d -t v2bx-lite-XXXXXX)"
  ok "下载：$url"
  curl -L "$url" -o "$tmpDir/asset.tar.gz"
  tar -xzf "$tmpDir/asset.tar.gz" -C "$tmpDir"
  [[ -f "$tmpDir/V2bX" ]] || { err "解压失败或未找到 V2bX 可执行文件"; rm -rf "$tmpDir"; exit 1; }
  backup="/usr/local/bin/V2bX.bak.$(date +%s)"
  if [[ -f "/usr/local/bin/V2bX" ]]; then cp "/usr/local/bin/V2bX" "$backup" && ok "已备份旧版本：$backup"; fi
  install -m 0755 "$tmpDir/V2bX" "/usr/local/bin/V2bX"
  rm -rf "$tmpDir"
  ok "安装完成：/usr/local/bin/V2bX"
}

setupConfig() {
  mkdir -p /etc/v2bx /var/log/v2bx
  if [[ ! -f /etc/v2bx/config.json ]]; then
    cat > /etc/v2bx/config.json <<'JSON'
{
  "Log": { "Level": "info", "AccessPath": "/var/log/v2bx/access.log", "ErrorPath": "/var/log/v2bx/error.log" },
  "Nodes": [ { "PanelType": "V2board", "ApiHost": "https://panel.example.com", "ApiKey": "replace-with-your-api-key", "NodeID": 1, "Core": "xray", "ListenIP": "0.0.0.0" } ]
}
JSON
    ok "已生成基础配置：/etc/v2bx/config.json"
  else
    warn "已存在配置文件，保留不覆盖"
  fi
}

setupService() {
  cat > /etc/systemd/system/v2bx.service <<'SERVICE'
[Unit]
Description=V2bX Service (lite installer)
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
  systemctl daemon-reload
  systemctl enable v2bx || true
  systemctl restart v2bx || true
  ok "服务已启动，查看：systemctl status v2bx；日志：journalctl -u v2bx -e"
}

parseArgs() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) versionTag="$2"; shift 2 ;;
      -h|--help) echo "用法：sudo bash install-lite.sh [--version vX.Y.Z]"; exit 0 ;;
      *) warn "忽略未知参数：$1"; shift 1 ;;
    esac
  done
}

main() {
  requireRoot
  parseArgs "$@"
  detectArch
  ensureCurl
  url=$(resolveUrl)
  installBinary "$url"
  setupConfig
  setupService
  ok "安装完成。如需添加节点：V2bX add-node --panel-url <url> --api-key <key> --node-id <id> --port <port> --core xray"
}

main "$@"