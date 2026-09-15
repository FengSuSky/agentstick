# AgentStick 接入 WorkBuddy 开放平台

本文说明如何让 M5Stack StickS3（ESP32-S3）上的语音任务通过 AgentStick 桌面端进入 WorkBuddy，并把执行状态回传到设备屏幕。

## 一、结论先行

设备侧几乎不用改。BLE 录音、按键、屏幕状态回写都已经存在，工作量集中在桌面端：把 Agent 后端从本地 CLI（`claude` / `codex`）换成 WorkBuddy Open API。

**路线 B（本地助理）已在桌面端实现完毕**，可直接配置使用。路线 A（云端任务 + ACP）尚未实现。

平台提供两条可用链路，建议分两步走：

| 路线 | 接口 | Scope | 复杂度 | 适用阶段 |
| --- | --- | --- | --- | --- |
| B. 本地助理 | `/localassistant/message` | `user.localassistant.*` | 低，约 200 行 | MVP，先跑通链路 |
| A. 云端任务 + ACP | `/tasks` + ACP 双通道 | `user.task.*` | 中，约 800 行 | 正式硬件接入形态 |

路线 B 驱动的是用户 PC 上已登录的 WorkBuddy 客户端，任务在本机执行，改动最小。路线 A 是白皮书里"双向打通 OpenAPI"的主推形态，任务跑在云端沙箱，支持流式回传和跨端续接，也是审核通过后应该交付的形态。

建议先用 B 验证端到端（1–2 天），再用 A 替换传输层。两条路线的对话文本来源相同，替换时上层不动。

## 一·之二、路线 B 已实现，怎么用

### 1. 开放平台配置（由 AgentStick 开发者完成）

1. 开放平台新建「硬件接入」应用，类型选「开发板/开发套件」或「其他智能硬件」。
2. Scope 只勾 `user.localassistant.invokable` 和 `user.localassistant.readable`。
3. OAuth 回调地址填 `http://localhost:8799/oauth/callback`，与桌面端 `WorkBuddyOAuthCallbackServer.redirectURI` 逐字一致。
4. 审核通过后记录 `client_id` 与 `client_secret`（Secret 只明文展示一次）。

### 2. 桌面端配置

`~/Library/Application Support/AgentStick/config.toml`：

```toml
[agent]
default = "workbuddy"
cwd = "~/work/my-project"
timeout_seconds = 600

[agents.workbuddy]
type = "workbuddy_local"
# client_id 可省略；默认使用内置开发者应用
settle_seconds = 15
```

App 已内置开发者 Client ID 与 Client Secret，普通用户无需填写。选择 WorkBuddy 并保存设置，点击「连接 WorkBuddy」完成个人授权。内置 Secret 直接从 App 读取；自定义 Secret 和个人 OAuth token 保存在 `~/Library/Application Support/AgentStick/workbuddy-auth.json`，权限 0600，按 Client ID 隔离。内置开发者凭据不写入该文件。内置 Secret 可从安装包中提取，不具备服务端保密性；发布和轮换由开发者管理。

### 3. 使用

设备按住录音键说出任务，确认识别文本后，桌面端会：

1. 检查本机 WorkBuddy 是否在线（不在线直接报错提示）。
2. `POST /localassistant/message` 发送任务。
3. 每 2 秒增量轮询回复，直到最后一条消息后静默 `settle_seconds` 秒判定完成。
4. 途中若 WorkBuddy 请求工具授权或提问，设备进入 `needs_attention`，在任务历史窗口应答后自动回发 `permission_response` 继续任务。
5. 复用既有链路：设备播放提示音、屏幕显示 notification、macOS 通知、结果写入 `~/Library/Application Support/AgentStick/Tasks/`。

### 4. 实现文件

| 文件 | 职责 |
| --- | --- |
| `WorkBuddyOAuthCallbackServer.swift` | 127.0.0.1:8799 回环 HTTP 服务，接收授权回调，一次性 `state` 10 分钟有效 |
| `WorkBuddyAuth.swift` | 0600 文件存取、OAuth 授权码换取、token 自动刷新（提前 120 秒 + 轮询中刷新）、同步 HTTP 封装 |
| `WorkBuddyLocalAssistantRunner.swift` | 在线检查、发消息、增量轮询、截获下行 permission 请求、回发 `permission_response`、静默判定完成、结果落盘 |
| `WorkBuddyInteraction.swift` | 下行 permission 请求解析与 `permission_response` 报文组装 |
| `AgentCLIRunner.swift` | `AgentCLIType.workBuddyLocal` 与派发分支，结构同 iMessage 分支 |
| `AppConfig.swift` | 解析 `client_id` / `settle_seconds` |
| `SettingsWindowController.swift` | WorkBuddy 设置区块与「连接 WorkBuddy」按钮 |

### 5. 已知限制

- 判定完成依赖「静默期」启发式，不是协议级完成信号。真正的完成判定需要走路线 A 的 ACP `stopReason`。
- 权限应答已接入 `AgentApprovalCenter`。未应答、回发失败和静默完成之间仍存在状态判断缺陷，不能把当前完成提醒视为协议级保证。
- 开发者 Secret 随 App 分发，可被提取；用户 token 与开发者凭据分开存储。当前采用开发者指定的内置凭据方案。

## 二、平台侧配置

在 https://open.workbuddy.cn 操作：

1. 进入「硬件接入」→ 新建应用。
2. 填写应用基本信息、权限管理、OAuth 回调地址，提交审核。
3. 审核通过后 `client_id` / `client_secret` 生效。**`client_secret` 只在创建成功时明文展示一次**，必须立刻存好。

### 回调地址

桌面端默认值为：

```text
http://localhost:8799/oauth/callback
```

注意 `localhost` 与 `127.0.0.1` 不等价，多一个结尾斜杠也不等价。`/authorize` 与 `/token` 两处传的 `redirect_uri` 必须字节级一致，且必须与平台上登记的值完全一致。

**不匹配时的表现：**未登录的情况下请求 `/authorize` 只会 302 到登录页，看起来一切正常；登录之后才返回 JSON 错误 `{"code":400,"status":"invalid_request","message":"redirect_uri is not registered for this application"}`。所以这是登录后才会暴露的问题。

**桌面端可以改这个值，不必改代码。**在设置页的 WorkBuddy 区块直接改「回调地址」，或写进配置文件：

```toml
[agents.workbuddy]
redirect_uri = "http://localhost:8799/oauth/callback"
```

回调服务默认监听 `127.0.0.1:8799`。如果平台上登记的是另一个回环端口或路径，`WorkBuddyOAuthCallbackServer` 会解析 `redirect_uri` 并改用其中的端口与路径监听；非回环地址会被忽略并退回默认值，本地服务不会去认领自己serve不了的地址。

### https 回调与「粘贴授权码」

桌面端只实现了明文 HTTP 回环监听，**没有内置 TLS 证书**，因此平台若登记 `https://localhost:10009` 这类地址，浏览器跳转会落到一个永远打不开的页面——但这不影响拿到授权码，因为 code 就在地址栏里。

平台侧登记什么，桌面端就照抄什么（字节级一致），然后走手动通道：

1. 设置页填好 Client ID、Client Secret、回调地址，点「连接 WorkBuddy」。
2. `WorkBuddyAuthController.canServeRedirect` 判定该地址无法自动接收，于是只生成授权链接并打开浏览器，不起本地服务。
3. 浏览器中登录并同意后，页面跳到打不开的地址，把地址栏完整链接复制下来。
4. 回到设置页点「粘贴授权码」，粘贴链接即可完成 token 换取。

`WorkBuddyAuthController.completeWithPastedCode` 同时接受完整回调 URL 和裸 code；App 未重启时（内存中仍有 `pendingState`），粘贴带 `state` 的 URL 会恢复 state 校验；仅在 App 重启后或只粘了 code 时跳过 state 校验。

如果希望全自动，只能在平台登记 `http://` 回环地址（OAuth 2.1 / RFC 8252 的 loopback 模式，桌面端默认 `http://localhost:8799/oauth/callback`）。自签证书方案没有采用：浏览器会拦下不受信证书，且需要把证书塞进系统信任链，代价大于收益。

### Scope 选择

按最小权限原则：

- 路线 B：`user.localassistant.invokable user.localassistant.readable`
- 路线 A：`user.task.invokable user.task.readable`

不要申请 `user.profile.readable`、`user.contact.readable`、`user.credit.exchange`，用不到。

### 审核材料

硬件接入的审核判定依据是"这是否是一个实体产品"。有公开案例因为产品名带"测试终端"、产品页写着 macOS 桌面应用、设备状态标注为"模拟"而被驳回。申报时应提供：

- 实体产品名称、品牌、型号（不要出现"测试终端""模拟器""Demo"）
- M5Stack StickS3 实机照片：外观、接口、尺寸
- 设备侧固件说明与 BLE 通信链路说明
- 设备到 WorkBuddy 的完整链路图
- 类型尽量选「开发板/开发套件」或「其他智能硬件」，以平台实际下拉选项为准

### Client Secret 的处理

官方明确要求 `client_secret` 不得暴露在前端或客户端代码中。macOS 桌面端无法成为真正的机密客户端：

- 内部联调：存 0600 文件（`~/Library/Application Support/AgentStick/workbuddy-auth.json`），不写入 `config.toml`，不进 Git。
- 对外分发：需向平台确认是否支持 PKCE 公共客户端模式。截至 2026-09，公开的 `/authorize` 参数列表只有 `response_type`、`client_id`、`redirect_uri`、`scope`、`state`，**没有 `code_challenge`**，即文档层面尚未承诺 PKCE。

## 三、路线 B：本地助理 API

### 接口

Base URL：`https://www.workbuddy.cn/openapi/v2`

```text
GET  /localassistant                 查询 PC 端是否在线      user.localassistant.readable
POST /localassistant/message         发送任务                user.localassistant.invokable
GET  /localassistant/message         增量/分页拉取回复        user.localassistant.readable
```

### 发送

```http
POST /openapi/v2/localassistant/message
Authorization: Bearer {access_token}
Content-Type: application/json

{"content": "帮我看下明天的日程", "msg_type": "text"}
```

返回 `data.message_id`，例如 `msg-001`。

### 轮询回复

```text
GET /openapi/v2/localassistant/message?message_id=msg-001
```

传 `message_id` 时进入增量模式，只返回该消息之后产生的新消息。不传则走分页模式（`limit` / `offset`）。

返回结构中 `messages[].content` **恒为数组**，与发送请求时的字符串格式不同，反序列化要注意。字段：

```json
{
  "message_id": "msg-002",
  "role": "assistant",
  "content": ["..."],
  "msg_type": "text",
  "created_at": "2026-07-30T10:00:00Z",
  "attachments": [],
  "metadata": {}
}
```

### 权限与提问应答

Agent 侧的 AskUserQuestion / 工具审批会下发 permission 请求。应答时 `msg_type` 传 `permission_response`，`content` 是**序列化后的 JSON 字符串**：

```json
{
  "content": "{\"outcome\":\"selected\",\"requestId\":\"...\",\"answers\":{\"q_0\":\"来道单选\"}}",
  "msg_type": "permission_response"
}
```

`requestId` 必须与下行请求一致；单选值为字符串，多选值为字符串数组。

### 已实现：中继到 AgentApprovalCenter

`WorkBuddyLocalAssistantRunner` 在轮询过程中识别下行请求，转交 `VoiceStickCoordinator` 传入的 `approvalHandler` / `inputHandler`——这两个 handler 已经包办了设备提示音、BLE `needs_attention` 状态回写和任务历史窗口的审批 UI，因此 WorkBuddy 无需另写界面。

```text
轮询命中 permission 请求
  → WorkBuddyInteractionParser.parse 提取 requestId / questions / toolName
  → 带 questions  → inputHandler   （任务历史窗口的问卷卡片）
    无 questions  → approvalHandler（允许 / 拒绝）
  → 用户答复
  → POST /localassistant/message  msg_type=permission_response
  → 继续轮询直到静默期结束
```

几个实现约定：

- **去重。** 已处理过的 `requestId` 进 `Set`，轮询重复投递不会二次弹窗。
- **等待不计入超时。** 用户思考的时间里不能消耗任务预算，等待被答复后 `deadline` 按实际等待时长顺延；单个请求最多等 15 分钟。
- **识别失败不卡死。** 解析不到结构化字段时按自由文本提问处理；handler 缺失或超时未答时不回发任何报文，任务收尾时追加「请在 WorkBuddy 窗口中确认」的提示。
- **问题编号。** 题目 id 一律重排为 `q_0`、`q_1`，与平台 `answers` 的 key 约定对齐；单选答案编码为字符串，多选为数组。

## 四、路线 A：云端任务 + ACP

### 4.1 创建任务

```http
POST /openapi/v2/tasks
Authorization: Bearer {access_token}

{"prompt": "帮我整理今天的会议纪要", "name": "会议纪要"}
```

HTTP 201 返回：

| 字段 | 说明 |
| --- | --- |
| `task_id` | 任务 ID，同时是 ACP 的 `sessionId` |
| `status` | `CREATING` / `idle` / `planning` / `working` / `pending` / `completed` / `failed` / `archived` / `deleted` |
| `link` | ACP 连接地址 |
| `token` | ACP 网关鉴权凭据 |
| `expire_at` | token 过期时间，Unix 秒 |
| `sandboxLink` / `sandboxDataLink` | 沙箱控制面与数据面地址 |

创建时若 `link` / `token` 尚未补齐，轮询 `GET /openapi/v2/tasks/{task_id}` 获取。注意**列表接口 `GET /tasks` 不返回 `token` 和 `expire_at`**，必须走单任务查询。

### 4.2 ACP 双通道

接收通道是 SSE，发送通道是 JSON-RPC POST，两条通道用 `Acp-Connection-Id` 关联：

```text
GET {link}
  Authorization: Bearer {token}
  Accept: text/event-stream
  → 响应头返回 Acp-Connection-Id

POST {link}
  Authorization: Bearer {token}
  Acp-Connection-Id: {connectionId}
  Content-Type: application/json
  Body: JSON-RPC 2.0
  → 结果异步通过 SSE 推回
```

按顺序发三个请求：

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{
  "protocolVersion":1,
  "clientCapabilities":{"fs":{"readTextFile":false,"writeTextFile":false}},
  "clientInfo":{"name":"agentstick-macos","version":"0.1.0"}
}}
```

```json
{"jsonrpc":"2.0","id":2,"method":"session/load","params":{
  "sessionId":"{task_id}",
  "cwd":"/workspace",
  "mcpServers":[]
}}
```

```json
{"jsonrpc":"2.0","id":3,"method":"session/prompt","params":{
  "sessionId":"{task_id}",
  "prompt":[{"type":"text","text":"帮我看下明天的天气如何"}]
}}
```

追问复用同一个 `sessionId`，这与现有 `AgentSessionStore` 的续接逻辑天然吻合——把 `task_id` 当作 session ID 记住即可。

### 4.3 下行消息

- `session/update`：notification，流式增量（对话内容、工具调用、规划、状态变化），无需应答。**这是回写设备屏幕的数据源。**
- `session/request_permission`：server-to-client request，必须应答，用于工具授权与提问。
- prompt response：本轮结束标记，含 `stopReason` 和 `usage`。**判断任务完成应看 `stopReason`，不能只看最后一个文本 chunk。**
- `_codebuddy.ai/artifact`：WorkBuddy 私有扩展，下推计划、任务清单、媒体、总结。未识别的 method 应安全忽略。

### 4.4 凭据分层

`access_token`（Open API，约 24 小时，用 `refresh_token` 刷新，refresh 有效期 60 天）与 ACP `token`（短期，通常约 3 天，也可能更短）是两层，不要混用。ACP 遇到 401 应重新 `GET /tasks/{task_id}` 换取新 token 后重建连接。

### 4.5 产物

沙箱地址 = `link` 去掉末尾 `/acp`。产物列表：

```text
GET {sandbox_url}/api/session/artifacts
Authorization: Bearer {task_ticket}
```

`task_ticket` 与 ACP 的 `token` 同源共用。

## 五、代码落地位置

### 新增文件（`desktop/macos/Sources/AgentStickApp/`）

> 本节是设计阶段的落地笔记，文件名与行号以当时设想为准。已落地的路线 B 实现请以「一·之二」和「三、路线 B」为准，两者文件命名略有差异。

| 文件 | 职责 |
| --- | --- |
| `WorkBuddyOAuthStore.swift` | 0600 文件读写 `client_id` / `client_secret` / token（按 Client ID 隔离）；本地 8799 回调 server；一次性 `state`（10 分钟过期，回调即删） |
| `WorkBuddyAPIClient.swift` | `access_token` 自动刷新；`POST /tasks`、`GET /tasks/{id}` 封装 |
| `WorkBuddyACPClient.swift` | SSE 接收 + JSON-RPC 发送双通道；`initialize` / `session/load` / `session/prompt`；`session/update` 解析；ACP token 401 重建 |
| `WorkBuddyAgentRunner.swift` | 实现 Agent 后端：语音文本 → 任务 → 状态回调 → 设备屏幕 |

### 修改文件

**`AgentCLIRunner.swift`**

`AgentCLIType` 增加：

```swift
case workBuddyLocal = "workbuddy_local"
case workBuddyCloud = "workbuddy_cloud"
```

`AgentCLIConfig.default.agents` 增加 `"workbuddy"` 条目。在 `run` 的派发里参照现有 `.iMessage` 分支（第 241–253 行）加分支——iMessage 也是非 CLI 后端，结构可直接照抄：

```swift
if definition.type == .workBuddyLocal {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = WorkBuddyAgentRunner().runLocal(
            task: task, timeoutSeconds: config.timeoutSeconds
        )
        DispatchQueue.main.async { completion(result) }
    }
    return
}
```

**`AppConfig.swift`** — 解析 `[agents.workbuddy]` 段。

**`SettingsWindowController.swift`** — 第 344 行的 agent 类型 switch 加 `workbuddy` 分支；第 504 行附近的 definition 读写加对应字段；增设"连接 WorkBuddy"授权按钮与状态显示。

**`AgentSessionStore.swift`** — 续接索引里记录 `task_id`，实现"继续会话"复用同一个 WorkBuddy 任务。

**`AgentTaskEvent.swift`** — `AgentKind.workBuddy = "work_buddy"` 已存在，直接复用；`AgentTaskEventKind` 的 `waitingForApproval` / `needsInput` 正好对应 ACP 的 `session/request_permission`。

**`StatusController.swift`** — 把 `session/update` 的增量文本压缩后推送到设备屏幕。设备屏幕宽度有限（320×240），建议只推状态与一句话摘要，完整结果留在任务历史窗口。

### 配置示例

```toml
[agent]
default = "workbuddy"

[agents.workbuddy]
type = "workbuddy_cloud"   # 或 "workbuddy_local"
# client_id / client_secret 不写在这里，走本地 0600 文件存储
```

## 六、设备侧

M5Stack StickS3 不需要改固件链路。现有 BLE GATT 协议已支持状态与文本下发，新增的只是 Agent 后端。若要增强体验可考虑：

- 屏幕上区分 WorkBuddy 任务的图标或颜色（区别于 Claude / Codex）
- 长任务时的进度提示，直接消费 `session/update` 的 status 增量

构建命令（不覆盖立创板产物）：

```sh
cd firmware
. /Users/fengsu/esp/esp-idf/export.sh
idf.py -B build-m5stack \
  -D SDKCONFIG=build-m5stack/sdkconfig \
  -D SDKCONFIG_DEFAULTS='sdkconfig.defaults;sdkconfig.defaults.m5stack' \
  build
```

## 七、上线前必须补齐的项

本节针对路线 A（ACP）。路线 B 已落地，不涉及 ACP token、SSE 与 JSON-RPC，因此下表在切换到路线 A 之前无需处理。

按优先级：

| 优先级 | 项 | 原因 |
| --- | --- | --- |
| P0 | ACP 401 后自动重新查询 task token | ACP token 可能很短 |
| P0 | SSE 断线重连 + 指数退避 | 网络中断是常态故障 |
| P0 | 严格识别 `session/request_permission` | 未知 method 默认拒绝，不得自动批准 |
| P0 | 权限应答按 ACP Schema 构造 | 错误的 result 可能造成误授权 |
| P1 | `session/cancel` | 用户需要停止长任务 |
| P1 | 设备事件去重持久化 | 内存去重在重启后失效，会导致重复执行 |
| P1 | 幂等的事件记录 | 同上 |
| P2 | MCP 硬件服务 | 让 WorkBuddy 反向查询设备状态，可先只暴露只读的 `get_device_status` |

## 八、里程碑

1. **PoC**：路线 B 跑通。设备说话 → 桌面 ASR → `/localassistant/message` → 轮询到回复 → 回传设备屏幕。
   **状态：代码完成**，含工具授权与提问的中继。待开放平台硬件接入应用审核通过、`client_id` / `client_secret` 填入后做实机联调。
2. **MVP**：切换到路线 A，ACP 流式回传，任务历史窗口展示，权限请求可应答。
   路线 B 已覆盖"权限请求可应答"；剩余价值是协议级完成判定（`stopReason`）替代静默期启发式。
3. **GA**：断线重连、cancel、产物拉取、设备侧 UI 增强。

## 九、重新构建与安装（本地验证）

代码改动只在源码里，必须重建 App 才会生效。固件不需要重新编译——固件里没有任何 Agent 类型硬编码，Agent 选择完全由桌面端配置决定。

```bash
AGENTSTICK_TARGET_ARCHS=arm64 scripts/build-macos.sh --release
scripts/update-local-macos.sh
```

已知的两个坑（均已修复或需留意）：

- **产物路径变更**：Swift 6.1 起 SwiftPM 把产物从 `.build-<arch>/<arch>-apple-macosx/<config>/` 移到了 `.build-<arch>/out/Products/<Config>/`。旧的打包脚本若仍读旧路径，会静默把上一次的旧二进制打进包里。`scripts/build-macos.sh` 已改为 `resolve_product()` 双路径解析并取较新者。
- **脚本会 `rm -rf` 构建缓存**：`build-macos.sh` 每次都会删 `.build-<arch>` 和 `build/AgentStick-<ver>.app`。设置 `AGENTSTICK_CLEAN_BUILD=0` 可跳过删除、走增量构建。

安装后无需重新授权。凭据存储在 `~/Library/Application Support/AgentStick/workbuddy-auth.json`（0600 权限），不受签名变化影响。

由于是 ad-hoc 签名，替换二进制后 macOS 会重新询问麦克风、蓝牙、辅助功能等权限。

## 参考

- 开放平台：https://open.workbuddy.cn
- 第三方应用（硬件接入流程、Scope）：https://open.workbuddy.cn/docs/third-party-app
- Open API 接口（任务 API、ACP 说明、错误码）：https://open.workbuddy.cn/docs/openapi
- ACP 协议：https://github.com/agentclientprotocol/agent-client-protocol
