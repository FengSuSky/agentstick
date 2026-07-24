# 桌面端显示界面 + 任务历史界面优化设计

- 日期: 2026-07-24
- 范围: `desktop/macos/Sources/AgentStickApp/OverlayController.swift`,
  `desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift`
- 视觉风格基调: 保留 macOS 原生风格(圆角胶囊、彩色主题、SF Symbols),不套用组织级
  报表风格规范(该规范面向文档/报表类产出,不适用于原生桌面 App UI)。

## 背景

当前两处界面功能完整但存在具体问题:

1. **悬浮窗(OverlayController)**: 背景色主题(6 种)、文字颜色、指示器颜色均为固定
   浅色调,不跟随系统深色模式,深色模式下刺眼。
2. **任务历史窗口(AgentTaskHistoryWindowController)**: 侧边列表把「待授权」
   「待回答」「已完成任务」三类记录混在同一个时间序列里,仅用 ASCII 符号
   (●/?/✓/×)区分,扫视效率低;详情面板底部最多同时展示 7 个按钮且没有主次
   区分,容易误点删除/清空历史等破坏性操作。

## 目标(非目标)

目标:
- 悬浮窗在深色模式下颜色自适应,不改变现有胶囊形状、6 种主题选择机制、
  "变高不变矮"的尺寸行为。
- 任务历史列表按「待处理 / 历史记录」分组展示,状态用图标+颜色强化。
- 详情面板按钮按主/次/破坏性操作重新分组布局。

非目标:
- 不引入搜索/过滤功能。
- 不改变悬浮窗的自动隐藏时长、位置堆叠逻辑。
- 不改变任务历史的数据来源(仍读取 `Tasks` 目录 markdown 文件 + `AgentApprovalCenter`)。
- 不改变中英文双语文案的现有实现方式(`currentLanguage` 三元表达式),只新增/调整
  文案内容。

## A. 悬浮窗深色模式适配

**现状**: `OverlayController.backgroundColor(for:)` 返回固定浅色
(如 `.white.withAlphaComponent(0.86)`);`textLabel`/`hintLabel` 用
`NSColor.black.withAlphaComponent(...)`;`RecognitionIndicatorView` 中
跳动条、倒计时环、暂停环、错误叉均用 `NSColor.black.withAlphaComponent(0.34)`。

**方案**:
- 为 6 种 `OverlayThemeColor` 各增加一套深色模式配色(降低背景亮度、保持相近
  透明度,例如深色卡片 + 半透明白色文字),通过 `NSColor` 动态解析
  (根据 `NSApp.effectiveAppearance` 或容器 view 的 `effectiveAppearance`
  判断 light/dark 后选择对应色值)。
- `container` 所在 view 需要在 `viewDidChangeEffectiveAppearance` 或等价的
  外观变化回调中,重新设置 `layer.backgroundColor`、文字颜色、指示器图层颜色,
  因为 `CALayer.backgroundColor` 不会自动跟随 `NSColor` 动态提供者更新。
- `RecognitionIndicatorView` 的 bar/ring/x 图层颜色同样改为跟随外观动态解析,
  而不是硬编码黑色半透明。
- 已在窗口显示时若系统外观发生切换(用户中途切换深浅色模式),下一次
  `show(...)` 调用或外观变化通知触发时刷新颜色。

**不变**: 胶囊圆角(24pt)、6 种主题的选择方式、`largestVisibleHeight` 只增不减
的尺寸行为、自动隐藏延时、屏幕位置堆叠逻辑均保持现状。

## B. 任务历史侧边列表:分组 + 状态图标强化

**现状**: `entries: [HistoryEntry]` 是单一时间倒序数组,`tableView` 是普通
`NSTableView`,每行用 `"\(symbol) ..."` 字符串前缀区分类型和状态。

**方案**:
- 侧边列表改用 `NSOutlineView`,顶层两个分组:
  - 「待处理」(`currentLanguage == .chinese ? "待处理" : "Pending"`):包含
    `state == .pending` 的授权请求和输入请求,按创建时间倒序。
  - 「历史记录」(`"历史记录" / "History"`):包含已完成任务 + 已处理
    (非 pending)的授权/输入请求,按时间倒序,与现状排序一致。
  - 两个分组均可折叠,默认展开;若「待处理」为空则该分组连同标题一起隐藏
    (不展示空分组标题行)。
- 行内符号替换为 SF Symbols + 语义化颜色圆点:
  - 待处理/等待中: 橙色 `circle.fill` 或 `questionmark.circle.fill`
  - 成功/已允许/已完成/已回答: 绿色 `checkmark.circle.fill`
  - 失败/已拒绝: 红色 `xmark.circle.fill`
  - 已取消: 灰色 `minus.circle.fill`
  - "继续执行中"(`.continuing`): 蓝色 `arrow.triangle.2.circlepath.circle.fill`
- 详情面板顶部 `metadataLabel` 所在位置,同步加一个与列表同色的小圆点 + 状态
  文字,替代目前纯文字状态描述,视觉上与列表呼应。
- 数据结构调整: `HistoryEntry` 增加一个计算属性(如 `isPending: Bool`)用于
  分组;`reloadEntries` 中先按 `isPending` 分桶,组内再按现有时间排序规则排列。
- 选中行定位逻辑(`selecting resultURL/approvalID/inputID`)需要适配
  outline view 的分组结构(先定位所在分组再展开选中该行)。

## C. 任务历史详情面板:按钮主次分组

**现状**: `footer` 是一个水平 `NSStackView`,最多同时塞入 7 个按钮
(刷新、清空历史、删除、拒绝、允许、取消请求、回答、打开原始文件、
在 Finder 中显示),无视觉主次之分。

**方案**: 重新组织 `footer` 为左右两组:
- **左侧(次要 / 破坏性操作)**: 「刷新」「打开原始文件」「在 Finder 中显示」
  收纳为无边框/纯文字样式按钮；「删除记录」「清空历史」保持独立、使用不显眼
  的样式(如 `bezelStyle = .inline` 或纯文字 + 警示色文字),仍需保留现有的
  二次确认 `NSAlert`。
- **右侧(主操作,始终最醒目)**: 当前适用的主操作(允许/拒绝、回答/取消请求)
  保持 `bezelStyle = .rounded`,允许/回答按钮使用强调色高亮
  (`keyEquivalent = "\r"` 保留回车默认确认)。
- 「打开原始文件」「在 Finder 中显示」两个只对已完成任务生效的操作,合并为
  一个次要下拉菜单按钮(`NSPopUpButton` 纯文字样式或 `NSMenu` 弹出),减少
  常驻按钮数量。
- 按钮的显示/隐藏规则(`display(_:)` 系列方法中根据 entry 类型切换
  `isHidden`/`isEnabled`)保持现有条件判断,只调整视觉样式和排列位置,不改变
  何时显示哪个按钮的逻辑。

## 兼容性与风险

- outline view 分组是本次改动中结构变化最大的部分,需要保留现有的"选中定位"
  「新请求到来时自动弹出并选中」等交互(`onChange`/`onInputChange` 回调触发
  `show(selectingApproval:)`/`show(selectingInput:)`)。
- 深色模式切换的实时刷新依赖 view 的外观变化回调,如果系统 API 行为与预期不符
  (低概率),需要退化为"下次显示时刷新"作为兜底,不阻塞主流程。
- 双语文案(中/英)需要为新增的分组标题、状态描述补充对应翻译,遵循现有
  `currentLanguage == .chinese ? "..." : "..."` 模式,不引入新的本地化机制。

## 测试计划

- 手动验证(该改动为原生 macOS UI,无自动化 UI 测试基础设施):
  1. 系统切换浅色/深色模式,悬浮窗在录音中的听写/倒计时/暂停/错误四种状态下
     颜色均清晰可读,6 种主题色在深色模式下都不刺眼。
  2. 任务历史窗口中,人为触发一个待授权请求和一个待回答请求,确认它们出现在
     「待处理」分组顶部,处理后自动移动到「历史记录」分组。
  3. 分别选中任务、待处理授权、待回答请求三种条目,确认详情面板按钮的
     显示/隐藏、主次样式符合预期,「删除」「清空历史」二次确认弹窗仍正常。
  4. 编译 `desktop/macos` target 确认无警告/报错。
