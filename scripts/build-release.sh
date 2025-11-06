#!/usr/bin/env bash
#
# 构建多架构发行包（Linux amd64/arm64），生成 tar.gz 与校验文件
# - 依赖 Go（>=1.23），本地已验证 GOEXPERIMENT=jsonv2 可构建
# - 输出目录默认为 dist/
# - 支持通过 --version 设置版本号（用于包名与校验文件标注）
# - 支持通过 --tags 指定内核编译标签（默认包含 sing/xray/hysteria2 及常用扩展）
#
# 用法示例：
#   bash scripts/build-release.sh --version v1.0.0
#   bash scripts/build-release.sh --version v1.0.0 --out dist --tags "sing xray hysteria2"

set -euo pipefail

red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

outDir="dist"
versionTag=""
buildTags="sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor"

printUsage() {
  cat <<EOF
用法：bash scripts/build-release.sh [--version <tag>] [--out <dir>] [--tags "..."]

参数：
  --version <tag>   版本号（例如 v1.2.3），会用于包名标注
  --out <dir>       输出目录，默认 dist/
  --tags "..."      Go 构建标签，默认：${buildTags}

示例：
  bash scripts/build-release.sh --version v1.0.0
  bash scripts/build-release.sh --version v1.0.0 --out dist --tags "sing xray hysteria2"
EOF
}

parseArgs() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) versionTag="$2"; shift 2 ;;
      --out) outDir="$2"; shift 2 ;;
      --tags) buildTags="$2"; shift 2 ;;
      -h|--help) printUsage; exit 0 ;;
      *) warn "未知参数：$1"; shift 1 ;;
    esac
  done
}

ensureGo() {
  if ! command -v go >/dev/null 2>&1; then
    err "未检测到 go，请先安装 Go (>=1.23)。"; exit 1
  fi
}

buildArch() {
  local arch="$1"; local outName="V2bX-linux-${arch}"
  ok "开始构建：GOOS=linux GOARCH=${arch}"
  GOOS=linux GOARCH="${arch}" GOEXPERIMENT=jsonv2 \
    go build -v -o "${outDir}/${outName}/V2bX" \
    -tags "${buildTags}" -trimpath \
    -ldflags "-X 'github.com/InazumaV/V2bX/cmd.version=${versionTag}' -s -w -buildid=" \
    ./
  ok "构建完成：${outDir}/${outName}/V2bX"
}

packageArch() {
  local arch="$1"; local outName="V2bX-linux-${arch}"
  (cd "${outDir}/${outName}" && tar -czf "../${outName}-${versionTag:-latest}.tar.gz" V2bX)
  ok "打包完成：${outDir}/${outName}-${versionTag:-latest}.tar.gz"
}

checksumAll() {
  (cd "${outDir}" && sha256sum *.tar.gz > "SHA256SUMS-${versionTag:-latest}.txt")
  ok "校验文件生成：${outDir}/SHA256SUMS-${versionTag:-latest}.txt"
}

main() {
  parseArgs "$@"
  ensureGo
  mkdir -p "${outDir}/V2bX-linux-amd64" "${outDir}/V2bX-linux-arm64"
  buildArch amd64
  buildArch arm64
  packageArch amd64
  packageArch arm64
  checksumAll
  ok "全部完成，输出目录：${outDir}"
}

main "$@"