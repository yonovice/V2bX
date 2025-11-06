#!/usr/bin/env bash
#
# 推送本项目到 GitHub 的辅助脚本
# 功能：
# - 检查/初始化 git 仓库
# - 可选创建/补充 .gitignore
# - 添加所有文件并提交
# - 配置远程仓库并推送到指定分支
#
# 使用示例：
#   bash scripts/push-to-github.sh --repo https://github.com/<user>/<repo>.git --branch main

set -euo pipefail

red="\033[0;31m"; green="\033[0;32m"; yellow="\033[0;33m"; plain="\033[0m"
err() { echo -e "${red}$*${plain}"; }
ok() { echo -e "${green}$*${plain}"; }
warn() { echo -e "${yellow}$*${plain}"; }

projectRootDir="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
branchName="main"
repoUrl=""

printUsage() {
  cat <<EOF
用法：bash scripts/push-to-github.sh --repo <url> [--branch <name>]

参数：
  --repo <url>     GitHub 仓库地址（如：https://github.com/user/repo.git）
  --branch <name>  推送的分支名（默认：main）
EOF
}

parseArgs() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repoUrl="$2"; shift 2 ;;
      --branch) branchName="$2"; shift 2 ;;
      -h|--help) printUsage; exit 0 ;;
      *) warn "未知参数：$1"; shift 1 ;;
    esac
  done
  if [[ -z "${repoUrl}" ]]; then
    err "必须提供 --repo <url>"; printUsage; exit 1
  fi
}

ensureGit() {
  if ! command -v git >/dev/null 2>&1; then
    err "未检测到 git，请先安装 git 后再执行。"; exit 1
  fi
}

initRepoIfNeeded() {
  cd "${projectRootDir}"
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ok "未检测到 git 仓库，开始初始化"
    git init
    # 创建默认分支
    git checkout -b "${branchName}" || true
  else
    ok "已检测到 git 仓库"
  fi
}

prepareGitignore() {
  cd "${projectRootDir}"
  if [[ ! -f .gitignore ]]; then
    warn ".gitignore 不存在，创建默认文件"
    cat > .gitignore <<'EOF'
# 通用忽略
.DS_Store
node_modules/
dist/
output/
.idea/
.vscode/
*.log
*.tmp

# Go / 构建产物
V2bX
example/*.logo
example/cert/
api/chooseparser.go.bak
EOF
  fi
}

commitAll() {
  cd "${projectRootDir}"
  git add -A
  if git rev-parse HEAD >/dev/null 2>&1; then
    git commit -m "chore: sync project" || warn "无变更可提交"
  else
    git commit -m "chore: initial commit"
  fi
}

setupRemoteAndPush() {
  cd "${projectRootDir}"
  # 设置远程
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "${repoUrl}"
  else
    git remote add origin "${repoUrl}"
  fi
  # 确保在目标分支
  currentBranch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "${currentBranch}" != "${branchName}" ]]; then
    git checkout -B "${branchName}"
  fi
  ok "开始推送到 ${repoUrl} (${branchName})"
  git push -u origin "${branchName}"
  ok "推送成功"
}

main() {
  parseArgs "$@"
  ensureGit
  initRepoIfNeeded
  prepareGitignore
  commitAll
  setupRemoteAndPush
}

main "$@"