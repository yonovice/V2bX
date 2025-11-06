#!/usr/bin/env bash
#
# V2bX 一键部署脚本（Linux）
# 功能：
# - 系统检测（架构、发行版、包管理器、systemd）
# - Go 环境检查/安装（默认安装 1.25.0）
# - 项目构建并安装到 /bin/V2bX
# - 初始化 /etc/V2bX/config.json（含 Cores、Nodes）与日志路径
# - 配置并启用 systemd 服务 V2bX.service
# - 可选防火墙放行端口（ufw / firewalld）
# - 集成 add-node：支持参数与交互式补充
# - 打印中文使用说明
#
# 使用示例：
#   bash scripts/install.sh \
#     --api-host https://panel.local --api-key abc123 \
#     --node-id 1001 --node-type vless --listen-ip 0.0.0.0 --tls
#
# 注意：请在 Linux 服务器上以 root 用户运行，macOS 不适配 systemd。

set -euo pipefail

# 颜色输出
red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

# 全局变量（驼峰命名）
projectRootDir="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
binaryInstallPath="/bin/V2bX"
configDir="/etc/V2bX"
configFilePath="${configDir}/config.json"
logFilePath="/var/log/V2bX.log"
systemdServicePath="/etc/systemd/system/V2bX.service"

pkgManager=""
firewallTool=""
linuxDistro=""
cpuArch=""

# add-node 参数（可选，用于非交互快速添加）
flagApiHost=""
flagApiKey=""
flagNodeID=""
flagNodeType=""
flagListenIP=""
flagTLSEnable="false"
flagNonInteractive="false"

printUsage() {
  cat <<EOF
用法：bash scripts/install.sh [选项]

选项：
  --api-host <URL>       面板地址，用于 add-node（示例：https://panel.local）
  --api-key <TOKEN>      面板 API 密钥（示例：abc123）
  --node-id <ID>         节点 ID（示例：1001）
  --node-type <TYPE>     节点类型（vless|vmess|trojan|shadowsocks|hysteria2）
  --listen-ip <IP>       监听 IP（默认：0.0.0.0）
  --tls                  启用 TLS（仅对需要 TLS 的协议有效）
  --non-interactive      非交互模式（若缺少必要参数，将跳过 add-node）

示例（完整参数模式）：
  bash scripts/install.sh --api-host https://panel.local --api-key abc123 \
    --node-id 1001 --node-type vless --listen-ip 0.0.0.0 --tls

脚本执行内容：
  1) 系统检测与 Go 环境安装（1.25.0）
  2) 编译 V2bX 并安装到 /bin/V2bX
  3) 初始化配置 /etc/V2bX/config.json 与日志文件
  4) 创建并启用 systemd 服务 V2bX.service
  5) 可选防火墙放行端口
  6) 集成 add-node 快速添加节点（参数或交互补充）
EOF
}

parseArgs() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --api-host) flagApiHost="$2"; shift 2 ;;
      --api-key) flagApiKey="$2"; shift 2 ;;
      --node-id) flagNodeID="$2"; shift 2 ;;
      --node-type) flagNodeType="$2"; shift 2 ;;
      --listen-ip) flagListenIP="$2"; shift 2 ;;
      --tls) flagTLSEnable="true"; shift 1 ;;
      --non-interactive) flagNonInteractive="true"; shift 1 ;;
      -h|--help) printUsage; exit 0 ;;
      *) warn "未知参数：$1"; shift 1 ;;
    esac
  done
}

requireRoot() {
  if [[ $(id -u) -ne 0 ]]; then
    err "请以 root 用户运行此脚本（sudo -i 或 su）。"; exit 1
  fi
}

detectSystem() {
  if [[ ! -f /etc/os-release ]]; then
    err "未检测到 /etc/os-release，当前系统可能不支持（需 Linux + systemd）。"; exit 1
  fi
  linuxDistro="$(. /etc/os-release; echo "${ID}")"
  local idLike="$(. /etc/os-release; echo "${ID_LIKE:-}")"
  case "${linuxDistro}" in
    ubuntu|debian)
      pkgManager="apt"; firewallTool="ufw" ;;
    centos|rhel|almalinux|rocky)
      pkgManager="yum"; firewallTool="firewalld" ;;
    arch)
      pkgManager="pacman"; firewallTool="ufw" ;;
    *)
      # 尝试根据 ID_LIKE 推断
      if [[ "${idLike}" == *"debian"* ]]; then
        pkgManager="apt"; firewallTool="ufw"
      elif [[ "${idLike}" == *"rhel"* ]] || [[ "${idLike}" == *"fedora"* ]]; then
        pkgManager="yum"; firewallTool="firewalld"
      else
        warn "未知发行版：${linuxDistro}，尝试使用通用安装逻辑。"
        pkgManager="apt"; firewallTool="ufw"
      fi
      ;;
  esac
  cpuArch="$(uname -m)"
  ok "已检测系统：distro=${linuxDistro}, pkg=${pkgManager}, firewall=${firewallTool}, arch=${cpuArch}"

  if ! command -v systemctl >/dev/null 2>&1; then
    err "未检测到 systemctl，当前系统不支持 systemd 服务管理。"; exit 1
  fi
}

installDeps() {
  case "${pkgManager}" in
    apt)
      apt update -y || true
      apt install -y curl wget tar git ca-certificates || true
      ;;
    yum)
      yum install -y curl wget tar git ca-certificates || true
      ;;
    pacman)
      pacman -Sy --noconfirm curl wget tar git ca-certificates || true
      ;;
    *) ;;
  esac
}

ensureGo() {
  local needInstall=""
  if command -v go >/dev/null 2>&1; then
    local v="$(go version | awk '{print $3}' | sed 's/go//')"
    local major="${v%%.*}"; local minorPatch="${v#*.}"; local minor="${minorPatch%%.*}"
    if [[ "${major}" -lt 1 ]] || [[ "${minor}" -lt 25 ]]; then
      warn "当前 Go 版本为 ${v}，低于 1.25.0，将进行升级安装。"; needInstall="yes"
    else
      ok "Go ${v} 已满足要求"
    fi
  else
    needInstall="yes"
  fi

  if [[ "${needInstall}" == "yes" ]]; then
    local goArch=""; local goFile=""
    case "${cpuArch}" in
      x86_64|amd64) goArch="amd64" ;;
      aarch64|arm64) goArch="arm64" ;;
      *) err "不支持的 CPU 架构：${cpuArch}"; exit 1 ;;
    esac
    goFile="go1.25.0.linux-${goArch}.tar.gz"
    ok "开始安装 Go 1.25.0 (${goArch})"
    cd /tmp
    wget -q "https://go.dev/dl/${goFile}" -O "${goFile}"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "${goFile}"
    cat >/etc/profile.d/golang.sh <<'EOP'
export PATH="/usr/local/go/bin:${PATH}"
EOP
    source /etc/profile.d/golang.sh || true
    ok "Go 1.25.0 安装完成"
  fi
}

buildAndInstall() {
  ok "开始构建 V2bX 二进制"
  cd "${projectRootDir}"
  # 确保依赖
  GOEXPERIMENT=jsonv2 go mod download
  # 构建（与 Dockerfile 保持一致的 build tags）
  GOEXPERIMENT=jsonv2 go build -v -o V2bX -tags "sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor"
  install -m 0755 V2bX "${binaryInstallPath}"
  ok "已安装到 ${binaryInstallPath}"
}

initConfig() {
  ok "初始化配置与日志目录"
  mkdir -p "${configDir}"
  mkdir -p "$(dirname "${logFilePath}")"
  touch "${logFilePath}" && chmod 0644 "${logFilePath}"

  if [[ ! -f "${configFilePath}" ]]; then
    cat >"${configFilePath}" <<EOF
{
  "Log": {
    "Level": "info",
    "Output": "${logFilePath}"
  },
  "Cores": [
    {
      "Type": "xray",
      "Name": "xray-default",
      "Log": { "Level": "warning", "AccessPath": "", "ErrorPath": "" },
      "AssetPath": "${configDir}/",
      "DnsConfigPath": "",
      "InboundConfigPath": "",
      "OutboundConfigPath": "",
      "RouteConfigPath": "",
      "XrayConnectionConfig": { "handshake": 4, "connIdle": 30, "uplinkOnly": 2, "downlinkOnly": 4, "bufferSize": 64 }
    },
    {
      "Type": "sing",
      "Name": "sing-default",
      "Log": { "Disable": false, "Level": "error", "Output": "", "Timestamp": true },
      "NTP": { "Enable": false, "Server": "time.apple.com", "ServerPort": 0 },
      "OriginalPath": ""
    }
  ],
  "Nodes": []
}
EOF
    ok "配置文件已创建：${configFilePath}"
  else
    warn "检测到已存在配置文件：${configFilePath}，将保留现有内容"
  fi
}

setupLogrotate() {
  ok "写入 logrotate 配置"
  cat >/etc/logrotate.d/V2bX <<EOF
${logFilePath} {
    daily
    rotate 14
    compress
    missingok
    notifempty
    copytruncate
}
EOF
}

setupSystemd() {
  ok "配置 systemd 服务单元"
  cat >"${systemdServicePath}" <<EOF
[Unit]
Description=V2bX Service
After=network.target

[Service]
Type=simple
ExecStart=${binaryInstallPath} server --config ${configFilePath}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
User=root
WorkingDirectory=${configDir}
Environment=XRAY_DNS_PATH=${configDir}/xray-dns.json
Environment=SING_DNS_PATH=${configDir}/sing-dns.json

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable V2bX.service
  systemctl restart V2bX.service || systemctl start V2bX.service
  ok "systemd 服务已启用并启动：V2bX.service"
}

configureFirewall() {
  warn "是否需要放行端口到防火墙？(Y/n)"
  local yes="Y"
  read -r -p "请输入选择: " yes || true
  if [[ -z "${yes}" ]] || [[ "${yes}" == "Y" ]] || [[ "${yes}" == "y" ]]; then
    read -r -p "请输入要放行的端口列表(逗号分隔，如 80,443,5000): " ports || true
    if [[ -n "${ports:-}" ]]; then
      case "${firewallTool}" in
        ufw)
          if ! command -v ufw >/dev/null 2>&1; then
            [[ "${pkgManager}" == "apt" ]] && apt install -y ufw || true
            [[ "${pkgManager}" == "pacman" ]] && pacman -Sy --noconfirm ufw || true
          fi
          ufw enable || true
          IFS=',' read -ra plist <<<"${ports}"
          for p in "${plist[@]}"; do
            ufw allow "$(echo "$p" | xargs)" || true
          done
          ufw status || true
          ;;
        firewalld)
          if ! command -v firewall-cmd >/dev/null 2>&1; then
            [[ "${pkgManager}" == "yum" ]] && yum install -y firewalld || true
            systemctl enable --now firewalld || true
          fi
          IFS=',' read -ra plist <<<"${ports}"
          for p in "${plist[@]}"; do
            firewall-cmd --permanent --add-port="$(echo "$p" | xargs)/tcp" || true
            firewall-cmd --permanent --add-port="$(echo "$p" | xargs)/udp" || true
          done
          firewall-cmd --reload || true
          firewall-cmd --list-ports || true
          ;;
        *) warn "未识别的防火墙工具：${firewallTool}" ;;
      esac
      ok "防火墙端口放行完成"
    else
      warn "未提供端口列表，跳过防火墙配置"
    fi
  else
    warn "已选择不配置防火墙"
  fi
}

runAddNode() {
  # 若提供完整参数，直接调用；否则进入交互式补充
  local cmd=("${binaryInstallPath}" add-node)
  [[ -n "${flagApiHost}" ]] && cmd+=("--api-host" "${flagApiHost}")
  [[ -n "${flagApiKey}" ]] && cmd+=("--api-key" "${flagApiKey}")
  [[ -n "${flagNodeID}" ]] && cmd+=("--node-id" "${flagNodeID}")
  [[ -n "${flagNodeType}" ]] && cmd+=("--node-type" "${flagNodeType}")
  [[ -n "${flagListenIP}" ]] && cmd+=("--listen-ip" "${flagListenIP}")
  [[ "${flagTLSEnable}" == "true" ]] && cmd+=("--tls")

  if [[ "${flagNonInteractive}" == "true" ]]; then
    # 非交互模式：若缺少必要参数则跳过
    if [[ -z "${flagApiHost}" || -z "${flagApiKey}" || -z "${flagNodeID}" || -z "${flagNodeType}" ]]; then
      warn "非交互模式缺少必要参数，跳过 add-node"
      return 0
    fi
    ok "执行 add-node（非交互）"
    "${cmd[@]}" || err "add-node 执行失败"
  else
    ok "执行 add-node（交互回退支持）"
    "${cmd[@]}" || err "add-node 执行失败"
  fi
}

finalTips() {
  cat <<EOF
------------------------------------------------------------
部署完成！常用命令与说明：

- 查看版本：         ${binaryInstallPath} version
- 服务控制：         ${binaryInstallPath} start | stop | restart | log
- 直接运行服务：     ${binaryInstallPath} server --config ${configFilePath}
- 添加节点：         ${binaryInstallPath} add-node --help
- 配置文件路径：     ${configFilePath}
- 日志文件路径：     ${logFilePath}
- systemd 单元：     ${systemdServicePath}

注意事项：
- 若写入 ${configFilePath} 报权限，请使用 root 运行或调整所有者：
  chown root ${configFilePath} && chmod 0644 ${configFilePath}
- add-node 支持命令行与交互回退，已自动补全 Cores 保证多协议共存。
- 生产环境建议为 ${logFilePath} 配置日志轮转（logrotate）。
------------------------------------------------------------
EOF
}

main() {
  parseArgs "$@"
  requireRoot
  detectSystem
installDeps
ensureGo
buildAndInstall
initConfig
  setupLogrotate
  setupSystemd
  configureFirewall
  runAddNode || true
  finalTips
  ok "V2bX 一键部署任务已完成"
}

main "$@"
