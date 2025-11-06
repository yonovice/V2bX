# V2bX（yonovice 维护版）

一个基于多内核的 V2board 节点服务端，源自 XrayR 并在原版 V2bX 的基础上进行了部署脚本增强、日志轮转与服务管理优化，支持 Vmess/Vless、Trojan、Shadowsocks、Hysteria1/2 等协议。

维护者：`yonovice` ｜ 仓库地址：`https://github.com/yonovice/V2bX.git`

> 说明：本项目需搭配修改版 V2board 使用；本维护版聚焦于“可用、易用、可维护”，提供面向生产的脚本工具集，支持一键安装、更新、卸载以及服务与配置管理。

## 特性概览

- 支持 Vmess/Vless、Trojan、Shadowsocks、Hysteria1/2 多协议与 XTLS 新特性。
- 单实例多节点对接，自动热重载配置。
- 在线 IP/连接数限制、用户级与端口级限速。
- 多内核可选与条件编译，按需裁剪。
- 完整部署脚本套件：安装、卸载、更新、服务管理、配置管理。
- 日志轮转与保留策略，保障长期运行可观测性。

## 一键使用（从 GitHub 拉取）

适合在节点服务器上直接使用，自动克隆仓库并调用项目内安装脚本：

```bash
wget -O install-from-github.sh https://raw.githubusercontent.com/yonovice/V2bX/dev_new/scripts/install-from-github.sh && \
  bash install-from-github.sh --repo https://github.com/yonovice/V2bX.git --branch dev_new
```

示例（传参透传给内部 `install.sh`）：

- 指定安装目录与服务名：
```bash
bash install-from-github.sh --repo https://github.com/yonovice/V2bX.git \
  --branch dev_new --install-dir /opt/v2bx --service-name v2bx
```

## 免 Git 安装（从 Releases 下载）

如果你的服务器没有安装 git，或希望更简洁的安装方式，可直接通过 Releases 安装（自动识别系统与架构、安装到系统路径并创建服务）：

```bash
wget -O install-from-releases.sh https://raw.githubusercontent.com/yonovice/V2bX/dev_new/scripts/install-from-releases.sh && \
  sudo bash install-from-releases.sh                 # 安装最新版本（若仓库已发布）
sudo bash install-from-releases.sh --version v1.2.3  # 安装指定版本
```

如遇“未找到发布资产”提示，说明当前仓库尚未发布二进制，可改用源码安装脚本：

```bash
wget -O install-from-github.sh https://raw.githubusercontent.com/yonovice/V2bX/dev_new/scripts/install-from-github.sh && \
  bash install-from-github.sh --repo https://github.com/yonovice/V2bX.git --branch dev_new
```

## 安装脚本（本仓库自带）

`scripts/install.sh` 提供面向生产的安装流程：系统检测、Go 环境处理、构建安装、配置初始化、systemd 服务、可选防火墙、日志轮转与 `add-node` 集成。

常用参数：
```bash
# 交互式安装（默认）
bash scripts/install.sh

# 非交互，指定目录与服务名、端口开放
bash scripts/install.sh --install-dir /opt/v2bx --service-name v2bx --open-ports 443,8443

# 安装后直接注册一个节点（参数透传到 add-node）
bash scripts/install.sh --add-node --panel-url https://panel.example.com \
  --api-key xxxxxx --node-id 1 --port 443 --core xray
```

安装路径与服务：
- 二进制：`/usr/local/bin/V2bX`
- 配置目录：`/etc/v2bx/`
- 日志目录：`/var/log/v2bx/`
- systemd 服务：`v2bx.service`
- 日志轮转：`/etc/logrotate.d/v2bx`

## 服务管理脚本

`scripts/v2bx.sh`：
```bash
# 启动/停止/重启
bash scripts/v2bx.sh start|stop|restart
# 查看状态与日志
bash scripts/v2bx.sh status
bash scripts/v2bx.sh logs
# 显示配置路径
bash scripts/v2bx.sh config-path
```

## 配置管理脚本

`scripts/config.sh`：
```bash
# 备份与恢复
bash scripts/config.sh backup
bash scripts/config.sh restore <备份文件>
# 校验配置（JSON/结构）
bash scripts/config.sh validate
# 查看节点数量与展示当前配置
bash scripts/config.sh nodes-count
bash scripts/config.sh show
```

## 更新与卸载

`scripts/update.sh`：平滑更新当前二进制，保留配置与日志，重启生效。
```bash
bash scripts/update.sh --branch dev_new        # 拉取并构建当前分支最新代码
bash scripts/update.sh --version v1.2.3        # 切到指定 tag/版本并更新
```

`scripts/uninstall.sh`：完整卸载，含服务清理与可选残留文件移除。
```bash
bash scripts/uninstall.sh
```

## add-node 功能（命令行）

安装脚本支持在安装阶段直接注册节点，也可手动执行 `V2bX add-node`：
```bash
V2bX add-node \
  --panel-url https://panel.example.com \
  --api-key xxxxxx \
  --node-id 1 \
  --port 443 \
  --core xray   # 支持 xray/sing/hysteria2 等，根据场景选择
```

参数说明：
- `--panel-url`：V2board 面板地址；
- `--api-key`：面板 API 密钥；
- `--node-id`：节点 ID；
- `--port`：监听端口；
- `--core`：核心类型（例如 `xray`、`sing`、`hysteria2`）。

## 手动构建（可选）

如需自定义内核组合，可使用条件编译：
```bash
GOEXPERIMENT=jsonv2 go build -v -o build_assets/V2bX \
  -tags "sing xray hysteria2 with_quic with_grpc with_utls with_wireguard with_acme with_gvisor" \
  -trimpath -ldflags "-X 'github.com/InazumaV/V2bX/cmd.version=$version' -s -w -buildid="
```

## 与原版 V2bX 的差异

- 新增完善的部署脚本套件：一键安装、从 GitHub 拉取部署、更新、卸载、服务与配置管理。
- 内置日志轮转配置（logrotate），更适合长期运行与日志保留。
- 安装脚本集成 `add-node` 参数化，降低首次配置成本。
- `.gitignore` 增强，避免将密钥与构建产物推送到仓库。

## 使用建议与保障

- 本维护版本已在本地完成构建与脚本语法校验，确保“可用”。
- 生产环境建议使用非交互模式并固定版本分支，更新前自动备份由脚本完成。
- 请在推送前确保未包含私钥与证书文件，仓库已通过 `.gitignore` 默认排除 `node/*.pem/*.key`。

## 反馈与支持

- 问题反馈：GitHub Issues（`https://github.com/yonovice/V2bX/issues`）。
- 联系方式：请在 Issue 中留下需求与场景描述，我们将跟进。

## 贡献指南

欢迎通过 Pull Request 贡献优化与新特性：
- 保持代码与脚本注释为中文，遵循本仓库风格；
- 单点变更专注、避免无关修改；
- 提交前通过本地构建与脚本 `bash -n` 进行校验。

## 版权与免责声明

- 本项目基于原版 V2bX 与 XrayR，遵循其开源协议；
- 仅用于学习与研究，使用造成的任何后果由使用者自负；
- 如不同意上述条款，请勿在生产环境使用。
