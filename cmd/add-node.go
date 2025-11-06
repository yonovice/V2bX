package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"

	"github.com/InazumaV/V2bX/conf"
)

// addNodeCmd 定义交互式添加节点配置的子命令
// 功能：
// - 读取现有配置文件 /etc/V2bX/config.json
// - 支持命令行参数批量部署（flags）与交互式补充（fallback）
// - 根据节点类型映射对应核心（xray/sing/hysteria2）
// - 将新节点以真实结构 ApiConfig/Options 写入，不覆盖其它配置
// - 自动补全 Cores，保证运行所需核心存在
var addNodeCmd = &cobra.Command{
	Use:   "add-node",
	Short: "交互式/参数化添加节点配置，支持多协议共存与批量部署",
	Long: `向 /etc/V2bX/config.json 添加节点配置：
- 支持命令行参数（--api-host --api-key --node-id --node-type --listen-ip --tls）直接写入；
- 如缺少必要参数，自动回退为交互式提示补充；
- 自动补全所需 Cores[]，不会覆盖已有配置，实现多协议共存。`,
	RunE: runAddNode,
}

// 命令行 flags 绑定变量
var (
	flagApiHost  string
	flagApiKey   string
	flagNodeID   int
	flagNodeType string
	flagListenIP string
	flagTLSEnable bool
)

func init() {
	// 绑定到根命令（cmd.command）
	command.AddCommand(addNodeCmd)
	// 定义 flags（命令行参数）
	addNodeCmd.Flags().StringVar(&flagApiHost, "api-host", "", "面板地址，例如 https://panel.example.com")
	addNodeCmd.Flags().StringVar(&flagApiKey, "api-key", "", "面板 API 密钥")
	addNodeCmd.Flags().IntVar(&flagNodeID, "node-id", 0, "节点 ID（数字）")
	addNodeCmd.Flags().StringVar(&flagNodeType, "node-type", "", "节点类型：vless/vmess/trojan/shadowsocks/hysteria2")
	addNodeCmd.Flags().StringVar(&flagListenIP, "listen-ip", "", "监听 IP（默认 0.0.0.0）")
	addNodeCmd.Flags().BoolVar(&flagTLSEnable, "tls", false, "是否启用 TLS（默认关闭）")
}

// nodeInput 为交互式输入的临时结构
// 说明：该结构仅用于接收用户输入，不直接映射到最终配置
// 字段：
// - apiHost: 面板地址（如 https://panel.example.com）
// - apiKey: 面板 API 密钥
// - nodeID: 节点 ID（数字）
// - nodeType: 节点类型（vless/vmess/trojan/shadowsocks/hysteria2）
// - listenIP: 监听 IP（默认 0.0.0.0）
// - tlsEnable: 是否启用 TLS（y/N）
type nodeInput struct {
	ApiHost   string
	ApiKey    string
	NodeID    int
	NodeType  string
	ListenIP  string
	TLSEnable bool
}

// runAddNode 交互式/参数化添加节点配置的主流程
// 步骤：
// 1) 检查配置文件是否存在
// 2) 优先读取命令行参数；若缺少必要参数则回退交互式补充
// 3) 构造 NodeConfig（ApiConfig/Options）并更新/追加到 Nodes
// 4) 自动补全 Cores，确保必需核心存在
// 5) 按真实结构序列化并写回磁盘
func runAddNode(cmd *cobra.Command, args []string) error {
	configPath := "/etc/V2bX/config.json"

	// 若配置文件不存在则提示先初始化
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		return fmt.Errorf("配置文件不存在，请先创建 %s 或使用 install 命令初始化", configPath)
	}

	// 读取现有配置
	cfg := conf.New()
	if err := cfg.LoadFromPath(configPath); err != nil {
		return fmt.Errorf("读取配置失败: %w", err)
	}

	// 构建输入：优先使用命令行参数；必要参数缺失则回退交互式补充
	in := &nodeInput{
		ApiHost:   flagApiHost,
		ApiKey:    flagApiKey,
		NodeID:    flagNodeID,
		NodeType:  flagNodeType,
		ListenIP:  flagListenIP,
		TLSEnable: flagTLSEnable,
	}
	needPrompt := (in.ApiHost == "" || in.ApiKey == "" || in.NodeID == 0 || in.NodeType == "")
	if needPrompt {
		prompt, err := promptNodeInput()
		if err != nil {
			return err
		}
		// 用命令行已提供参数覆盖交互输入，实现部分参数回填
		if in.ApiHost != "" { prompt.ApiHost = in.ApiHost }
		if in.ApiKey != "" { prompt.ApiKey = in.ApiKey }
		if in.NodeID != 0 { prompt.NodeID = in.NodeID }
		if in.NodeType != "" { prompt.NodeType = in.NodeType }
		if in.ListenIP != "" { prompt.ListenIP = in.ListenIP }
		// tls: 命令行优先
		prompt.TLSEnable = in.TLSEnable || prompt.TLSEnable
		in = prompt
	}
	// 补默认监听 IP
	if in.ListenIP == "" { in.ListenIP = "0.0.0.0" }

	// 选择核心类型并构造新节点配置（按真实结构 ApiConfig/Options 写入）
	requiredCore := mapNodeTypeToCore(in.NodeType)
	newNode := conf.NodeConfig{
		ApiConfig: conf.ApiConfig{
			APIHost:  in.ApiHost,
			Key:      in.ApiKey,
			NodeID:   in.NodeID,
			NodeType: in.NodeType,
		},
		Options: conf.Options{
			ListenIP:   in.ListenIP,
			Core:       requiredCore,
			CertConfig: conf.NewCertConfig(),
		},
	}
	// 启用 TLS 时调整证书模式（使用 http 证书模式）
	if in.TLSEnable && newNode.Options.CertConfig != nil {
		newNode.Options.CertConfig.CertMode = "http"
	}

	// 查找是否已存在相同 NodeID 的节点（更新），否则追加
	found := false
	for i, n := range cfg.NodeConfig {
		if n.ApiConfig.NodeID == in.NodeID {
			cfg.NodeConfig[i] = newNode
			found = true
			break
		}
	}
	if !found {
		cfg.NodeConfig = append(cfg.NodeConfig, newNode)
	}

	// 自动补全所需核心配置
	ensureCores(cfg, in.NodeType)

	// 写回配置文件
	if err := saveConfig(configPath, cfg); err != nil {
		return fmt.Errorf("保存配置失败: %w", err)
	}

	fmt.Println("✅ 节点配置已安全写入，多协议共存达成！")
	return nil
}

// promptNodeInput 交互式采集节点输入
// 注意：对 listenIP 做默认值补全
func promptNodeInput() (*nodeInput, error) {
	var input nodeInput

	fmt.Print("请输入面板地址 (如 https://panel.example.com): ")
	fmt.Scanln(&input.ApiHost)

	fmt.Print("请输入 API Key: ")
	fmt.Scanln(&input.ApiKey)

	fmt.Print("请输入节点 ID (数字): ")
	fmt.Scanln(&input.NodeID)

	fmt.Print("请输入节点类型 (如 vless, vmess, trojan, shadowsocks, hysteria2): ")
	fmt.Scanln(&input.NodeType)

	fmt.Print("请输入监听 IP (默认 0.0.0.0): ")
	fmt.Scanln(&input.ListenIP)
	if input.ListenIP == "" {
		input.ListenIP = "0.0.0.0"
	}

	var tlsInput string
	fmt.Print("是否启用 TLS (y/N): ")
	fmt.Scanln(&tlsInput)
	input.TLSEnable = tlsInput == "y" || tlsInput == "Y"

	return &input, nil
}

// ensureCores 确保 Cores 中包含所需核心类型
// 规则：
// - vless/vmess/trojan -> xray
// - shadowsocks -> sing
// - hysteria2 -> hysteria2
func ensureCores(cfg *conf.Conf, nodeType string) {
	var requiredCore string
	switch nodeType {
	case "vless", "vmess", "trojan":
		requiredCore = "xray"
	case "shadowsocks":
		requiredCore = "sing"
	case "hysteria2":
		requiredCore = "hysteria2"
	default:
		requiredCore = "xray"
	}

	// 是否已存在该核心
	exists := false
	for _, c := range cfg.CoresConfig {
		if c.Type == requiredCore {
			exists = true
			break
		}
	}

	// 若不存在则追加
	if !exists {
		cfg.CoresConfig = append(cfg.CoresConfig, conf.CoreConfig{Type: requiredCore})
	}
}

// saveConfig 将配置以真实结构写回到文件
// 为避免 conf 包的自定义反序列化影响输出结构，这里定义输出结构：
// - Log: 直接使用 conf.LogConfig
// - Cores: 直接使用 []conf.CoreConfig（仅包含 Type/Name）
// - Nodes: 展平为 { ApiConfig, Options } 数组
func saveConfig(path string, cfg *conf.Conf) error {
	// 确保目录存在
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	// 生成与配置文件一致的序列化结构（Nodes 使用 ApiConfig/Options）
	type nodeOut struct {
		ApiConfig conf.ApiConfig `json:"ApiConfig"`
		Options   conf.Options   `json:"Options"`
	}
	type confOut struct {
		Log   conf.LogConfig    `json:"Log"`
		Cores []conf.CoreConfig `json:"Cores"`
		Nodes []nodeOut         `json:"Nodes"`
	}
	out := confOut{
		Log:   cfg.LogConfig,
		Cores: cfg.CoresConfig,
	}
	for _, n := range cfg.NodeConfig {
		out.Nodes = append(out.Nodes, nodeOut{ApiConfig: n.ApiConfig, Options: n.Options})
	}

	// 编码为 JSON
	data, err := json.MarshalIndent(out, "", "  ")
	if err != nil {
		return err
	}

	// 写入文件
	return os.WriteFile(path, data, 0644)
}

// mapNodeTypeToCore 将节点类型映射到核心类型
func mapNodeTypeToCore(nodeType string) string {
	switch nodeType {
	case "vless", "vmess", "trojan":
		return "xray"
	case "shadowsocks":
		return "sing"
	case "hysteria2":
		return "hysteria2"
	default:
		return "xray"
	}
}