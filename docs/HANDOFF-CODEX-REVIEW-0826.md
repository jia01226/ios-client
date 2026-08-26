# 交接 · iOS 聊天重构独立核查（2026-08-26）

> 本文是一张一次性审核工单。审核对象只包括 iOS 原生 App 的聊天重构，不包括 PWA、VPS 后端、人格或记忆库。原先“必须由 CC 核查”的流程已经取消，本轮改由另一扇独立 Codex 窗核查。

## 先给结论边界

- 仓库：`jia01226/ios-client`
- 审核分支：`codex/chat-refactor-0826`
- 功能代码终点：`4d5fb0a9d90ba2ee30de2521b07a38ae75988219`
- 对比起点：`a26ae85a27910e30b230db70fc3b943dfcc1f339`
- 当前阶段：代码已提交并推送，尚未合并、打包、部署或安装。
- 审核通过后仍先停下，把结论交给佳佳；是否合并和打包由佳佳决定。

本地工作树在：

```text
C:\Users\甜崽小慢\Documents\ios-client-chat-refactor
```

开始前执行：

```powershell
git fetch origin
git status --short
git rev-parse HEAD
git diff --check a26ae85a27910e30b230db70fc3b943dfcc1f339..4d5fb0a9d90ba2ee30de2521b07a38ae75988219
git diff --stat a26ae85a27910e30b230db70fc3b943dfcc1f339..4d5fb0a9d90ba2ee30de2521b07a38ae75988219
```

若本地工作树正在被别的窗口使用，不要切它的分支；另建一个 detached worktree 审查：

```powershell
git worktree add ..\ios-client-review-0826 --detach origin/codex/chat-refactor-0826
```

## 用户要的最终行为

### Thinking

1. 聊天时间线里只显示一行固定高度的 `Thinking` 入口，不再在消息列表内部展开长思考。
2. 点击入口后，从底部弹出系统原生 Sheet；它覆盖聊天页面，不改变底层聊天记录的高度和位置。
3. Sheet 支持中等和全屏两档、系统拖拽指示条、内部独立滚动；思考内容不设长度上限。
4. 标题保持英文 `Thinking`，内容只显示中文，不出现“原文为英文”之类标记。
5. 真思考 `thoughtSummary` 和小念头 `thoughtNote` 分字段保存、在同一个 Sheet 内展示，不允许互相覆盖。
6. 流式回复期间打开 Sheet，思考文字继续实时更新。
7. 关闭 Sheet 后，底层聊天记录仍停在打开前的位置。
8. Thinking 入口与所属回复气泡之间使用 4pt 间距。

### 聊天时间线与键盘

1. 时间线由一个滚动所有者负责，避免 SwiftUI 与 UIKit 同时抢滚动位置。
2. 打开键盘时自动看到最新回复，输入栏位于键盘上方，底部 Tab 暂时隐藏。
3. 收起键盘后底部 Tab 恢复，消息不留下大块空白，也不发生二次跳动。
4. 从较远的历史位置点击输入框时，最终消息完整出现在键盘上方。
5. 打开附件面板时只覆盖已有聊天，不推动消息位置。
6. 连续切换底部 Tab 后，聊天不能出现空白页或卡死。
7. 柯的长回复必须完整换行，不出现省略号；需要换行的气泡使用聊天区可用宽度并顶到右边。

## 代码结构变化

审核重点不只是 UI 是否能点开，还要确认重构边界是否干净：

- `KeApp/Features/Chat/ChatView.swift`
  - 从约 2700 行降为页面编排层。
  - 负责组合时间线、输入区、附件层和 Thinking Sheet，不再承载全部聊天业务。
- `KeApp/Features/Chat/ChatViewModel.swift`
  - 承接消息加载、流式状态、发送、恢复和页面状态。
- `KeApp/Features/Chat/ChatCollectionTimeline.swift`
  - 基于 ChatLayout 管理消息列表、自尺寸更新、锚点和键盘跟随。
  - 这是本轮最需要挑剔检查的文件。
- `KeApp/Features/Chat/ChatMessageViews.swift`
  - 承接气泡、Thinking 固定入口和 Thinking Sheet。
  - 短回复按内容收紧；真实排版宽度放不下时自动换成整行气泡，不再按字符数猜宽度。
- `KeApp/Features/Chat/ChatStatusViews.swift`
  - 承接加载、离线、空状态等状态视图。
- `KeApp/RootTabView.swift`
  - 键盘出现时隐藏底部 Tab，键盘消失后恢复。
- `KeAppTests/MessagePresentationTests.swift`
  - 增加 Thinking 独立时间线条目以及空思考不渲染的单元测试。
- `KeAppUITests/ThinkingInteractionTests.swift`
  - 覆盖 Sheet、流式、消息分条、键盘、附件、Tab 和空白聊天回归。
- `.github/workflows/ios-thinking-simulator.yml`
  - 手动工作流会运行模拟器测试，并导出截图与 `xcresult`。

分支相对起点共修改 11 个文件。请看实际 diff，不以行数判断质量。

## 必查风险

### P0：会造成用户直接不可用

- 冷启动或切 Tab 后消息列表偶发空白。
- 键盘、附件面板、Thinking Sheet 任一出现或消失时，时间线发生不可解释的跳动。
- 流式消息重复、丢失、停止更新，或者产生第二个回复气泡。
- Sheet 展开后，底层时间线仍在自动跟随流式内容。
- `thoughtSummary` 与 `thoughtNote` 再次写进同一个字段。

### P1：交互与架构回退

- `ChatView` 重新承担业务逻辑，拆分只是搬文件，没有形成清楚边界。
- SwiftUI 外层滚动与 `ChatCollectionTimelineController` 同时调整偏移。
- 键盘通知观察者未解除、异步闭包形成引用环，或控制器销毁后仍修改 UI。
- 自尺寸 Cell 更新后使用未经布局确认的最后一个 index path，导致只露出 Thinking 标题、正文落在键盘下面。
- Sheet 打开期间持有过期消息快照，流式文字不更新。
- 无思考或用户消息生成空的 Thinking 入口。

### P2：视觉与无障碍

- Thinking 标题不是现有花体样式，或者被改成中文。
- 思考正文出现英文标记。
- Thinking 与气泡间距明显大于约定的 4pt。
- 长回复显示省略号、文字被截断，或换行后仍在右侧留下不必要的大块空位。
- 键盘出现后底部 Tab 仍覆盖输入框。
- VoiceOver 无法知道 Thinking 可点击，或“完成”按钮无法关闭 Sheet。

## 已有自动化证据

以下三次完整工作流都跑在功能提交 `4d5fb0a9d90ba2ee30de2521b07a38ae75988219`，且结论为 `success`：

1. <https://github.com/jia01226/ios-client/actions/runs/32945969958>
2. <https://github.com/jia01226/ios-client/actions/runs/32946598199>
3. <https://github.com/jia01226/ios-client/actions/runs/32947029480>

每次包含 7 项单元测试与 12 项 UI 测试。截图和 `xcresult` 均已作为工作流 Artifact 上传，保留 14 天。可下载最后一轮证据：

```powershell
gh run download 32947029480 --repo jia01226/ios-client --name ChatSimulator-screenshots --dir .review-artifacts\screenshots
gh run download 32947029480 --repo jia01226/ios-client --name ChatSimulator-xcresult --dir .review-artifacts\xcresult
```

已有自动化通过不等于审核通过。请至少亲眼看以下截图状态：

- 静态 Thinking Sheet 展开和关闭。
- 流式思考在 Sheet 内更新。
- 分条气泡到达时底层时间线不移动。
- 键盘出现和收起各两轮。
- 长回复完整换行并使用聊天区可用宽度。
- 附件面板覆盖时间线。
- 连续 12 次切 Tab 后聊天不空白。

## 建议复跑方法

不要打 `app-v` tag。只手动触发审核分支的模拟器工作流：

```powershell
gh workflow run ios-thinking-simulator.yml --repo jia01226/ios-client --ref codex/chat-refactor-0826
```

等待完成后确认运行的 `headSha` 与被审代码一致，再看测试结论和截图，不要只看绿色图标。

## 审核回报格式

请按代码审查方式回报，不要只写“通过”或“看起来没问题”。

### 发现的问题

- 按 P0、P1、P2 排序。
- 每条写清文件、行号、触发条件、用户会看到的结果。
- 没有发现就明确写“未发现阻塞问题”。

### 亲眼验过

- 列出实际打开的截图、运行记录和复跑结果。
- 写明审核对应的完整提交 SHA。

### 没有验过

- Windows 本机没有 Xcode 或真机时如实写明。
- 模拟器通过不能写成真机通过。

### 最终判定

只能选一个：

- `通过，可以交佳佳决定是否合并和打包`
- `不通过，修完以下阻塞项后重新核查`

## 本轮禁止事项

- 不碰 PWA。
- 不碰 VPS、`goodlove` 或 `kongkong`。
- 不合并到 `main`。
- 不打包、不部署、不安装。
- 不借审核之名顺手增加功能或改变已经确认的 UI。
