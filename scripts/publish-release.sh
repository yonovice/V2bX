#!/usr/bin/env bash
#
# 创建 GitHub Release 并上传发行资产（需要 gh CLI 或 GitHub Token）
# - 默认使用 gh CLI：gh release create <tag> <assets...> --title --notes
# - 也可使用 GITHUB_TOKEN 环境变量调用 API（简化版占位，不建议非交互）
#
# 用法：
#   bash scripts/publish-release.sh --version v1.0.0 --assets dist/*.tar.gz --title "V2bX v1.0.0" --notes "更新说明..."

set -euo pipefail

red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

versionTag=""
title=""
notes=""
assets=()

printUsage() {
  cat <<EOF
用法：bash scripts/publish-release.sh --version <tag> --assets <glob> [--title "..."] [--notes "..."]

示例：
  bash scripts/publish-release.sh --version v1.0.0 --assets dist/*.tar.gz --title "V2bX v1.0.0" --notes "更新说明..."
EOF
}

parseArgs() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) versionTag="$2"; shift 2 ;;
      --assets) shift 1; while [[ $# -gt 0 && "$1" != --* ]]; do assets+=("$1"); shift 1; done ;;
      --title) title="$2"; shift 2 ;;
      --notes) notes="$2"; shift 2 ;;
      -h|--help) printUsage; exit 0 ;;
      *) warn "未知参数：$1"; shift 1 ;;
    esac
  done
}

requireGh() {
  if ! command -v gh >/dev/null 2>&1; then
    err "未检测到 gh CLI，请安装后再执行：https://cli.github.com/"; exit 1
  fi
}

main() {
  parseArgs "$@"
  if [[ -z "$versionTag" ]]; then err "必须提供 --version <tag>"; exit 1; fi
  if [[ ${#assets[@]} -eq 0 ]]; then err "必须提供 --assets <文件列表>"; exit 1; fi
  requireGh
  ok "创建 Release：$versionTag"
  gh release create "$versionTag" "${assets[@]}" --title "${title:-V2bX ${versionTag}}" --notes "${notes:-自动发布}" || {
    err "创建 Release 失败，请检查 gh 登录与权限。"; exit 1
  }
  ok "发布完成：$versionTag"
}

main "$@"