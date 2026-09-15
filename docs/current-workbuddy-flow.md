# 当前 WorkBuddy 功能实现逻辑

本文依据当前 macOS 源码整理，不代表开放平台端到端验证结果。

## 1. 用户配置与授权

- AgentStick 内置开发者申请的 Client ID / Client Secret。省略或清空 Client ID 时使用内置值。
- 用户在设置中选择 WorkBuddy 并保存，再点击"连接 WorkBuddy"。普通用户无需申请开放平台应用。
- 自定义 Client ID 可配套填写 Secret；自定义 Secret 和 OAuth token 按 Client ID 隔离存储在 `~/Library/Application Support/AgentStick/workbuddy-auth.json`，权限 0600。内置开发者凭据不写入该文件。
- App 使用浏览器打开 `/openapi/v2/authorize`，申请本地助理读取和调用权限。
- 默认回调为 `http://localhost:8799/oauth/callback`，必须与开发者在平台登记的地址完全一致。代码内置凭据并不能保证平台登记地址正确。
- HTTP localhost 回调由 IPv4/IPv6 本地监听器接收；HTTPS 或其他无法监听的地址走手动粘贴链接。手动粘贴时，若 App 未重启且内存中仍有 `state`，会恢复 state 校验。
- `/token` 用 code 换取个人 access token 和 refresh token，存入上述文件。内置开发者 Secret 不写入文件。
- 发起任务前读取 token，距离过期不足 120 秒时刷新。长任务轮询过程中每次拉取消息前也会检查并刷新 token，避免任务因过期而中断。
- 存储文件读写失败时，Settings 界面会显示"存储异常"红字提示，不再静默丢失错误。

## 2. 语音到任务

1. 设备通过 BLE 上传录音数据，桌面端缓冲并发送 Ogg/Opus 音频给已配置的 ASR。
2. ASR 最终文本按设备输出配置分流：字幕、当前应用输入，或 Agent 任务。
3. Agent 任务先进入文本确认；确认后进入 `AgentCLIRunner`。
4. Runner 根据默认 Agent 选择 Codex、Claude、iMessage、WorkBuddy 或通用命令后端。
5. WorkBuddy 分支在后台线程运行 `WorkBuddyLocalAssistantRunner`，避免网络等待阻塞主界面。

## 3. WorkBuddy 的执行方式

- 先 `GET /localassistant` 检查平台返回的在线状态。代码没有额外校验该助理属于当前这台 Mac。
- 再 `POST /localassistant/message`，请求体只发送任务文本和 `msg_type=text`。
- 每 2 秒以 `message_id` 游标增量拉取消息，保留最新的 assistant 文本。每次拉取前刷新 token，保证长任务不会因过期中断。
- 这条链路经过 WorkBuddy 云端开放平台，再由已登录的本地助理执行；并非直接调用本机 CLI。
- 当前没有发送工程目录、AgentStick 记忆上下文、续接会话 ID。通用 Runner 虽做了记忆观察与会话路由，但这些参数未接入 WorkBuddy 请求。
- 因而工程选择、上下文和会话实际行为依赖 WorkBuddy；不能承诺与 Codex 的续接逻辑一致。"跳过审批"也没有传入 WorkBuddy 分支。

## 4. 授权与提问中继

- 解析下行消息中的工具权限请求或问题，按 request ID 去重。
- 切到主线程：设备显示 `needs_attention`、播放提示音，并向 `AgentApprovalCenter` 提交请求。
- 用户允许、拒绝或回答后，通过 `/localassistant/message` 回发 `permission_response`。
- 单个无选项、允许自由文本且非秘密的问题，在有对应设备时可用语音回答。
- Runner 等待应答；成功回发后，将用户等待时间补回任务超时预算。

## 5. 结果与提醒

- 收到文本后静默 15 秒（可通过 settle_seconds 修改），即视为完成；它不是正式的任务完成事件。
- settle 期间或超时时，若存在未应答请求，结果会标记 `permissionPending`，提示用户在 WorkBuddy 窗口中确认。
- 成功结果写入 Tasks 目录，进入任务历史，并触发 macOS 通知及设备状态、声音更新。
- 未连接目标设备时尝试其他设备；无可用设备时播放 Mac 系统音。
- 当前 BLE 方法在提交写入后立即报告成功，没有等待控制特征写入确认，因此不能保证声音实际送达。

## 6. 已修正的问题

1. ~~钥匙串保存和更新失败未上报~~：改为 0600 文件存储，读写失败会记录并在 Settings 界面显示"存储异常"。
2. ~~Token 没有按 Client ID 隔离~~：token 文件携带 `clientID` 字段，不匹配时视为未授权。
3. ~~本机 ad hoc 签名导致钥匙串 ACL 失效~~：不再使用 Keychain，文件存储不受签名变化影响。
4. ~~手动粘贴授权码跳过 state 校验~~：App 未重启时（内存中仍有 `pendingState`），粘贴带 state 的 URL 会恢复校验。
5. ~~长任务中 token 过期没有刷新~~：轮询循环每次迭代前调用 `validToken()`，自动刷新即将过期的 token。
6. ~~静默完成掩盖待应答请求~~：settle 完成和超时路径都检查 `unansweredRequest`，结果标记 `permissionPending`。
7. ~~回调服务器 finish() 竞争窗口~~：改用 `NSLock` 保护 `finished` 标记和回调投递。

## 7. 剩余已知问题

1. 刷新锁（`refreshLock`）保护单进程内并发刷新，但两个独立 App 实例同时刷新同一 token 仍会冲突——实际场景中仅开发者同时运行调试版和正式版时可能触发。
2. 剩余问题与第 6 节已修正项之外的既有设计限制相同：未发送工程目录和记忆上下文、BLE 写入未确认等。

当前未实现云端任务 `/tasks` + ACP 路线。本文描述的是本地助理消息接口实现。
