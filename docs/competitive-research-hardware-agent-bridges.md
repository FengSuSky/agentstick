# 调研简报:端侧硬件(M5Stack/ESP32) × 桌面 AI Agent(Claude Code/Codex)赛道

- 调研时间:2026-07-24
- 调研方法:多 agent 深度调研(5 个搜索角度、22 个信源、93 条声明提取、25 条声明三票制交叉验证)
- 触发背景:对标 [HermannBjorgvin/Clawdmeter](https://github.com/HermannBjorgvin/Clawdmeter),为 voicestick(ESP32 语音交互硬件项目)做赛道调研

## 结论先行

Clawdmeter 不是孤例,这是一条已经分化出至少 **5 类技术路线**的赛道,且已出现与 voicestick 定位几乎重合的项目——`palmdaemon/claude-code-stick`(语音输入 + 物理按钮审批,M5Stack StickS3)。voicestick 的差异化空间在于:官方协议目前只做"状态展示 + 审批",尚未把语音交互作为一等公民;而现有语音向项目大多是纯软件(如 hns),硬件语音项目又刚起步、生态很浅——这正是窗口期。

## 一、Clawdmeter 本身

| 维度 | 内容 |
|---|---|
| 定位 | ESP32 桌面仪表盘,展示 Claude Code 用量/rate limit,吉祥物随用量逼近上限而"焦躁" |
| 硬件 | Waveshare ESP32-S3 AMOLED 屏(约 $32) |
| 数据获取 | 桌面 Bash daemon 读取本地 OAuth token(Keychain/凭据文件),每 60 秒调用一次 Anthropic API,**从响应头解析** rate-limit 数据(非官方文档化字段) |
| 通信 | 自定义 BLE GATT 特征值推送 JSON,设备端 LVGL 渲染;串口仅用于一次性刷机 |
| 交互 | 物理按键伪装成标准 **BLE HID 键盘**,直接发送 Space/Shift+Tab,对任何有焦点窗口生效,不走 Claude Code 插件/MCP |
| 热度 | 约 1.1k~1.7k star(不同信源统计时间点不同),2025 年 11 月上线,最近 push 2026-07-23 |
| 来源 | [GitHub](https://github.com/HermannBjorgvin/Clawdmeter) · [CNX Software 技术拆解](https://www.cnx-software.com/2026/05/14/clawdmeter-a-diy-esp32-s3-desk-dashboard-for-claude-code-token-usage-monitoring/) · [TechCrunch 2026-05-14](https://techcrunch.com/2026/05/14/clawdmeter-turns-your-claude-code-usage-stats-into-a-tiny-desktop-dashboard/) |

## 二、同赛道全景(按技术路线分类)

| 路线 | 代表项目 | 硬件 | 与 Agent 的通信方式 | 定位 |
|---|---|---|---|---|
| 凭据劫持 + API 轮询 + BLE | [Clawdmeter](https://github.com/HermannBjorgvin/Clawdmeter)、[Claudial](https://github.com/Moge800/Claudial) | ESP32-S3 屏 / M5Stack Dial(带旋钮) | 自定义 BLE GATT,daemon 轮询 API 响应头 | 用量监控,Claudial 支持转旋钮实时调阈值 |
| **官方协议** | [anthropics/claude-desktop-buddy](https://github.com/anthropics/claude-desktop-buddy)(2463★)、[espressif/esp-desktop-buddy](https://github.com/espressif/esp-desktop-buddy) SDK | 参考硬件 M5StickC Plus | 标准化 BLE(Nordic UART),官方定义协议,默认关闭需手动开启 Developer Mode | 会话开始/结束、审批请求同步到桌面宠物,可在设备上批准/拒绝;**无语音通道** |
| **官方协议的社区衍生** | [palmdaemon/claude-code-stick](https://github.com/palmdaemon/claude-code-stick) | M5Stack StickS3(ESP32-S3-PICO + ES8311 麦克风 + 屏) | fork 自 claude-desktop-buddy 固件 | **物理按钮审批 + 语音输入**——目前搜到与 voicestick 定位最接近的项目 |
| | [TaoXieSZ/claude-code-buddy](https://github.com/TaoXieSZ/claude-code-buddy) | M5StickC Plus2 + BugC2 机器人底盘 | BLE,统一线协议镜像 Claude Desktop/Code/Cursor 三种客户端状态 | "一套协议、多 agent 通吃"思路 |
| | [houxiaomu/m5stack-coding-toys](https://github.com/houxiaomu/m5stack-coding-toys)、[alonw0/claude-monitor-esp32](https://github.com/alonw0/claude-monitor-esp32) | M5Stack CoreS3 / 任意 ESP32+OLED | 日志/hooks 轮询 | 纯状态镜像,无交互 |
| 软件层多界面桥接 | [puritysb/AgentDeck](https://github.com/puritysb/AgentDeck) | 支持 22 种界面(含 ESP32 面板、平板、墨水屏) | 原生 hooks(Claude Code/Codex)+ SSE(OpenCode)→ 中央守护进程 → WebSocket 广播 | 多设备/多 agent 通吃,ESP32 只是其中一种界面 |
| MCP-over-transport | [quantumnic/mcpd](https://github.com/quantumnic/mcpd) | ESP32/RP2000 | MCU 跑 MCP Server 组件,host 端 Python 桥接转译为 Streamable HTTP(注意:并非 MCU 直连,存在 host 桥接层) | 让硬件外设(GPIO/传感器)变成 Agent 可调用的工具 |
| | [es617/serial-mcp-server](https://github.com/es617/serial-mcp-server) | 任意串口设备 | host 端标准 MCP Server,把串口读写、复位控制线暴露为 MCP 工具 | Agent 主动控制硬件,而非硬件推送状态 |
| Codex 专属物理控制器 | [M5Stack Core2 复刻 Codex Micro](https://www.cnx-software.com/2026/07/18/m5stack-core2-gets-open-source-firmware-to-reproduce-openais-codex-micro-features/)(2026-07-18) | M5Stack Core2(约 $59.9,对比原版 Codex Micro $230) | 固件把设备模拟成 BLE vendor HID,被 ChatGPT/Codex 桌面应用原生识别 | 六个 agent 键+六个命令键+摇杆+拨盘,复刻 Work Louder Codex Micro 硬件控制器 |
| 纯软件语音(非硬件) | [hns](https://github.com/primaprashant/hns) | 无 | shell command substitution 把转录文本注入 Claude Code/Codex CLI/Cursor CLI | 与硬件赛道不相交,仅在"语音驱动 coding agent"场景有交集 |

## 三、值得重点关注的两个信号

1. **`palmdaemon/claude-code-stick`** 是目前唯一把"语音输入 + 物理按钮审批"结合在 M5Stack 上的项目,命名(`*-stick`)和硬件形态都与 voicestick 高度相似,建议直接去读它的语音链路实现(ES8311 麦克风采集 → 编码 → 传输方式),这是最直接的对标对象。
2. **官方 `claude-desktop-buddy`/`esp-desktop-buddy`** 定义了标准 BLE(Nordic UART)协议,但仅覆盖"审批 + 状态同步",**没有语音通道**。如果 voicestick 想走"官方协议兼容"路线,可以在这个协议基础上扩展语音数据通道,而不必自造一套 BLE GATT(Clawdmeter 的做法)。

## 四、局限性说明

- Clawdmeter/Claudial 依赖的 rate-limit 响应头**未被 Anthropic 公开文档化**,存在被随时变更的风险。
- `mcpd` 项目存在夸大表述(其"MCU 直接符合 MCP 规范、可被任意客户端发现"的说法已被验证推翻,实际有 host 桥接层),`mcpd`/`serial-mcp-server` 均为个位数到十几星标的小众项目,成熟度低。
- 所有信息基于 **2026 年 7 月 24 日前**的仓库快照及 2026 年 4-7 月的媒体报道,这条赛道正在快速演进(官方协议 4 月才发布,`claude-code-stick` 5 月底才创建),建议后续定期复查。
- 未找到"语音交互 + 旋钮控制 + 状态灯"三者统一的开源方案——这是本次调研范围内确认的差异化空白点,而非"不存在"的断言。

## 附:未收录到主表但值得关注的项目

- `Claudeq`(经 WiFi/WebSocket 通信,而非 BLE)
- `DeskPet`(运行在 M5Stack Cardputer 上的桌面宠物)

以上两者在验证阶段作为反证信源出现,尚未做深度信源核实,仅作为后续调研线索记录。
