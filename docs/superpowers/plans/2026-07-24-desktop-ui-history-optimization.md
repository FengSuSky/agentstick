# 桌面端悬浮窗 + 任务历史界面优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让悬浮窗(OverlayController)在深色模式下颜色自适应,让任务历史窗口
(AgentTaskHistoryWindowController)的侧边列表按"待处理/历史记录"分组并用图标+颜色
强化状态,详情面板底部按钮按主/次/破坏性重新分组,同时保留 macOS 原生视觉语言。

**Architecture:** 把可以脱离 AppKit 单独验证的纯逻辑(主题配色映射、状态→图标/颜色
映射、按待处理/历史分组排序)下沉到 `AgentStickCore` 模块,用现有的
`Tests/AgentStickAppTests/main.swift` + `expect()` 断言方式覆盖;AppKit 相关的
视觉接线(NSColor 构造、NSOutlineView、按钮样式)留在 `AgentStickApp` 里,通过手动
编译 + 人工走查验证(该代码库对 AppKit UI 类没有自动化测试基础设施,这是延续现有
约定,而不是新引入的空白)。

**Tech Stack:** Swift 5.9 / AppKit / Swift Package Manager (`desktop/macos/Package.swift`)。

**参考设计文档:** [docs/superpowers/specs/2026-07-24-desktop-ui-history-optimization-design.md](../specs/2026-07-24-desktop-ui-history-optimization-design.md)

**约定:**
- 所有 Swift 命令均在 `desktop/macos` 目录下执行。
- 每个 Task 完成后运行 `swift build --product AgentStickApp 2>&1 | tail -20` 确认无编译错误,再提交。
- 中英文文案沿用现有 `currentLanguage == .chinese ? "中文" : "English"` 写法,不引入新的本地化机制。

---

### Task 1: OverlayColorScheme 纯逻辑(悬浮窗深浅色配色表)

**Files:**
- Create: `desktop/macos/Sources/AgentStickCore/OverlayColorScheme.swift`
- Modify (test): `desktop/macos/Tests/AgentStickAppTests/main.swift`

- [ ] **Step 1: 在测试文件末尾追加失败用例**

在 `desktop/macos/Tests/AgentStickAppTests/main.swift` 文件末尾(`print("AgentStickCoreTests passed")` 之前)追加:

```swift
expect(
    OverlayColorScheme.backgroundComponents(for: .white, appearance: .light)
        == OverlayColorComponents(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.86),
    "White theme light background should match the legacy overlay color"
)
expect(
    OverlayColorScheme.backgroundComponents(for: .white, appearance: .dark)
        != OverlayColorScheme.backgroundComponents(for: .white, appearance: .light),
    "Dark appearance should use a different background than light appearance"
)
expect(
    OverlayColorScheme.isLightText(for: .dark),
    "Dark appearance should use light (white-based) text for contrast"
)
expect(
    !OverlayColorScheme.isLightText(for: .light),
    "Light appearance should keep dark (black-based) text"
)
expect(
    OverlayColorScheme.textAlpha(for: .dark) > OverlayColorScheme.textAlpha(for: .light),
    "Dark mode text should be more opaque so it reads clearly on a dark card"
)
for theme in OverlayThemeName.allCases {
    let light = OverlayColorScheme.backgroundComponents(for: theme, appearance: .light)
    let dark = OverlayColorScheme.backgroundComponents(for: theme, appearance: .dark)
    expect(light.alpha > 0 && dark.alpha > 0, "\(theme) should define a background for both appearances")
}
```

- [ ] **Step 2: 运行测试,确认因类型不存在而编译失败**

Run: `cd desktop/macos && swift run AgentStickCoreTests 2>&1 | tail -20`
Expected: 编译错误,提示 `OverlayColorScheme`/`OverlayColorComponents`/`OverlayThemeName` 等类型找不到。

- [ ] **Step 3: 创建 OverlayColorScheme.swift**

```swift
import Foundation

public enum OverlayAppearance {
    case light
    case dark
}

public enum OverlayThemeName: String, CaseIterable {
    case white
    case pink
    case green
    case yellow
    case blue
    case purple
}

public struct OverlayColorComponents: Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public enum OverlayColorScheme {
    public static func backgroundComponents(
        for theme: OverlayThemeName,
        appearance: OverlayAppearance
    ) -> OverlayColorComponents {
        switch (theme, appearance) {
        case (.white, .light): return OverlayColorComponents(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.86)
        case (.white, .dark): return OverlayColorComponents(red: 0.16, green: 0.16, blue: 0.17, alpha: 0.88)
        case (.pink, .light): return OverlayColorComponents(red: 1.0, green: 0.84, blue: 0.9, alpha: 0.86)
        case (.pink, .dark): return OverlayColorComponents(red: 0.32, green: 0.18, blue: 0.24, alpha: 0.88)
        case (.green, .light): return OverlayColorComponents(red: 0.84, green: 0.95, blue: 0.84, alpha: 0.86)
        case (.green, .dark): return OverlayColorComponents(red: 0.16, green: 0.26, blue: 0.18, alpha: 0.88)
        case (.yellow, .light): return OverlayColorComponents(red: 1.0, green: 0.94, blue: 0.72, alpha: 0.86)
        case (.yellow, .dark): return OverlayColorComponents(red: 0.3, green: 0.26, blue: 0.12, alpha: 0.88)
        case (.blue, .light): return OverlayColorComponents(red: 0.82, green: 0.91, blue: 1.0, alpha: 0.86)
        case (.blue, .dark): return OverlayColorComponents(red: 0.14, green: 0.2, blue: 0.3, alpha: 0.88)
        case (.purple, .light): return OverlayColorComponents(red: 0.9, green: 0.84, blue: 1.0, alpha: 0.86)
        case (.purple, .dark): return OverlayColorComponents(red: 0.24, green: 0.18, blue: 0.32, alpha: 0.88)
        }
    }

    public static func textAlpha(for appearance: OverlayAppearance) -> Double {
        appearance == .light ? 0.68 : 0.92
    }

    public static func hintAlpha(for appearance: OverlayAppearance) -> Double {
        appearance == .light ? 0.42 : 0.6
    }

    public static func indicatorAlpha(for appearance: OverlayAppearance) -> Double {
        appearance == .light ? 0.34 : 0.7
    }

    public static func isLightText(for appearance: OverlayAppearance) -> Bool {
        appearance == .dark
    }
}
```

- [ ] **Step 4: 重新运行测试确认通过**

Run: `cd desktop/macos && swift run AgentStickCoreTests 2>&1 | tail -5`
Expected: `AgentStickCoreTests passed`

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Sources/AgentStickCore/OverlayColorScheme.swift desktop/macos/Tests/AgentStickAppTests/main.swift
git commit -m "feat: add OverlayColorScheme for light/dark overlay theming

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: HistoryStatus 纯逻辑(状态 → SF Symbol + 语义颜色)

**Files:**
- Create: `desktop/macos/Sources/AgentStickCore/HistoryStatus.swift`
- Modify (test): `desktop/macos/Tests/AgentStickAppTests/main.swift`

- [ ] **Step 1: 追加失败用例**

在 `main.swift` 末尾追加:

```swift
expect(
    HistoryStatus.taskSucceeded.presentation == HistoryStatusPresentation(symbolName: "checkmark.circle.fill", color: .success),
    "Succeeded tasks should present as a filled checkmark in the success color"
)
expect(
    HistoryStatus.taskFailed.presentation.color == .failure,
    "Failed tasks should present in the failure color"
)
expect(
    HistoryStatus.approvalPending.presentation.color == .pending,
    "Pending approvals should present in the pending color"
)
expect(
    HistoryStatus.approvalContinuing.presentation.color == .inProgress,
    "Continuing approvals should present in the in-progress color"
)
expect(
    HistoryStatus.inputCancelled.presentation.color == .cancelled,
    "Cancelled input requests should present in the cancelled color"
)
expect(
    HistoryStatus.inputPending.presentation.symbolName == "questionmark.circle.fill",
    "Pending input requests should use a question-mark glyph"
)
```

- [ ] **Step 2: 运行测试,确认因类型不存在而编译失败**

Run: `cd desktop/macos && swift run AgentStickCoreTests 2>&1 | tail -20`
Expected: 编译错误,提示 `HistoryStatus` 等类型找不到。

- [ ] **Step 3: 创建 HistoryStatus.swift**

```swift
import Foundation

public enum HistoryStatusColor: Equatable {
    case pending
    case success
    case failure
    case cancelled
    case inProgress
}

public struct HistoryStatusPresentation: Equatable {
    public let symbolName: String
    public let color: HistoryStatusColor

    public init(symbolName: String, color: HistoryStatusColor) {
        self.symbolName = symbolName
        self.color = color
    }
}

public enum HistoryStatus {
    case taskSucceeded
    case taskFailed
    case approvalPending
    case approvalContinuing
    case approvalAllowed
    case approvalDenied
    case inputPending
    case inputSubmitted
    case inputCancelled

    public var presentation: HistoryStatusPresentation {
        switch self {
        case .taskSucceeded:
            return HistoryStatusPresentation(symbolName: "checkmark.circle.fill", color: .success)
        case .taskFailed:
            return HistoryStatusPresentation(symbolName: "xmark.circle.fill", color: .failure)
        case .approvalPending:
            return HistoryStatusPresentation(symbolName: "circle.fill", color: .pending)
        case .approvalContinuing:
            return HistoryStatusPresentation(symbolName: "arrow.triangle.2.circlepath", color: .inProgress)
        case .approvalAllowed:
            return HistoryStatusPresentation(symbolName: "checkmark.circle.fill", color: .success)
        case .approvalDenied:
            return HistoryStatusPresentation(symbolName: "xmark.circle.fill", color: .failure)
        case .inputPending:
            return HistoryStatusPresentation(symbolName: "questionmark.circle.fill", color: .pending)
        case .inputSubmitted:
            return HistoryStatusPresentation(symbolName: "checkmark.circle.fill", color: .success)
        case .inputCancelled:
            return HistoryStatusPresentation(symbolName: "minus.circle.fill", color: .cancelled)
        }
    }
}
```

- [ ] **Step 4: 重新运行测试确认通过**

Run: `cd desktop/macos && swift run AgentStickCoreTests 2>&1 | tail -5`
Expected: `AgentStickCoreTests passed`

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Sources/AgentStickCore/HistoryStatus.swift desktop/macos/Tests/AgentStickAppTests/main.swift
git commit -m "feat: add HistoryStatus symbol/color mapping for task history

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: HistoryEntryGrouping 纯逻辑(待处理/历史记录分组排序)

**Files:**
- Create: `desktop/macos/Sources/AgentStickCore/HistoryEntryGrouping.swift`
- Modify (test): `desktop/macos/Tests/AgentStickAppTests/main.swift`

- [ ] **Step 1: 追加失败用例**

在 `main.swift` 末尾追加:

```swift
let groupingNow = Date(timeIntervalSince1970: 1_000_000)
let groupingOlderHistory = HistoryGroupingItem(id: "history-older", isPending: false, date: groupingNow.addingTimeInterval(-100))
let groupingNewerHistory = HistoryGroupingItem(id: "history-newer", isPending: false, date: groupingNow)
let groupingPendingOld = HistoryGroupingItem(id: "pending-old", isPending: true, date: groupingNow.addingTimeInterval(-500))
let groupingPendingNew = HistoryGroupingItem(id: "pending-new", isPending: true, date: groupingNow.addingTimeInterval(-10))
let groupingResult = HistoryEntryGrouping.group([
    groupingOlderHistory, groupingPendingOld, groupingNewerHistory, groupingPendingNew
])
expect(
    groupingResult.pending.map(\.id) == ["pending-new", "pending-old"],
    "Pending items should be grouped together and sorted newest first"
)
expect(
    groupingResult.history.map(\.id) == ["history-newer", "history-older"],
    "Non-pending items should be grouped together and sorted newest first"
)
expect(
    HistoryEntryGrouping.group([]).pending.isEmpty && HistoryEntryGrouping.group([]).history.isEmpty,
    "Grouping an empty list should yield two empty groups"
)
```

- [ ] **Step 2: 运行测试,确认因类型不存在而编译失败**

Run: `cd desktop/macos && swift run AgentStickCoreTests 2>&1 | tail -20`
Expected: 编译错误,提示 `HistoryGroupingItem`/`HistoryEntryGrouping` 找不到。

- [ ] **Step 3: 创建 HistoryEntryGrouping.swift**

```swift
import Foundation

public struct HistoryGroupingItem: Equatable {
    public let id: String
    public let isPending: Bool
    public let date: Date

    public init(id: String, isPending: Bool, date: Date) {
        self.id = id
        self.isPending = isPending
        self.date = date
    }
}

public struct HistoryGroupedResult: Equatable {
    public let pending: [HistoryGroupingItem]
    public let history: [HistoryGroupingItem]

    public init(pending: [HistoryGroupingItem], history: [HistoryGroupingItem]) {
        self.pending = pending
        self.history = history
    }
}

public enum HistoryEntryGrouping {
    public static func group(_ items: [HistoryGroupingItem]) -> HistoryGroupedResult {
        let pending = items.filter(\.isPending).sorted { $0.date > $1.date }
        let history = items.filter { !$0.isPending }.sorted { $0.date > $1.date }
        return HistoryGroupedResult(pending: pending, history: history)
    }
}
```

- [ ] **Step 4: 重新运行测试确认通过**

Run: `cd desktop/macos && swift run AgentStickCoreTests 2>&1 | tail -5`
Expected: `AgentStickCoreTests passed`

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Sources/AgentStickCore/HistoryEntryGrouping.swift desktop/macos/Tests/AgentStickAppTests/main.swift
git commit -m "feat: add HistoryEntryGrouping for pending/history sectioning

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: 在 AppConfig.swift 中桥接 OverlayThemeColor → OverlayThemeName

**Files:**
- Modify: `desktop/macos/Sources/AgentStickApp/AppConfig.swift:1-57`

- [ ] **Step 1: 添加 AgentStickCore 导入**

在 `desktop/macos/Sources/AgentStickApp/AppConfig.swift` 顶部(第 1-3 行)把:

```swift
import AppKit
import Foundation
import TOMLKit
```

改为:

```swift
import AgentStickCore
import AppKit
import Foundation
import TOMLKit
```

- [ ] **Step 2: 添加桥接扩展**

在 `enum OverlayThemeColor { ... }` 定义结束的 `}`(原第 57 行)之后插入:

```swift

extension OverlayThemeColor {
    var colorSchemeTheme: OverlayThemeName {
        OverlayThemeName(rawValue: rawValue) ?? .white
    }
}
```

- [ ] **Step 3: 编译确认无误**

Run: `cd desktop/macos && swift build --product AgentStickApp 2>&1 | tail -20`
Expected: `Build of product 'AgentStickApp' complete!`,无警告/报错。

- [ ] **Step 4: Commit**

```bash
git add desktop/macos/Sources/AgentStickApp/AppConfig.swift
git commit -m "feat: bridge OverlayThemeColor to AgentStickCore.OverlayThemeName

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: RecognitionIndicatorView 支持动态颜色

**Files:**
- Modify: `desktop/macos/Sources/AgentStickApp/OverlayController.swift:403-424`

- [ ] **Step 1: 在 `setup()` 中把硬编码颜色改为通过新方法设置**

把 `RecognitionIndicatorView.setup()`(原第 403-426 行)中这一段:

```swift
    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = NSColor.black.withAlphaComponent(0.34).cgColor
        ringLayer.lineCap = .round
        ringLayer.lineWidth = 3
        ringLayer.isHidden = true
        layer?.addSublayer(ringLayer)
        for xLayer in xLayers {
            xLayer.strokeColor = NSColor.black.withAlphaComponent(0.34).cgColor
            xLayer.lineCap = .round
            xLayer.lineWidth = 3
            xLayer.isHidden = true
            layer?.addSublayer(xLayer)
        }
        for bar in barLayers {
            bar.backgroundColor = NSColor.black.withAlphaComponent(0.34).cgColor
            bar.cornerRadius = 2
            layer?.addSublayer(bar)
        }
        layoutBars()
        startAnimating()
    }
```

替换为:

```swift
    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.lineCap = .round
        ringLayer.lineWidth = 3
        ringLayer.isHidden = true
        layer?.addSublayer(ringLayer)
        for xLayer in xLayers {
            xLayer.lineCap = .round
            xLayer.lineWidth = 3
            xLayer.isHidden = true
            layer?.addSublayer(xLayer)
        }
        for bar in barLayers {
            bar.cornerRadius = 2
            layer?.addSublayer(bar)
        }
        setTintColor(NSColor.black.withAlphaComponent(0.34))
        layoutBars()
        startAnimating()
    }

    func setTintColor(_ color: NSColor) {
        let cgColor = color.cgColor
        ringLayer.strokeColor = cgColor
        for xLayer in xLayers {
            xLayer.strokeColor = cgColor
        }
        for bar in barLayers {
            bar.backgroundColor = cgColor
        }
    }
```

- [ ] **Step 2: 编译确认无误**

Run: `cd desktop/macos && swift build --product AgentStickApp 2>&1 | tail -20`
Expected: `Build of product 'AgentStickApp' complete!`

- [ ] **Step 3: Commit**

```bash
git add desktop/macos/Sources/AgentStickApp/OverlayController.swift
git commit -m "feat: allow RecognitionIndicatorView tint color to be set dynamically

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: OverlayController 深色模式自适应接线

**Files:**
- Modify: `desktop/macos/Sources/AgentStickApp/OverlayController.swift:1-93` (顶部 + init + setThemeColor)
- Modify: `desktop/macos/Sources/AgentStickApp/OverlayController.swift:344-359` (删除旧的 `backgroundColor(for:)`)

- [ ] **Step 1: 添加 import 和自定义容器 view**

把文件顶部(原第 1 行)的:

```swift
import AppKit
```

改为:

```swift
import AgentStickCore
import AppKit

private final class OverlayContainerView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}
```

- [ ] **Step 2: 把 container 属性类型改为 OverlayContainerView**

把(原第 5 行):

```swift
    private let container = NSView()
```

改为:

```swift
    private let container = OverlayContainerView()
```

- [ ] **Step 3: 重写 init 中的颜色设置部分**

把 `init()` 中(原第 44-51 行)这一段:

```swift
        container.wantsLayer = true
        if let layer = container.layer {
            layer.backgroundColor = Self.backgroundColor(for: themeColor).cgColor
            layer.cornerRadius = 24
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            layer.borderWidth = 0
        }

        textLabel.font = .systemFont(ofSize: 30, weight: .regular)
        textLabel.textColor = NSColor.black.withAlphaComponent(0.68)
        textLabel.alignment = .center
        textLabel.maximumNumberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.usesSingleLineMode = false
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.textColor = NSColor.black.withAlphaComponent(0.42)
        hintLabel.alignment = .center
```

替换为:

```swift
        container.wantsLayer = true
        if let layer = container.layer {
            layer.cornerRadius = 24
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            layer.borderWidth = 0
        }
        container.onAppearanceChange = { [weak self] in self?.applyAppearanceColors() }

        textLabel.font = .systemFont(ofSize: 30, weight: .regular)
        textLabel.alignment = .center
        textLabel.maximumNumberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.usesSingleLineMode = false
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.alignment = .center
```

- [ ] **Step 4: 在 init 末尾(约束激活之后)调用一次颜色应用**

把 `init()` 结尾(原第 75-87 行)的:

```swift
        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: indicatorWidth),
            indicator.heightAnchor.constraint(equalToConstant: indicatorWidth),
            textLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: textLeadingInset),
            textLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            textCenterYConstraint,
            hintLabel.leadingAnchor.constraint(equalTo: textLabel.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor),
            hintLabel.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 8)
        ])
    }
```

改为:

```swift
        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: indicatorWidth),
            indicator.heightAnchor.constraint(equalToConstant: indicatorWidth),
            textLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: textLeadingInset),
            textLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            textCenterYConstraint,
            hintLabel.leadingAnchor.constraint(equalTo: textLabel.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor),
            hintLabel.topAnchor.constraint(equalTo: textLabel.bottomAnchor, constant: 8)
        ])

        applyAppearanceColors()
    }
```

- [ ] **Step 5: 简化 setThemeColor 并新增颜色计算方法**

把(原第 89-93 行):

```swift
    func setThemeColor(_ color: OverlayThemeColor) {
        guard themeColor != color else { return }
        themeColor = color
        container.layer?.backgroundColor = Self.backgroundColor(for: color).cgColor
    }
```

改为:

```swift
    func setThemeColor(_ color: OverlayThemeColor) {
        guard themeColor != color else { return }
        themeColor = color
        applyAppearanceColors()
    }

    private var currentAppearance: OverlayAppearance {
        container.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    private func applyAppearanceColors() {
        let appearance = currentAppearance
        let components = OverlayColorScheme.backgroundComponents(for: themeColor.colorSchemeTheme, appearance: appearance)
        container.layer?.backgroundColor = NSColor(
            calibratedRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha
        ).cgColor

        let textBase: NSColor = OverlayColorScheme.isLightText(for: appearance) ? .white : .black
        textLabel.textColor = textBase.withAlphaComponent(CGFloat(OverlayColorScheme.textAlpha(for: appearance)))
        hintLabel.textColor = textBase.withAlphaComponent(CGFloat(OverlayColorScheme.hintAlpha(for: appearance)))
        indicator.setTintColor(textBase.withAlphaComponent(CGFloat(OverlayColorScheme.indicatorAlpha(for: appearance))))

        if window.isVisible {
            applyText(textLabel.stringValue, shouldWrap: textLabel.maximumNumberOfLines != 1)
        }
    }
```

- [ ] **Step 6: 删除旧的静态 backgroundColor(for:) 方法**

删除文件末尾(原第 344-359 行)的:

```swift
    private static func backgroundColor(for color: OverlayThemeColor) -> NSColor {
        switch color {
        case .white:
            return NSColor.white.withAlphaComponent(0.86)
        case .pink:
            return NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.9, alpha: 0.86)
        case .green:
            return NSColor(calibratedRed: 0.84, green: 0.95, blue: 0.84, alpha: 0.86)
        case .yellow:
            return NSColor(calibratedRed: 1.0, green: 0.94, blue: 0.72, alpha: 0.86)
        case .blue:
            return NSColor(calibratedRed: 0.82, green: 0.91, blue: 1.0, alpha: 0.86)
        case .purple:
            return NSColor(calibratedRed: 0.9, green: 0.84, blue: 1.0, alpha: 0.86)
        }
    }
}
```

只保留结尾的 `}`(类的闭合括号),即整个方法体被移除。

- [ ] **Step 7: 编译确认无误**

Run: `cd desktop/macos && swift build --product AgentStickApp 2>&1 | tail -30`
Expected: `Build of product 'AgentStickApp' complete!`,无警告/报错。若报 `textAttributes` 中引用 `textLabel.textColor` 的地方类型不匹配,确认该方法仍读取 `textLabel.textColor` 属性(无需改动,因为它是实例属性访问)。

- [ ] **Step 8: Commit**

```bash
git add desktop/macos/Sources/AgentStickApp/OverlayController.swift
git commit -m "feat: adapt overlay colors to light/dark appearance

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: 悬浮窗深色模式人工验证

**Files:** 无代码修改,仅验证。

- [ ] **Step 1: 编译并运行 App**

Run: `cd desktop/macos && swift build --product AgentStickApp 2>&1 | tail -10`
Expected: 编译成功。

- [ ] **Step 2: 启动 App,在系统设置中切换浅色模式,触发一次录音(听写中状态)**

确认悬浮窗胶囊背景、文字均清晰可读,颜色与切换前一致(不应有回归)。

- [ ] **Step 3: 切换系统到深色模式,不重启 App,再次触发录音**

确认:
- 胶囊背景变为深色调,不再是刺眼的浅色。
- 文字变为浅色(白色系),对比度良好。
- 跳动条/倒计时环/暂停环/错误叉的线条颜色同步变浅,能看清。

- [ ] **Step 4: 依次切换悬浮窗的 6 种主题色(设置面板中選擇),在深色模式下逐一确认背景不刺眼、文字可读**

- [ ] **Step 5: 记录验证结果**

若发现问题,在此任务下继续修正 Task 6 中的代码,重新走 Step 1-4,直到全部通过后再进入 Task 8。

---

### Task 8: AgentTaskHistoryWindowController 数据模型分组 + NSOutlineView 迁移

**Files:**
- Modify: `desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift` (大范围改动,见下)

> 本 Task 只做结构迁移(分组 + NSOutlineView),列表行仍暂时使用旧的 ASCII 符号文字
> (`●`/`?`/`✓`/`×`),图标化在 Task 9 完成。这样可以保证本 Task 落地后应用仍可编译
> 运行,功能不回归。

- [ ] **Step 1: 添加 AgentStickCore 导入(已存在则跳过)**

确认文件顶部(原第 1-3 行)已有:

```swift
import AppKit
import AgentStickCore
import Foundation
```

如果 `AgentStickCore` 已导入则跳过此步。

- [ ] **Step 2: 替换类声明,新增分组用的模型类型和存储属性**

把(原第 5-36 行)从类声明开始到 `private var entries: [HistoryEntry] = []` 结束的这一段:

```swift
final class AgentTaskHistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onClearSessionHistory: (() -> Void)?
    private struct TaskEntry {
        let url: URL
        let date: Date
        let agent: String
        let prompt: String
        let exitCode: Int?
        let markdown: String

        var succeeded: Bool { exitCode == 0 }
    }

    private enum HistoryEntry {
        case approval(AgentApprovalRequest)
        case input(AgentInputRequest)
        case task(TaskEntry)
    }

    private let tableView = NSTableView()
    private let detailTextView = NSTextView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private let revealButton = NSButton()
    private let allowButton = NSButton()
    private let denyButton = NSButton()
    private let answerButton = NSButton()
    private let cancelInputButton = NSButton()
    private let deleteButton = NSButton()
    private let approvalCenter: AgentApprovalCenter
    private var entries: [HistoryEntry] = []
```

替换为:

```swift
final class AgentTaskHistoryWindowController: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onClearSessionHistory: (() -> Void)?
    private struct TaskEntry {
        let url: URL
        let date: Date
        let agent: String
        let prompt: String
        let exitCode: Int?
        let markdown: String

        var succeeded: Bool { exitCode == 0 }
    }

    private enum HistoryEntry {
        case approval(AgentApprovalRequest)
        case input(AgentInputRequest)
        case task(TaskEntry)
    }

    private enum SectionKind {
        case pending
        case history

        var title: String {
            switch self {
            case .pending: return currentLanguage == .chinese ? "待处理" : "Pending"
            case .history: return currentLanguage == .chinese ? "历史记录" : "History"
            }
        }
    }

    private final class HistorySectionItem {
        let kind: SectionKind
        init(kind: SectionKind) { self.kind = kind }
    }

    private final class HistoryEntryItem {
        let entry: HistoryEntry
        init(entry: HistoryEntry) { self.entry = entry }
    }

    private let outlineView = NSOutlineView()
    private let detailTextView = NSTextView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metadataLabel = NSTextField(labelWithString: "")
    private let moreButton = NSPopUpButton()
    private let allowButton = NSButton()
    private let denyButton = NSButton()
    private let answerButton = NSButton()
    private let cancelInputButton = NSButton()
    private let deleteButton = NSButton()
    private let approvalCenter: AgentApprovalCenter
    private let pendingSectionItem = HistorySectionItem(kind: .pending)
    private let historySectionItem = HistorySectionItem(kind: .history)
    private var pendingItems: [HistoryEntryItem] = []
    private var historyItems: [HistoryEntryItem] = []

    private var visibleSections: [HistorySectionItem] {
        pendingItems.isEmpty ? [historySectionItem] : [pendingSectionItem, historySectionItem]
    }

    private var selectedEntry: HistoryEntry? {
        guard outlineView.selectedRow >= 0,
              let item = outlineView.item(atRow: outlineView.selectedRow) as? HistoryEntryItem else { return nil }
        return item.entry
    }
```

注意:`openButton`/`revealButton` 属性被移除,改由 `moreButton` 承载(在 Task 10 中接入菜单)。

- [ ] **Step 3: 更新侧边栏构建代码,把 NSTableView 换成 NSOutlineView**

把 `buildContent()` 中(原第 100-125 行)这一段:

```swift
        let sidebar = NSView()
        let tableScrollView = NSScrollView()
        tableScrollView.hasVerticalScroller = true
        tableScrollView.drawsBackground = false
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(tableScrollView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task"))
        column.title = currentLanguage == .chinese ? "任务" : "Tasks"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 58
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableScrollView.documentView = tableView

        NSLayoutConstraint.activate([
            tableScrollView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            tableScrollView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            tableScrollView.topAnchor.constraint(equalTo: sidebar.topAnchor),
            tableScrollView.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
```

替换为:

```swift
        let sidebar = NSView()
        let tableScrollView = NSScrollView()
        tableScrollView.hasVerticalScroller = true
        tableScrollView.drawsBackground = false
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(tableScrollView)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task"))
        column.title = currentLanguage == .chinese ? "任务" : "Tasks"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 0
        outlineView.rowHeight = 58
        outlineView.intercellSpacing = NSSize(width: 0, height: 4)
        outlineView.selectionHighlightStyle = .regular
        outlineView.dataSource = self
        outlineView.delegate = self
        tableScrollView.documentView = outlineView

        NSLayoutConstraint.activate([
            tableScrollView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            tableScrollView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            tableScrollView.topAnchor.constraint(equalTo: sidebar.topAnchor),
            tableScrollView.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
```

- [ ] **Step 4: 重写 reloadEntries 并新增分组/选中辅助方法**

把(原第 251-292 行)从 `reloadEntries` 到 `interactionDate` 结束的这一段:

```swift
    private func reloadEntries(selecting resultURL: URL?, approvalID: UUID? = nil, inputID: UUID? = nil) {
        let directory = AppConfig.configDirectory.appendingPathComponent("Tasks", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let taskEntries = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(loadEntry)
            .sorted { $0.date > $1.date }
        let interactions: [HistoryEntry] = (
            approvalCenter.requests.map(HistoryEntry.approval) +
            approvalCenter.inputRequests.map(HistoryEntry.input)
        ).sorted { interactionDate($0) > interactionDate($1) }
        entries = interactions + taskEntries.map(HistoryEntry.task)
        tableView.reloadData()

        let targetPath = resultURL?.standardizedFileURL.path
        let selectedIndex = inputID.flatMap { id in
            entries.firstIndex { if case .input(let value) = $0 { return value.id == id }; return false }
        } ?? approvalID.flatMap { id in
            entries.firstIndex { if case .approval(let value) = $0 { return value.id == id }; return false }
        } ?? targetPath.flatMap { path in
            entries.firstIndex { if case .task(let value) = $0 { return value.url.standardizedFileURL.path == path }; return false }
        } ?? (entries.isEmpty ? nil : 0)
        if let selectedIndex {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedIndex)
            display(entries[selectedIndex])
        } else {
            displayEmptyState()
        }
    }

    private func interactionDate(_ entry: HistoryEntry) -> Date {
        switch entry {
        case .approval(let request): return request.createdAt
        case .input(let request): return request.createdAt
        case .task(let task): return task.date
        }
    }
```

替换为:

```swift
    private func reloadEntries(selecting resultURL: URL?, approvalID: UUID? = nil, inputID: UUID? = nil) {
        let directory = AppConfig.configDirectory.appendingPathComponent("Tasks", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let taskEntries: [HistoryEntry] = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap(loadEntry)
            .map(HistoryEntry.task)
        let interactionEntries: [HistoryEntry] =
            approvalCenter.requests.map(HistoryEntry.approval) +
            approvalCenter.inputRequests.map(HistoryEntry.input)
        let grouped = groupedSections(from: interactionEntries + taskEntries)
        pendingItems = grouped.pending.map(HistoryEntryItem.init)
        historyItems = grouped.history.map(HistoryEntryItem.init)
        outlineView.reloadData()
        outlineView.expandItem(pendingSectionItem)
        outlineView.expandItem(historySectionItem)

        let targetPath = resultURL?.standardizedFileURL.path
        let allEntries = (pendingItems + historyItems).map(\.entry)
        let targetEntry: HistoryEntry? = allEntries.first { entry in
            if let inputID { if case .input(let value) = entry { return value.id == inputID } }
            if let approvalID { if case .approval(let value) = entry { return value.id == approvalID } }
            if let targetPath { if case .task(let value) = entry { return value.url.standardizedFileURL.path == targetPath } }
            return false
        }
        let fallback = (inputID == nil && approvalID == nil && targetPath == nil) ? allEntries.first : nil
        if let entry = targetEntry ?? fallback, let item = outlineItem(for: entry) {
            let row = outlineView.row(forItem: item)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
            }
            display(entry)
        } else {
            displayEmptyState()
        }
    }

    private func groupedSections(from all: [HistoryEntry]) -> (pending: [HistoryEntry], history: [HistoryEntry]) {
        let items = all.map {
            HistoryGroupingItem(id: historyEntryID($0), isPending: isPendingEntry($0), date: interactionDate($0))
        }
        let grouped = HistoryEntryGrouping.group(items)
        let byID = Dictionary(uniqueKeysWithValues: all.map { (historyEntryID($0), $0) })
        return (
            grouped.pending.compactMap { byID[$0.id] },
            grouped.history.compactMap { byID[$0.id] }
        )
    }

    private func historyEntryID(_ entry: HistoryEntry) -> String {
        switch entry {
        case .task(let task): return "task:\(task.url.standardizedFileURL.path)"
        case .approval(let request): return "approval:\(request.id.uuidString)"
        case .input(let request): return "input:\(request.id.uuidString)"
        }
    }

    private func isPendingEntry(_ entry: HistoryEntry) -> Bool {
        switch entry {
        case .task: return false
        case .approval(let request): return request.state == .pending
        case .input(let request): return request.state == .pending
        }
    }

    private func outlineItem(for entry: HistoryEntry) -> HistoryEntryItem? {
        let id = historyEntryID(entry)
        return (pendingItems + historyItems).first { historyEntryID($0.entry) == id }
    }

    private func interactionDate(_ entry: HistoryEntry) -> Date {
        switch entry {
        case .approval(let request): return request.createdAt
        case .input(let request): return request.createdAt
        case .task(let task): return task.date
        }
    }
```

- [ ] **Step 5: 替换 NSTableViewDataSource/Delegate 方法为 NSOutlineViewDataSource/Delegate**

把(原第 434-477 行)从 `numberOfRows` 到 `tableViewSelectionDidChange` 结束的这一段:

```swift
    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("TaskHistoryCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let value = NSTableCellView()
            value.identifier = identifier
            let label = NSTextField(wrappingLabelWithString: "")
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            value.textField = label
            value.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: value.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: value.trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: value.centerYAnchor)
            ])
            return value
        }()
        switch entries[row] {
        case .task(let entry):
            let symbol = entry.succeeded ? "✓" : "!"
            cell.textField?.stringValue = "\(symbol) \(entry.agent.capitalized)\n\(entry.prompt)"
        case .approval(let request):
            let symbol: String
            switch request.state { case .pending: symbol = "●"; case .continuing: symbol = "↻"; case .allowed: symbol = "✓"; case .denied: symbol = "×" }
            cell.textField?.stringValue = "\(symbol) \(request.agent) · \(request.kind)\n\(request.summary)"
        case .input(let request):
            let symbol: String
            switch request.state { case .pending: symbol = "?"; case .submitted: symbol = "✓"; case .cancelled: symbol = "×" }
            cell.textField?.stringValue = "\(symbol) \(request.agent) · \(currentLanguage == .chinese ? "需要回答" : "Input needed")\n\(request.summary)"
        }
        cell.textField?.textColor = .labelColor
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard entries.indices.contains(row) else { return }
        display(entries[row])
    }
```

替换为:

```swift
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return visibleSections.count }
        guard let section = item as? HistorySectionItem else { return 0 }
        return section === pendingSectionItem ? pendingItems.count : historyItems.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return visibleSections[index] }
        guard let section = item as? HistorySectionItem else {
            fatalError("Unexpected outline item without a parent section")
        }
        return section === pendingSectionItem ? pendingItems[index] : historyItems[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is HistorySectionItem
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is HistorySectionItem
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is HistoryEntryItem
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        item is HistorySectionItem ? 22 : 58
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let section = item as? HistorySectionItem {
            let identifier = NSUserInterfaceItemIdentifier("HistorySectionHeader")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
                let value = NSTableCellView()
                value.identifier = identifier
                let label = NSTextField(labelWithString: "")
                label.font = .systemFont(ofSize: 11, weight: .bold)
                label.textColor = .secondaryLabelColor
                label.translatesAutoresizingMaskIntoConstraints = false
                value.textField = label
                value.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: value.leadingAnchor, constant: 12),
                    label.centerYAnchor.constraint(equalTo: value.centerYAnchor)
                ])
                return value
            }()
            cell.textField?.stringValue = section.kind.title.uppercased()
            return cell
        }
        guard let entryItem = item as? HistoryEntryItem else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("TaskHistoryCell")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let value = NSTableCellView()
            value.identifier = identifier
            let label = NSTextField(wrappingLabelWithString: "")
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            value.textField = label
            value.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: value.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: value.trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: value.centerYAnchor)
            ])
            return value
        }()
        switch entryItem.entry {
        case .task(let entry):
            let symbol = entry.succeeded ? "✓" : "!"
            cell.textField?.stringValue = "\(symbol) \(entry.agent.capitalized)\n\(entry.prompt)"
        case .approval(let request):
            let symbol: String
            switch request.state { case .pending: symbol = "●"; case .continuing: symbol = "↻"; case .allowed: symbol = "✓"; case .denied: symbol = "×" }
            cell.textField?.stringValue = "\(symbol) \(request.agent) · \(request.kind)\n\(request.summary)"
        case .input(let request):
            let symbol: String
            switch request.state { case .pending: symbol = "?"; case .submitted: symbol = "✓"; case .cancelled: symbol = "×" }
            cell.textField?.stringValue = "\(symbol) \(request.agent) · \(currentLanguage == .chinese ? "需要回答" : "Input needed")\n\(request.summary)"
        }
        cell.textField?.textColor = .labelColor
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let entry = selectedEntry else { return }
        display(entry)
    }
```

- [ ] **Step 6: 重写依赖 `entries[tableView.selectedRow]` 的操作方法**

把(原第 479-528 行)从 `refresh` 到 `deleteSelectedEntry` 结束的这一段:

```swift
    @objc private func refresh() {
        let selectedURL: URL? = entries.indices.contains(tableView.selectedRow) ? {
            if case .task(let entry) = entries[tableView.selectedRow] { return entry.url }
            return nil
        }() : nil
        reloadEntries(selecting: selectedURL)
    }

    @objc private func openSelectedTask() {
        guard entries.indices.contains(tableView.selectedRow), case .task(let entry) = entries[tableView.selectedRow] else { return }
        NSWorkspace.shared.open(entry.url)
    }

    @objc private func revealSelectedTask() {
        guard entries.indices.contains(tableView.selectedRow), case .task(let entry) = entries[tableView.selectedRow] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    @objc private func allowSelectedRequest() { resolveSelectedRequest(allowed: true) }
    @objc private func denySelectedRequest() { resolveSelectedRequest(allowed: false) }

    private func resolveSelectedRequest(allowed: Bool) {
        guard entries.indices.contains(tableView.selectedRow), case .approval(let request) = entries[tableView.selectedRow] else { return }
        approvalCenter.resolve(request, allowed: allowed)
        display(request)
        tableView.reloadData(forRowIndexes: IndexSet(integer: tableView.selectedRow), columnIndexes: IndexSet(integer: 0))
    }

    @objc private func deleteSelectedEntry() {
        guard entries.indices.contains(tableView.selectedRow) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = currentLanguage == .chinese ? "删除这条记录？" : "Delete this record?"
        alert.informativeText = currentLanguage == .chinese
            ? "任务文件会移到废纸篓；已处理的交互记录会从列表移除。"
            : "Task files move to Trash; completed interaction records are removed from the list."
        alert.addButton(withTitle: currentLanguage == .chinese ? "删除" : "Delete")
        alert.addButton(withTitle: currentLanguage == .chinese ? "取消" : "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        switch entries[tableView.selectedRow] {
        case .task(let task):
            NSWorkspace.shared.recycle([task.url]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.reloadEntries(selecting: nil) }
            }
        case .approval(let request):
            approvalCenter.remove(request)
        case .input(let request):
            approvalCenter.remove(request)
        }
    }
```

替换为:

```swift
    @objc private func refresh() {
        let selectedURL: URL? = { if case .task(let entry) = selectedEntry { return entry.url }; return nil }()
        reloadEntries(selecting: selectedURL)
    }

    @objc private func openSelectedTask() {
        guard case .task(let entry) = selectedEntry else { return }
        NSWorkspace.shared.open(entry.url)
    }

    @objc private func revealSelectedTask() {
        guard case .task(let entry) = selectedEntry else { return }
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    @objc private func allowSelectedRequest() { resolveSelectedRequest(allowed: true) }
    @objc private func denySelectedRequest() { resolveSelectedRequest(allowed: false) }

    private func resolveSelectedRequest(allowed: Bool) {
        guard case .approval(let request) = selectedEntry else { return }
        approvalCenter.resolve(request, allowed: allowed)
        reloadEntries(selecting: nil, approvalID: request.id)
    }

    @objc private func deleteSelectedEntry() {
        guard let entry = selectedEntry else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = currentLanguage == .chinese ? "删除这条记录？" : "Delete this record?"
        alert.informativeText = currentLanguage == .chinese
            ? "任务文件会移到废纸篓；已处理的交互记录会从列表移除。"
            : "Task files move to Trash; completed interaction records are removed from the list."
        alert.addButton(withTitle: currentLanguage == .chinese ? "删除" : "Delete")
        alert.addButton(withTitle: currentLanguage == .chinese ? "取消" : "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        switch entry {
        case .task(let task):
            NSWorkspace.shared.recycle([task.url]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.reloadEntries(selecting: nil) }
            }
        case .approval(let request):
            approvalCenter.remove(request)
        case .input(let request):
            approvalCenter.remove(request)
        }
    }
```

- [ ] **Step 7: 重写 cancelSelectedInput 和 answerSelectedInput 中依赖旧数组下标的部分**

把(原第 559-564 行):

```swift
    @objc private func cancelSelectedInput() {
        guard entries.indices.contains(tableView.selectedRow), case .input(let request) = entries[tableView.selectedRow] else { return }
        approvalCenter.resolve(request, answers: nil)
        display(request)
        tableView.reloadData(forRowIndexes: IndexSet(integer: tableView.selectedRow), columnIndexes: IndexSet(integer: 0))
    }
```

替换为:

```swift
    @objc private func cancelSelectedInput() {
        guard case .input(let request) = selectedEntry else { return }
        approvalCenter.resolve(request, answers: nil)
        reloadEntries(selecting: nil, inputID: request.id)
    }
```

把 `answerSelectedInput()` 的开头(原第 566-567 行):

```swift
    @objc private func answerSelectedInput() {
        guard entries.indices.contains(tableView.selectedRow), case .input(let request) = entries[tableView.selectedRow], request.state == .pending else { return }
```

替换为:

```swift
    @objc private func answerSelectedInput() {
        guard case .input(let request) = selectedEntry, request.state == .pending else { return }
```

把 `answerSelectedInput()` 的结尾(原第 634-648 行):

```swift
        guard response == .alertFirstButtonReturn else { return }
        var answers: [String: [String]] = [:]
        for (question, control) in controls {
            let value: String
            if let popup = control as? NSPopUpButton {
                value = popup.titleOfSelectedItem ?? ""
            } else {
                value = control.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            answers[question.id] = value.isEmpty ? [] : [value]
        }
        approvalCenter.resolve(request, answers: answers)
        display(request)
        tableView.reloadData(forRowIndexes: IndexSet(integer: tableView.selectedRow), columnIndexes: IndexSet(integer: 0))
    }
```

替换为:

```swift
        guard response == .alertFirstButtonReturn else { return }
        var answers: [String: [String]] = [:]
        for (question, control) in controls {
            let value: String
            if let popup = control as? NSPopUpButton {
                value = popup.titleOfSelectedItem ?? ""
            } else {
                value = control.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            answers[question.id] = value.isEmpty ? [] : [value]
        }
        approvalCenter.resolve(request, answers: answers)
        reloadEntries(selecting: nil, inputID: request.id)
    }
```

- [ ] **Step 8: 编译确认无误**

Run: `cd desktop/macos && swift build --product AgentStickApp 2>&1 | tail -30`
Expected: `Build of product 'AgentStickApp' complete!`。若报错提示 `openButton`/`revealButton` 未定义(因为 Step 2 中已移除),检查 `buildContent()` 里是否还有旧的按钮接线代码引用它们 —— 这些将在 Task 10 中一并处理;若此处编译因此报错,先临时保留 `private let openButton = NSButton()` 和 `private let revealButton = NSButton()` 两个属性声明(不删除),等 Task 10 再移除,以保证本 Task 可独立编译通过。

- [ ] **Step 9: Commit**

```bash
git add desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift
git commit -m "feat: group task history sidebar into pending/history sections via NSOutlineView

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: 任务历史行图标化 + 状态色点

**Files:**
- Create: `desktop/macos/Sources/AgentStickApp/AgentTaskHistoryCellViews.swift`
- Modify: `desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift`

- [ ] **Step 1: 创建 Cell View 文件**

```swift
import AppKit

final class HistoryEntryCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = .init(pointSize: 14, weight: .regular)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8)
        ])
    }

    func configure(symbolName: String, tintColor: NSColor, title: String, subtitle: String) {
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        iconView.contentTintColor = tintColor
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
    }
}

final class HistorySectionHeaderCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(title: String) {
        titleLabel.stringValue = title.uppercased()
    }
}
```

- [ ] **Step 2: 替换 outlineView(_:viewFor:item:) 为图标化版本,并新增辅助方法**

把 `AgentTaskHistoryWindowController.swift` 中 Task 8 Step 5 写入的
`outlineView(_:viewFor:tableColumn:item:)` 整个方法体(从 `func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {` 到对应的闭合 `}`)替换为:

```swift
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let section = item as? HistorySectionItem {
            return sectionHeaderView(for: section)
        }
        guard let entryItem = item as? HistoryEntryItem else { return nil }
        return entryCellView(for: entryItem.entry)
    }

    private func sectionHeaderView(for section: HistorySectionItem) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("HistorySectionHeader")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? HistorySectionHeaderCellView) ?? {
            let view = HistorySectionHeaderCellView()
            view.identifier = identifier
            return view
        }()
        cell.configure(title: section.kind.title)
        return cell
    }

    private func entryCellView(for entry: HistoryEntry) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("TaskHistoryCell")
        let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? HistoryEntryCellView) ?? {
            let view = HistoryEntryCellView()
            view.identifier = identifier
            return view
        }()
        let status = historyStatus(for: entry)
        cell.configure(
            symbolName: status.presentation.symbolName,
            tintColor: nsColor(for: status.presentation.color),
            title: title(for: entry),
            subtitle: subtitle(for: entry)
        )
        return cell
    }

    private func title(for entry: HistoryEntry) -> String {
        switch entry {
        case .task(let task): return task.agent.capitalized
        case .approval(let request): return "\(request.agent) · \(request.kind)"
        case .input(let request): return "\(request.agent) · \(currentLanguage == .chinese ? "需要回答" : "Input needed")"
        }
    }

    private func subtitle(for entry: HistoryEntry) -> String {
        switch entry {
        case .task(let task): return task.prompt
        case .approval(let request): return request.summary
        case .input(let request): return request.summary
        }
    }

    private func historyStatus(for entry: HistoryEntry) -> HistoryStatus {
        switch entry {
        case .task(let task): return task.succeeded ? .taskSucceeded : .taskFailed
        case .approval(let request):
            switch request.state {
            case .pending: return .approvalPending
            case .continuing: return .approvalContinuing
            case .allowed: return .approvalAllowed
            case .denied: return .approvalDenied
            }
        case .input(let request):
            switch request.state {
            case .pending: return .inputPending
            case .submitted: return .inputSubmitted
            case .cancelled: return .inputCancelled
            }
        }
    }

    private func nsColor(for color: HistoryStatusColor) -> NSColor {
        switch color {
        case .pending: return .systemOrange
        case .success: return .systemGreen
        case .failure: return .systemRed
        case .cancelled: return .secondaryLabelColor
        case .inProgress: return .systemBlue
        }
    }
```

- [ ] **Step 3: 在详情面板顶部加上同色状态点**

新增一个共用方法。在 `historyStatus(for:)` 方法后面插入:

```swift

    private func setMetadata(statusColor: NSColor, text: String) {
        let attributed = NSMutableAttributedString(
            string: "●  ",
            attributes: [.foregroundColor: statusColor, .font: NSFont.systemFont(ofSize: 11, weight: .bold)]
        )
        attributed.append(NSAttributedString(
            string: text,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 12)]
        ))
        metadataLabel.attributedStringValue = attributed
    }
```

把 `display(_ entry: TaskEntry)`(原第 342-362 行)中的:

```swift
        titleLabel.stringValue = entry.prompt
        metadataLabel.stringValue = "\(entry.agent.capitalized) · \(status) · \(formatter.string(from: entry.date)) · \(entry.url.path)"
```

改为:

```swift
        titleLabel.stringValue = entry.prompt
        setMetadata(
            statusColor: nsColor(for: (entry.succeeded ? HistoryStatus.taskSucceeded : HistoryStatus.taskFailed).presentation.color),
            text: "\(entry.agent.capitalized) · \(status) · \(formatter.string(from: entry.date)) · \(entry.url.path)"
        )
```

把 `display(_ request: AgentApprovalRequest)`(原第 364-390 行)中的:

```swift
        let status: String
        switch request.state {
        case .pending: status = currentLanguage == .chinese ? "等待授权" : "Waiting for approval"
        case .continuing: status = currentLanguage == .chinese ? "已允许 · 继续执行中" : "Allowed · Continuing"
        case .allowed: status = currentLanguage == .chinese ? "已允许" : "Allowed"
        case .denied: status = currentLanguage == .chinese ? "已拒绝" : "Denied"
        }
        titleLabel.stringValue = request.summary
        metadataLabel.stringValue = "\(request.agent) · \(request.kind) · \(status) · \(formatter.string(from: request.createdAt))"
```

改为:

```swift
        let status: String
        let statusKind: HistoryStatus
        switch request.state {
        case .pending: status = currentLanguage == .chinese ? "等待授权" : "Waiting for approval"; statusKind = .approvalPending
        case .continuing: status = currentLanguage == .chinese ? "已允许 · 继续执行中" : "Allowed · Continuing"; statusKind = .approvalContinuing
        case .allowed: status = currentLanguage == .chinese ? "已允许" : "Allowed"; statusKind = .approvalAllowed
        case .denied: status = currentLanguage == .chinese ? "已拒绝" : "Denied"; statusKind = .approvalDenied
        }
        titleLabel.stringValue = request.summary
        setMetadata(
            statusColor: nsColor(for: statusKind.presentation.color),
            text: "\(request.agent) · \(request.kind) · \(status) · \(formatter.string(from: request.createdAt))"
        )
```

把 `display(_ request: AgentInputRequest)`(原第 392-417 行)中的:

```swift
        let status: String
        switch request.state {
        case .pending: status = currentLanguage == .chinese ? "等待回答" : "Waiting for input"
        case .submitted: status = currentLanguage == .chinese ? "已回答" : "Answered"
        case .cancelled: status = currentLanguage == .chinese ? "已取消" : "Cancelled"
        }
        titleLabel.stringValue = request.summary
        metadataLabel.stringValue = "\(request.agent) · \(status) · \(formatter.string(from: request.createdAt))"
```

改为:

```swift
        let status: String
        let statusKind: HistoryStatus
        switch request.state {
        case .pending: status = currentLanguage == .chinese ? "等待回答" : "Waiting for input"; statusKind = .inputPending
        case .submitted: status = currentLanguage == .chinese ? "已回答" : "Answered"; statusKind = .inputSubmitted
        case .cancelled: status = currentLanguage == .chinese ? "已取消" : "Cancelled"; statusKind = .inputCancelled
        }
        titleLabel.stringValue = request.summary
        setMetadata(
            statusColor: nsColor(for: statusKind.presentation.color),
            text: "\(request.agent) · \(status) · \(formatter.string(from: request.createdAt))"
        )
```

把 `displayEmptyState()`(原第 419-432 行)中的:

```swift
        metadataLabel.stringValue = ""
```

改为:

```swift
        metadataLabel.attributedStringValue = NSAttributedString(string: "")
```

- [ ] **Step 4: 编译确认无误**

Run: `cd desktop/macos && swift build --product AgentStickApp 2>&1 | tail -30`
Expected: `Build of product 'AgentStickApp' complete!`

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Sources/AgentStickApp/AgentTaskHistoryCellViews.swift desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift
git commit -m "feat: show SF Symbol status icons and colored dots in task history

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: 详情面板底部按钮主次分组

**Files:**
- Modify: `desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift`

- [ ] **Step 1: 若 Task 8 Step 8 中临时保留了 openButton/revealButton 属性,现在删除**

确认属性声明区不再包含:

```swift
    private let openButton = NSButton()
    private let revealButton = NSButton()
```

(Task 8 Step 2 中的新版本已经不含它们;若因 Step 8 的兜底而仍存在,在此删除。)

- [ ] **Step 2: 重写按钮构建与 footer 排布**

把 `buildContent()` 中(原第 165-221 行)从 `let footer = NSStackView()` 到
`footer.addArrangedSubview(openButton)` 结束的这一段:

```swift
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(footer)

        let refreshButton = NSButton(
            title: currentLanguage == .chinese ? "刷新" : "Refresh",
            target: self,
            action: #selector(refresh)
        )
        let clearHistoryButton = NSButton(
            title: currentLanguage == .chinese ? "清空历史" : "Clear History",
            target: self,
            action: #selector(clearHistory)
        )
        openButton.title = currentLanguage == .chinese ? "打开原始文件" : "Open Original"
        openButton.target = self
        openButton.action = #selector(openSelectedTask)
        revealButton.title = currentLanguage == .chinese ? "在 Finder 中显示" : "Show in Finder"
        revealButton.target = self
        revealButton.action = #selector(revealSelectedTask)
        allowButton.title = currentLanguage == .chinese ? "允许" : "Allow"
        allowButton.bezelStyle = .rounded
        allowButton.keyEquivalent = "\r"
        allowButton.target = self
        allowButton.action = #selector(allowSelectedRequest)
        denyButton.title = currentLanguage == .chinese ? "拒绝" : "Deny"
        denyButton.bezelStyle = .rounded
        denyButton.target = self
        denyButton.action = #selector(denySelectedRequest)
        answerButton.title = currentLanguage == .chinese ? "回答…" : "Answer…"
        answerButton.bezelStyle = .rounded
        answerButton.keyEquivalent = "\r"
        answerButton.target = self
        answerButton.action = #selector(answerSelectedInput)
        cancelInputButton.title = currentLanguage == .chinese ? "取消请求" : "Cancel Request"
        cancelInputButton.bezelStyle = .rounded
        cancelInputButton.target = self
        cancelInputButton.action = #selector(cancelSelectedInput)
        deleteButton.title = currentLanguage == .chinese ? "删除记录" : "Delete"
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedEntry)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(refreshButton)
        footer.addArrangedSubview(clearHistoryButton)
        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(deleteButton)
        footer.addArrangedSubview(denyButton)
        footer.addArrangedSubview(allowButton)
        footer.addArrangedSubview(cancelInputButton)
        footer.addArrangedSubview(answerButton)
        footer.addArrangedSubview(revealButton)
        footer.addArrangedSubview(openButton)
```

替换为:

```swift
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(footer)

        let refreshButton = NSButton(
            title: currentLanguage == .chinese ? "刷新" : "Refresh",
            target: self,
            action: #selector(refresh)
        )
        refreshButton.bezelStyle = .inline
        refreshButton.isBordered = false

        let clearHistoryButton = NSButton(
            title: currentLanguage == .chinese ? "清空历史" : "Clear History",
            target: self,
            action: #selector(clearHistory)
        )
        clearHistoryButton.bezelStyle = .inline
        clearHistoryButton.isBordered = false
        clearHistoryButton.contentTintColor = .systemRed

        moreButton.pullsDown = true
        moreButton.bezelStyle = .inline
        moreButton.imagePosition = .noImage
        let moreMenu = NSMenu()
        moreMenu.addItem(NSMenuItem(title: currentLanguage == .chinese ? "更多" : "More", action: nil, keyEquivalent: ""))
        let openItem = NSMenuItem(
            title: currentLanguage == .chinese ? "打开原始文件" : "Open Original",
            action: #selector(openSelectedTask),
            keyEquivalent: ""
        )
        openItem.target = self
        moreMenu.addItem(openItem)
        let revealItem = NSMenuItem(
            title: currentLanguage == .chinese ? "在 Finder 中显示" : "Show in Finder",
            action: #selector(revealSelectedTask),
            keyEquivalent: ""
        )
        revealItem.target = self
        moreMenu.addItem(revealItem)
        moreButton.menu = moreMenu

        allowButton.title = currentLanguage == .chinese ? "允许" : "Allow"
        allowButton.bezelStyle = .rounded
        allowButton.keyEquivalent = "\r"
        allowButton.contentTintColor = .controlAccentColor
        allowButton.target = self
        allowButton.action = #selector(allowSelectedRequest)
        denyButton.title = currentLanguage == .chinese ? "拒绝" : "Deny"
        denyButton.bezelStyle = .rounded
        denyButton.target = self
        denyButton.action = #selector(denySelectedRequest)
        answerButton.title = currentLanguage == .chinese ? "回答…" : "Answer…"
        answerButton.bezelStyle = .rounded
        answerButton.keyEquivalent = "\r"
        answerButton.contentTintColor = .controlAccentColor
        answerButton.target = self
        answerButton.action = #selector(answerSelectedInput)
        cancelInputButton.title = currentLanguage == .chinese ? "取消请求" : "Cancel Request"
        cancelInputButton.bezelStyle = .rounded
        cancelInputButton.target = self
        cancelInputButton.action = #selector(cancelSelectedInput)
        deleteButton.title = currentLanguage == .chinese ? "删除记录" : "Delete"
        deleteButton.bezelStyle = .inline
        deleteButton.isBordered = false
        deleteButton.contentTintColor = .systemRed
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedEntry)

        let destructiveGroup = NSStackView(views: [clearHistoryButton, deleteButton])
        destructiveGroup.orientation = .horizontal
        destructiveGroup.spacing = 10

        let secondaryGroup = NSStackView(views: [refreshButton, moreButton])
        secondaryGroup.orientation = .horizontal
        secondaryGroup.spacing = 10

        let primaryGroup = NSStackView(views: [cancelInputButton, denyButton, allowButton, answerButton])
        primaryGroup.orientation = .horizontal
        primaryGroup.spacing = 10

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(destructiveGroup)
        footer.addArrangedSubview(secondaryGroup)
        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(primaryGroup)
```

- [ ] **Step 3: 更新三处 display 方法中对 openButton/revealButton 的显隐控制,改为 moreButton**

把 `display(_ entry: TaskEntry)`(Task 9 之后的版本)中的:

```swift
        openButton.isEnabled = true
        revealButton.isEnabled = true
        openButton.isHidden = false
        revealButton.isHidden = false
        allowButton.isHidden = true
```

改为:

```swift
        moreButton.isHidden = false
        moreButton.isEnabled = true
        allowButton.isHidden = true
```

把 `display(_ request: AgentApprovalRequest)` 中的:

```swift
        openButton.isHidden = true
        revealButton.isHidden = true
        answerButton.isHidden = true
```

改为:

```swift
        moreButton.isHidden = true
        answerButton.isHidden = true
```

把 `display(_ request: AgentInputRequest)` 中的:

```swift
        allowButton.isHidden = true
        denyButton.isHidden = true
        openButton.isHidden = true
        revealButton.isHidden = true
```

改为:

```swift
        allowButton.isHidden = true
        denyButton.isHidden = true
        moreButton.isHidden = true
```

把 `displayEmptyState()` 中的:

```swift
        openButton.isEnabled = false
        revealButton.isEnabled = false
        allowButton.isHidden = true
```

改为:

```swift
        moreButton.isEnabled = false
        moreButton.isHidden = true
        allowButton.isHidden = true
```

- [ ] **Step 4: 编译确认无误**

Run: `cd desktop/macos && swift build --product AgentStickApp 2>&1 | tail -30`
Expected: `Build of product 'AgentStickApp' complete!`,无 `openButton`/`revealButton` 未定义的报错。

- [ ] **Step 5: Commit**

```bash
git add desktop/macos/Sources/AgentStickApp/AgentTaskHistoryWindowController.swift
git commit -m "feat: regroup task history footer buttons by primary/secondary/destructive intent

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 11: 任务历史窗口人工验证

**Files:** 无代码修改,仅验证。

- [ ] **Step 1: 编译并启动 App**

Run: `cd desktop/macos && swift build --product AgentStickApp 2>&1 | tail -10`
Expected: 编译成功。

- [ ] **Step 2: 触发一次 Agent Run 任务并等待完成,打开 Agent 任务历史窗口**

确认已完成任务出现在「历史记录」分组下,图标为绿色/红色对勾/叉号(依据成功/失败),
标题与摘要清晰可读。

- [ ] **Step 3: 触发一次需要授权的操作(或使用现有测试脚本模拟),观察待授权请求**

确认:
- 待授权请求出现在「待处理」分组顶部,图标为橙色实心圆点。
- 分组标题「待处理」正确显示,且在没有待处理项时该分组连同标题一起消失。
- 点击「允许」或「拒绝」后,该条目从「待处理」移动到「历史记录」,图标变为绿色/红色。

- [ ] **Step 4: 触发一次需要回答的输入请求**

确认待回答请求同样出现在「待处理」分组,图标为橙色问号;点击「回答…」提交或
「取消请求」后正确移动到「历史记录」分组。

- [ ] **Step 5: 分别选中一个已完成任务、一个已处理的授权请求、一个已处理的输入请求**

确认详情面板底部按钮:
- 破坏性操作(清空历史、删除记录)在左侧,样式不显眼(无边框、红色文字)。
- 次要操作(刷新、更多▾)在其右侧,朴素样式。
- 主操作(允许/拒绝/回答/取消请求,视条目类型显示)始终在最右侧,允许/回答带强调色。
- 「更多」下拉菜单里的「打开原始文件」「在 Finder 中显示」仅在选中已完成任务时可用。

- [ ] **Step 6: 验证「清空历史」「删除记录」二次确认弹窗仍正常工作,不会误删待处理请求**

- [ ] **Step 7: 记录验证结果**

若发现问题,回到 Task 8/9/10 对应代码修正,重新执行本任务的 Step 1-6,直至全部通过。

---

### Task 12: 全量编译与收尾

**Files:** 无代码修改(除非验证中发现问题需要回头修正)。

- [ ] **Step 1: 运行完整 Core 测试套件**

Run: `cd desktop/macos && swift run AgentStickCoreTests 2>&1 | tail -5`
Expected: `AgentStickCoreTests passed`

- [ ] **Step 2: 完整编译 App 与 Hooks 两个可执行目标**

Run: `cd desktop/macos && swift build 2>&1 | tail -30`
Expected: 全部 target 编译成功,无警告/报错。

- [ ] **Step 3: 确认 git 状态干净,所有改动已提交**

Run: `git status`
Expected: `nothing to commit, working tree clean`(若有遗漏改动,补充 commit)。

- [ ] **Step 4: 更新设计文档状态(可选,若发现设计文档与实现有出入)**

若实现过程中对 [2026-07-24-desktop-ui-history-optimization-design.md](../specs/2026-07-24-desktop-ui-history-optimization-design.md)
有偏离(例如 Task 8 Step 8 提到的临时兜底方案),在该文档补充一段「实现备注」说明差异,并提交:

```bash
git add docs/superpowers/specs/2026-07-24-desktop-ui-history-optimization-design.md
git commit -m "docs: note implementation deviations for desktop UI optimization

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

若无出入,跳过此步。
