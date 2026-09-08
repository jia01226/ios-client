---
name: LoveApp 记忆审卡
description: 回忆页入口、逐张核对、备注与完整原文的原生界面记录。
colors:
  day-rose-bg: "#FCF7F3"
  day-card: "#FFFFFF"
  day-rose-textPrimary: "#493A35"
  day-rose-accent: "#A0796E"
  night-bg: "#0E1430"
  night-card: "#172046"
  night-cardElevated: "#1E2A5C"
  night-textPrimary: "#F4F1EA"
  night-accent: "#D9AE5F"
typography:
  reviewFact:
    fontFamily: system-ui
    fontWeight: 600
  reviewBody:
    fontFamily: system-ui
    fontWeight: 400
  reviewCaption:
    fontFamily: system-ui
    fontWeight: 400
  pageTitle:
    fontFamily: system-ui
    fontSize: 30pt
    fontWeight: 600
  sectionTitle:
    fontFamily: system-ui
    fontSize: 17pt
    fontWeight: 500
rounded:
  radiusCard: 18pt
  radiusChip: 14pt
spacing:
  gapS: 8pt
  gapM: 14pt
  gapL: 20pt
  gapXL: 28pt
  pagePadding: 18pt
components:
  review-card:
    rounded: "{rounded.radiusCard}"
    padding: "{spacing.gapL}"
  review-action:
    rounded: "{rounded.radiusChip}"
    height: 66pt
  review-note-editor:
    typography: "{typography.reviewBody}"
    rounded: "{rounded.radiusCard}"
    padding: "{spacing.gapS}"
---

# Design System: LoveApp 记忆审卡

## Overview

本文记录 iOS SwiftUI 的记忆审卡局部界面，模式为 Operate。范围包括“回忆”页的审卡入口与已收下列表、核对卡组、备注 sheet、完整原文 sheet 和待同步记录 sheet。界面继承既有柔和白天与深蓝夜里主题，以事实、引证和判断操作为阅读顺序。

实现入口为 [MemoriesView](../../../KeApp/Features/Memories/MemoriesView.swift) 与 [MemoryReviewDeck](../../../KeApp/Features/Memories/MemoryReviewDeck.swift)。主题取值由 [Theme.swift](../../../KeApp/Theme/Theme.swift) 的 `Theme.color`、`Typo`、`Metrics` 决定；状态语义由 [MemoryReviewStore](../../../KeApp/Features/Memories/MemoryReviewStore.swift) 决定。本文只约束此表面，源码是变更时的取值依据。

**Key Characteristics:**

- 单张事实占据主要空间，来源与完整原文入口紧随其后。
- 操作位置固定为左侧“不对”、中间“备注”、右侧“收下”。
- 备注保留语境，暂缓保留稍后判断的入口，撤销恢复最近一次操作。
- 系统导航、分段选择器、sheet、键盘和 SF Symbols 承担原生交互。

## Colors

白天使用浅暖背景与白色卡片，夜里使用深蓝背景及分层蓝色卡片。正文与说明保持同一色相。

### Primary

交互 tint 继承 `Theme.effectiveAccent`。前置色值记录了白天默认“焦糖玫瑰”和夜里两种取值；审卡的三个主操作按钮使用正文色与卡片底色。

### Neutral

页面背景使用 `color.bg`，主卡与回忆页入口使用 `color.cardElevated`，后卡、操作按钮与备注输入区使用 `color.card`。正文使用 `color.textPrimary`；状态、来源与辅助说明使用 `Theme.reviewSecondary`，其派生关系记录在 sidecar。

白天实际通过 `Palette.chat(chatPalette)` 生成，颜色会随用户选择变化。其余白天配色及映射见 [ChatPalette.swift](../../../KeApp/Theme/ChatPalette.swift) 的 `ChatPalette.all` 和 `Palette.chat(_:)`；静态 `Palette.day` 不是 `Theme.color` 白天分支的取值入口。

## Typography

使用 SwiftUI 系统字体，审卡的事实、正文和说明分别对应 `Typo.reviewFact`、`reviewBody`、`reviewCaption`。这三个角色采用语义文字样式 `.title2`、`.body`、`.caption`，随 Dynamic Type 缩放；精确原生表达式见 sidecar。

事实采用半粗字重，引证和原文采用常规字重。入口标题、备注引导语及操作图标沿用固定字号的 `sectionTitle`；“回忆”页标题沿用 `pageTitle`。系统导航标题由 `NavigationStack` 管理。

卡面限制事实、引证、备注和来源的行数，适合逐张判断。完整原文页使用可滚动、可选取且不限行的正文，来源文字纵向展开；大字体阅读仍通过这一入口查看全部内容。

## Layout

回忆页为纵向滚动结构，审卡入口在已收下列表之前；分类筛选使用系统菜单 Picker。审卡页依次排列线路与同步状态、待审/暂缓分段选择器、错误提示、主卡、三个等宽操作按钮、手势说明和撤销按钮。

页面水平内边距采用 `pagePadding`，卡内采用 `gapL`，卡组与操作行间距采用 `gapM`。主卡填充剩余高度，事实与引证靠上，来源与原文入口靠下。`review-action.height` 表示原生实现的最小高度；原文入口、备注保存、刷新、重试和撤销使用 `Metrics.touchTarget` 作为最小高度。

备注 sheet 将说明、`TextEditor` 与两个保存操作纵向排列；完整原文 sheet 使用 `ScrollView`。这些页面沿用系统安全区域和键盘布局，没有独立的网页断点或列网格。

## Elevation & Depth

审卡内容以填色和前后卡偏移表达层次。队列有下一张时显示一层后卡，横向内缩并向下偏移；卡面、操作按钮和输入区没有自定义阴影。导航和 sheet 的系统材质与转场由平台承担。

## Shapes

主卡、后卡、回忆页入口和备注输入区使用 `radiusCard` 圆角；三个主操作按钮使用 `radiusChip`。拖动达到方向阈值时，主卡右上出现胶囊形操作提示。卡面的点击形状与圆角外形一致。

## Components

### 核对卡与操作行

卡面依次展示分类、待核对状态、事实、引证、非空备注或草稿、校验说明、来源和完整原文入口。水平拖动右侧为“收下”、左侧为“不对”；上划为“暂缓”，需要已有非空说明。无说明时上划打开备注 sheet。

方向判断采用 [MemoryReviewModels.swift](../../../KeApp/Features/Memories/MemoryReviewModels.swift) 的 `ReviewGesture.action`：按实际位移与主轴判断，未达到距离阈值时回弹。回弹、出卡、旋转与 Reduce Motion 的取值集中记录在 sidecar。按钮与 VoiceOver 自定义操作提供相同的判定入口。

来源不允许收下时，收下按钮禁用；本机记录不可用、待核对冲突或正在出卡时，操作行禁用。相关按钮通过降低不透明度明确呈现不可用状态，判定条件见 `MemoryReviewStore.canReview` 与卡片的 `can_accept`。

### 备注编辑

输入变化通过 `saveDraft` 写入本机。与已提交备注不同的内容属于草稿；卡面上的非空草稿标为“本机草稿，尚未提交”，同步状态也能提示未提交草稿。

“完成”和“只保存备注”都调用 `saveNote` 提交备注，成功写入本机操作队列后关闭 sheet，卡片继续留在原队列。“保存说明，先放着”提交暂缓并关闭；空白说明时禁用。交互关闭 sheet 会保留输入草稿。

### 完整原文

使用 `ReviewOriginalView` 展示完整事实、逐字引证及各条来源正文。每条来源保留渠道、时间和角色标签；`role == "user"` 显示“你的原话”，其余显示“助手原话，仅供核对”。正文支持文字选取，完成按钮关闭阅读 sheet。

### 同步、恢复与空态

`MemoryReviewStore.syncLabel` 区分核对服务器记录、本机操作待同步、同步中、未提交草稿及连接状态。操作先持久化到本机再同步；回忆页的已收下列表取自同步后的 `archive.facts`。

一般同步错误提供重试，阻塞操作提供“核对”入口。待同步记录 sheet 展示本次判定与备注，允许撤回该卡的本地操作、保留备注并刷新。`canReview` 在重新核对期间保持关闭。

“撤销上一张”恢复最近一次操作前的卡片与备注，并将卡移回队列前部；只保留一层撤销记录。没有可撤销操作或正在出卡时，按钮禁用。没有卡片时按连接状态与所选队列显示对应空态，并保留刷新入口。

## Do's and Don'ts

### Do:

- **Do** 通过现有主题 token 延续白天与夜里的配色，并保留审卡语义字体。
- **Do** 保持事实、引证、来源和角色标签的阅读层级，完整原文支持大字体与滚动。
- **Do** 保留固定方向的手势、可见按钮、未达阈值回弹及单步撤销。
- **Do** 清楚区分本机草稿、本机操作待同步和服务器已同步。

### Don't:

- **Don't** 把助手原话呈现为用户已确认的事实。
- **Don't** 把“完成”做成丢下未提交草稿的关闭按钮。
- **Don't** 仅靠手势提供判定，或在 Reduce Motion 开启时保留大幅出卡与旋转。
- **Don't** 将此表面的卡组布局扩展成全 App 的布局规定。
