# 调研简报：AgentStick × 腾讯 WorkBuddy 联动方案

日期：2026-08-15

## WorkBuddy 是什么

WorkBuddy 是腾讯 CodeBuddy 团队推出的桌面 AI Agent 工作台（仍在快速迭代中），定位"全场景职场 AI 智能体桌面工作台"：

- 一句话描述需求，自动拆解多步骤任务、调用本地文件、交付多模态结果。
- 支持多 Agent 并行工作，有技能市场（兼容 OpenClaw 技能生态）。
- 有"连接器"体系对接外部服务：预置 QQ 邮箱、腾讯文档、腾讯会议、TAPD、腾讯乐享、腾讯网盘等，支持自定义连接器。
- 有"助理（远程任务）"功能：通过微信 / 企业微信 / QQ / 元宝 / 钉钉 / 飞书 IM 远程给电脑上的 WorkBuddy 下发任务并接收结果。

关键事实：**WorkBuddy 桌面版本身没有公开的本地 API、URL scheme 或 webhook**，外部触发目前只有 IM 助理渠道。但它的连接器体系基于 **MCP（stdio/SSE/HTTP 均支持）**，且同家族的 **CodeBuddy CLI 提供了完整的 headless 模式和 HTTP API**——这两条才是可编程联动的落点。

## 联动方向与可行性

按实现成本从低到高、与 AgentStick 现有架构的契合度排序：

### 方案 A：把 CodeBuddy CLI 接入为 Agent 后端（推荐首选）

CodeBuddy CLI（命令 `codebuddy` / `cbc`）的 headless 模式与 `claude -p` 高度同构，AgentStick 已有的 `claude_print` / `codex_exec` 接入模式可以直接复用：

- 非交互执行：`codebuddy -p "任务"`，支持 stdin 传入。
- 输出：`--output-format text/json/stream-json`；JSON 含 `session_id`、`result`、成本统计；`--json-schema` 可约束结构化输出。
- 会话续接：`--continue` / `--resume <session_id>`，与 AgentStick 现有的会话续接索引（新会话/继续会话）一一对应。
- 后台任务事件：stream-json 中有 `task_started` / `task_progress` / `task_updated` / `task_notification`，天然映射到设备屏幕状态回写（运行中/完成/失败）。
- MCP：`~/.codebuddy/.mcp.json`，stdio/SSE/HTTP 三种传输。

落地方式：在 `AgentCLIRunner` 新增 `codebuddy_print` 类型（或直接用现有 `generic` 类型 + `[agents.codebuddy]` 配置先行验证），并在 CLI 自动发现逻辑中加入 CodeBuddy CLI 的常见安装路径。

注意事项：

- 需要授权的操作必须加 `-y / --dangerously-skip-permissions` 或用 `--allowedTools` 白名单；`--permission-prompt-tool` 不支持，所以 Claude Code 那种逐项审批回调拿不到，短期只能走"白名单 + 高风险绕过"两档，任务中心审批界面在 CodeBuddy 后端下暂时无效。
- CodeBuddy CLI 支持定时任务工具（CronCreate 等）和后台任务，长任务建议用 stream-json 而不是 json 一次性输出。

### 方案 B：AgentStick 桌面端对外提供 MCP Server（差异化最大）

方向反过来：不是 AgentStick 调 WorkBuddy，而是让 WorkBuddy（以及 Claude Code、Codex 等任何 MCP 客户端）把 AgentStick 当作一个连接器。WorkBuddy 自定义连接器的配置方式与 CodeBuddy MCP 一致，本地 stdio 或 HTTP 均可接。

AgentStick 桌面 App 内嵌一个 MCP server，暴露的工具例如：

- `notify_device`：把 Agent 任务完成/失败状态推到 ESP32 屏幕和声音提醒。
- `ask_user_by_voice`：Agent 遇到 needs input 时，通过设备语音向用户提问并回收 ASR 结果——这是 IM 助理渠道做不到的"离开键盘即时应答"。
- `get_task_history`：读取本地任务历史供 Agent 汇报。

这一步让 AgentStick 从"语音入口"升级为"任何桌面 Agent 的硬件外设"，且同时服务 Claude Code / Codex / WorkBuddy 三家，不绑定腾讯生态。

### 方案 C：发布 WorkBuddy Skill（Skill + CLI 形态）

WorkBuddy 连接器的第二种形态是 Skill + CLI，技能市场兼容 OpenClaw 生态。可以打包一个 AgentStick Skill，内含薄 CLI 封装（如 `agentstick notify` / `agentstick ask`），教 WorkBuddy 在什么时机调用设备提醒/语音问询。Skill 与 MCP 方案 B 互补：MCP 提供工具，Skill 提供使用时机和话术。Skill 格式细节文档公开程度有限，落地前需按当期官方文档确认。

### 方案 D：IM 助理渠道（不建议，仅关注）

WorkBuddy 官方远程方案是微信等 IM 渠道，不开放 API，且有固定工作目录、单会话等限制。AgentStick 作为本地硬件语音入口可以视为同一场景的替代品（"本地助理渠道"），但没有可编程接口，无法直接桥接。除非后续腾讯开放助理 API，否则不投入。

### 方案 E：自动化模块监听触发（待验证）

WorkBuddy 自动化模块支持"定时/监听"触发条件。如果"监听"支持文件夹或邮件，可以用"投递任务文件/邮件"的方式廉价触发 WorkBuddy 任务，作为方案 A 的补充。公开文档未写明监听对象，需实测确认。

## 建议路线

1. **短期（成本最低）**：用现有 `generic` agent 类型接 `codebuddy -p` 跑通语音下发任务 → 结果回写设备；验证后再做一等公民的 `codebuddy_print` 类型和会话续接。
2. **中期（差异化）**：在桌面 App 内实现 MCP server（stdio 起步），先把 Claude Code / Codex 接上，再写一份"WorkBuddy 自定义连接器接入 AgentStick"的配置指南；条件成熟时发布配套 Skill。
3. **持续关注**：CodeBuddy CLI 的 HTTP API（Beta）和 SDK（Python/TypeScript）走向服务化后，可替换 CLI 进程模型；WorkBuddy 助理若开放 API 再评估 IM 桥接。

## 专项评估：MCP Server / Skill 能否打通"语音下发 → WorkBuddy 执行 → 设备提醒"

目标链路拆成两段：①语音任务从 AgentStick 下发进 WorkBuddy 并开始执行；②WorkBuddy 完成后经 AgentStick 给 ESP32 设备发提醒。

先说已确认的硬约束：WorkBuddy 桌面版**没有** URL scheme、CLI、webhook 或任何外部任务注入接口；自动化模块**只支持定时触发**（无事件/文件夹/邮件监听）；唯一的远程入口是 IM 助理（微信等，不开放 API）。

**方案 2（AgentStick 启动时开本地 MCP 服务，WorkBuddy 装自定义连接器）：能稳定做到 ②，做不到 ①。**

- 可行性高。AgentStick App 监听 `127.0.0.1` 端口提供 MCP over HTTP；WorkBuddy 自定义连接器的配置方式与 CodeBuddy MCP 一致，支持 http 传输，填 `http://127.0.0.1:<port>/mcp` 即可接入。
- 暴露 `notify_device` / `ask_user_by_voice` / `get_task_history` 等工具后，WorkBuddy 的 agent 在任务完成或需要输入时即可调用，AgentStick 再经 BLE 回写设备屏幕和声音提醒。
- 但 MCP 的方向是"WorkBuddy 调 AgentStick"，它无法把外部任务推进 WorkBuddy。

**方案 1（自定义 Skill）：单独看同样做不到 ①，它的真正价值是服务 ②。**

- Skill 是 WorkBuddy agent 运行时才使用的能力包，没有外部触发入口，AgentStick 无法通过 skill"下发命令"。
- Skill 的正确用法是配合 MCP：MCP 提供工具，Skill 教 WorkBuddy 在"任务完成 / 需要确认"时默认调用 AgentStick 的工具。两个方案是配套关系，不是二选一。

**①（语音任务注入 WorkBuddy）目前只能走非官方通道，按务实程度排序：**

1. **UI 自动化粘贴（今天就能做）**：AgentStick 继承了 VoiceStick 的"聚焦应用 + 粘贴文本"能力，可以切到 WorkBuddy 窗口、粘贴任务文本、回车发送。缺点：抢占前台焦点、WorkBuddy 输入框结构升级会失效、执行中新任务注入困难。
2. **定时自动化轮询（纯官方机制）**：在 WorkBuddy 建一个每 N 分钟的自动化任务，提示词为"调用 agentstick MCP 的 fetch_pending_tasks 工具，若有新语音任务则执行，完成后调用 notify_device"。延迟等于轮询间隔；无人值守自动执行有权限风险，官方文档也提示涉及文件写入/资金操作的 prompt 需谨慎。
3. IM 助理渠道不可编程，排除。

**推荐组合**：以方案 2 的 MCP server 为主体，配一个薄 Skill 约定行为；任务下发先用 UI 粘贴自动化打通体验（相当于 Agent Run 增加一个 `workbuddy_ui` 输出目标），同时小成本验证定时轮询方案，等腾讯开放正式 API 再迁移。WorkBuddy 仍处内测快速迭代期，自定义连接器配置格式可能变化，接入层要做成可配置。

## 专项调研：Vibe Island 的实现机制，及其对"WorkBuddy → 设备提醒"的意义

对本机安装的 Vibe Island（`app.vibeisland.macos`）做了解剖，它的架构完全是 **Claude Code hooks + 本地 Unix socket 桥**：

1. **零配置注入 hooks**：安装后把一个 hook 命令写入各家 Agent 的配置文件，包括 `~/.claude/settings.json`、`~/.codex/config.toml`、`~/.gemini/settings.json`、`~/.cursor/hooks.json`、`~/.copilot/config.json`、`~/.codebuddy/settings.json`，以及——**`~/.workbuddy/settings.json`**。
2. **hook 命令**：`~/.vibe-island/bin/vibe-island-bridge --source <agent名>`，实际是一个 zsh 启动器，定位并 exec App 内的 Helpers 二进制；App 被删除时有 5 分钟宽限期的自清理逻辑（从所有配置文件里摘除自己的 hooks）。
3. **事件回传**：bridge 从 stdin 读取 hook JSON payload，通过 Unix domain socket（`/tmp/vibe-island.sock`）推给主 App，主 App 再渲染灵动岛状态、发系统通知（含音效），并用 AppleEvents 跳回对应终端窗口。
4. **覆盖的事件**：UserPromptSubmit / PreToolUse / PostToolUse / Notification / Stop / SubagentStop / SessionStart / SessionEnd / PreCompact——即 Claude Code hook 协议全集。

**关键事实（已在本机验证）**：`~/.workbuddy/settings.json` 存在且结构就是 Claude Code 的 hooks schema（`hooks.<Event>[].hooks[].command` + matcher），Vibe Island 已在其中注册了全部九个事件、`--source workbuddy`。这意味着 **WorkBuddy 原生支持 Claude Code 风格的 hooks**，"任务完成 / 需要确认 / 会话结束"等事件都会以 JSON 形式喂给外部命令——这正是"WorkBuddy 完成任务后主动提醒设备"缺失的那块拼图，不需要 MCP、不需要 Skill、也不需要腾讯开放 API。

**对 AgentStick 的落地路径**（复用现有 `AgentStickHooks` + `AgentEventBridge`，仓库里已有同构实现）：

> **已实现（2026-08-15）**：App 启动时自动检测各 Agent CLI 的 hook 配置，幂等注入事件 hooks（修改前自动备份）。支持 Claude Code（`~/.claude/settings.json`）、Codex（`~/.codex/hooks.json`）、WorkBuddy、CodeBuddy、Gemini、Qwen、Qoder、Factory（各 `settings.json`，均为 Claude 嵌套 schema）以及 Cursor（`~/.cursor/hooks.json`，扁平 schema + `beforeSubmitPrompt`/`stop` 事件）。hook 命令指向 `~/.agentstick/bin/agentstick-bridge` 启动器（带 App 路径缓存、多路径查找、App 被删后 5 分钟宽限自清理，自清理覆盖全部配置文件）；`AgentHookPayloadMapper` 按上表 source 映射，设备端显示各 Agent 名称。Kimi / DeepSeek / CodeWhale（TOML 配置）、OpenCode / Mimocode / Antigravity（JS 插件机制）暂未支持，为后续项。实现见 `AgentStickCore/AgentHookRegistration.swift`、`AgentStickApp/AgentHookInstaller.swift`。

1. 把 `AgentStickHooks` 二进制（或安装到 `~/.agentstick/bin/` 的启动器脚本，参考 vibe-island 的多路径查找 + 自清理写法）注册进 `~/.workbuddy/settings.json`，事件至少订阅 `Stop`（任务完成）、`Notification`（需要用户注意/审批）、`SessionEnd`，命令带 `--source workbuddy`。
2. 现有 `AgentHookEnvelope` / `AgentEventBridgeClient`（stdin JSON → Unix socket → 主 App）原样复用；只需在事件解析层适配 WorkBuddy payload 的字段差异（待实测对比）。
3. 主 App 按 source=workbuddy 走既有的设备状态回写（运行中/完成/失败/等待确认）+ 声音提醒链路。
4. 与 Vibe Island 共存无冲突：hook 数组允许多条命令，vibe-island 的清理逻辑只摘除包含 `vibe-island` 字样的命令，不会动 AgentStick 的条目；反之 AgentStick 的注入/卸载也应按"精确匹配自己的命令"来写。
5. 飞书等连接器场景：WorkBuddy 通过连接器推送飞书消息时，`PostToolUse` / `Notification` hook 同样会触发，可在 payload 的工具名里识别（如 feishu / tencent-docs 相关工具），据此定制设备提醒文案。

风险与注意：WorkBuddy hooks 属于未公开文档的能力（从 Vibe Island 逆向证实），字段格式可能随版本变化，解析层要宽容失败（现有 AgentStickHooks 已是 fail-open 设计，保持即可）；注入前备份 `settings.json`，并提供一键卸载。

## 局限性说明

- WorkBuddy 处于快速迭代期，连接器/助理细节以官方文档当期版本为准。
- Skill 格式、自动化"监听"触发的能力边界未能从公开文档完全确认，标注为待验证。
- CodeBuddy CLI 与 WorkBuddy 桌面版是两个产品线：CLI 接通不等于 WorkBuddy 桌面版接通，方案 A 的用户体验是"多一个 Agent 后端"，方案 B/C 才是真正与 WorkBuddy 工作台联动。

## 参考来源

- WorkBuddy 官网：<https://www.codebuddy.cn/work/>
- WorkBuddy 连接器文档：<https://www.workbuddy.cn/docs/workbuddy/From-Beginner-to-Expert-Guide/Function-Description/Connector>
- 助理（远程任务）企业文档：<https://cloud.tencent.com/document/product/1831/134392>
- CodeBuddy CLI MCP 文档：<https://www.codebuddy.cn/docs/cli/mcp>
- CodeBuddy CLI 无头模式文档：<https://www.codebuddy.cn/docs/cli/headless>
- WorkBuddy 产品技术概览与多平台集成指南：<https://cloud.tencent.com/developer/article/2680488>
