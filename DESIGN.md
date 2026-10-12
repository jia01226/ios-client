---
name: LoveApp · 记忆
description: 记忆花园与语录的原生设计记录，继承既有昼夜主题
colors:
  morandi-rose: "#BD949E"
  morandi-background: "#FAF3F4"
  morandi-ink: "#594B50"
  night-background: "#0E1430"
  night-accent: "#D9AE5F"
  flower-low: "rgb(52% 30% 37%)"
  flower-neutral: "rgb(97% 95% 95%)"
  flower-high: "rgb(94% 78% 83%)"
  quote-paper: "rgb(98% 97% 96%)"
typography:
  display:
    fontFamily: "Allura-Regular"
    fontSize: "32pt"
  title:
    fontFamily: "NotoSerifSC-ExtraLight"
    fontSize: "22pt"
  quote:
    fontFamily: "NotoSerifSC-ExtraLight"
    fontSize: "17pt"
  category:
    fontFamily: "NotoSerifSC-ExtraLight"
    fontSize: "15pt"
  caption:
    fontFamily: "NotoSerifSC-ExtraLight"
    fontSize: "13pt"
rounded:
  category: "4pt"
  empty-state: "12pt"
spacing:
  category-gap: "8pt"
  quote-gap: "14pt"
  category-inline: "16pt"
  garden-inline: "22pt"
  detail-inset: "24pt"
  header-inline: "26pt"
components:
  category:
    typography: "{typography.category}"
    rounded: "{rounded.category}"
    padding: "0pt 16pt"
  quote-paper-day:
    backgroundColor: "{colors.quote-paper}"
    typography: "{typography.quote}"
    padding: "14pt 0pt"
  detail:
    padding: "{spacing.detail-inset}"
---

# Design System: LoveApp · 记忆

## Overview

**Creative North Star: "月光清冷，山茶温柔"**

本记录限定于新「记忆」tab 的花园、语录和相关详情。轻法式、灰调莫兰迪与克制的手绘水彩共同形成氛围；花园把真实记忆放进环境，语录让原话留在浅纸色列表中。花园构图不构成聊天、我们、玩或抽屉的全 App 规则，也不覆盖既有 `.impeccable/surfaces/memory-review/` 文档。

主题、控件和画面分层继承现有实现。白天使用 `Theme.pageColor` 的莫兰迪体系，夜里接续深蓝与金色；场景图与记忆花保留独立绘制层。本文以 SwiftUI / UIKit 源码为准，尺寸单位为原生 pt；画布内部另有缩放坐标。sidecar 的 HTML/CSS 仅供设计面板示意，不是 App 原生源码。

**Key Characteristics:**

- 环境轻、花朵可辨，路径、水面与庭院铺地保留呼吸空间。
- 手写拉丁标题与中文宋体构成识别，操作说明沿用系统字型。
- 每朵山茶都有真实身份，密度与状态来自数据。

## Colors

### Primary

`morandi-rose` 是白天交互强调色，夜间改用 `night-accent`；分类下划线和详情操作跟随 `theme.pageAccent`。不把白天玫瑰色固定应用到所有主题。

### Secondary

`flower-low`、`flower-neutral`、`flower-high` 是花朵叠色，依次用于 valence 小于 0.15、居中区间、大于 0.6。低值以 0.78 不透明度叠色，其余以 0.45 叠色，保留原素材花瓣明暗。这些值描述绘制输入，不代表屏幕最终像素色。

### Neutral

`morandi-background` 与 `morandi-ink` 支撑白天页面；`night-background` 接续夜间页面。语录白天纸条使用 `quote-paper`，夜间使用白色 0.05 不透明度。其余次级文字沿用主题或系统 secondary，不新造一套色阶。

月下场景即使处于白天皮肤也使用浅字；花园浅场景文字使用源码中的冷灰蓝。顶部、底部渐变辅助读字，不能据此把整个 App 定义为深色界面。

## Typography

前置令牌记录实际使用的基础字号。Allura 用于「Les souvenirs」；中文场景标题、分类与语录用 NotoSerifSC-ExtraLight。对应 `Font.custom(..., relativeTo:)` 随动态字体调整；`caption` 在此专指标题旁的「记忆」，其余说明、日期和按钮使用原生 caption / subheadline / body。

记忆详情标题为 23pt、正文为系统 body；正文额外行间距为 7pt，引用为 5pt，语录为 6pt。不要把 SwiftUI 的 `lineSpacing` 误记成 CSS 行高，也不要给系统控件补上源码没有指定的字号或字重。

## Layout

花园与语录共用紧凑页头，原生分段选择器切换两页。花园将页头、来源开关、横向分类、场景名与数量叠在场景上，下方保留操作提示、花朵列表、回收入口和刷新。主 tab 栏延续 `RootTabView` 的昼夜两套外观，记忆使用 `camera.macro`。

五个主要分类映射为约定 → 月下、关系 → 水边、生活 → 城堡、身体 → 庭院、喜好 → 玻璃花房。额外分类不改名；恋爱沿用水边、医疗及未知分类沿用庭院。各场景种植区集中在 `MemoryFlowerLayout.plantingRegions(for:)`，这是调整排布的入口，勿把某张截图的坐标扩展为全局布局规则。

画布使用 1000 × 1778 的内部坐标，按可见区域等比填满，允许拖动及最高初始倍率五倍的双指缩放。ID 与场景决定稳定中心位置；importance、密度和远近共同影响尺寸。fallen 放到地面。超过 100 条且相对缩放小于 1.8 时显示聚合，放大后恢复单朵；聚合代表最多三个真实 ID，数量标签表示该组全部记忆。

分类与详情操作设有 44pt 最小高度；画布点选按缩放扩大命中区。重叠或无障碍选择通过「花朵列表」进入，不依赖在图上逐朵辨认。本文不把这些实现描述成已完成真机可用性验收。

## Elevation & Depth

环境纵深来自水彩素材的前后景、枝叶与留白。花朵用轻影融入背景，夜间有微光；loved 使用更明显的白色柔光与暖色花心亮点，并非持续跳动动画。原生详情与空态使用 regularMaterial，不以自制玻璃卡片替代。

仅记录源码中已存在的状态动效：收到 withered 状态后，移出花朵的位置短暂落下花瓣并淡出；减少动态效果开启时跳过。聚合点选使用原生缩放，减少动态效果时不做缩放动画。具体参数保存在 sidecar，未实现的风吹、呼吸、绽放动效不纳入规范。

## Shapes

分类是小圆角底面加细下划线；空态为较柔和的圆角材料面。语录采用原生 List 行与分组形状，未自定义的系统圆角不推断成固定 token。山茶轮廓来自透明素材 `MemoryBloom`、`MemoryBud`、`MemoryPetals`，不以通用圆形图标代替花瓣结构。

## Components

- **页面导航**：`MemoryPageHeader` 包含标题与花园 / 语录分段控件。Toggle 控制是否加入历史整理；分类选中态有强调色 0.12 不透明度底面与 1pt 下划线。
- **记忆花与花丛**：`bloom`、`bud`、`fallen` 对应盛放、花苞、落瓣。默认仅 `author=ke`；主动打开历史来源后，other 以 0.48 不透明度出现。普通与聚合共用 `drawFlower`，保留 valence、importance、来源和 loved 的语义。
- **详情与纠错**：原生 sheet 支持 medium / large 高度，展示标题、正文、最多三句原话及两种时间；原话左侧为强调色细竖线。喜欢、记错与找回等待服务端确认，失败保留原内容并提示。
- **花朵列表与回收**：列表用状态缩略图、标题、来源或归档说明及喜欢标志帮助精确选择；`withered` 只出现在回收入口，可找回。
- **语录纸条**：原话、可选备注、时间和回到聊天的箭头按顺序排列。日常直接显示，床上分组默认收起；侧滑移除需确认，只取消收藏。收藏备注输入使用原生 Form / TextField。

源码入口为 `KeApp/Features/Memories/MemoryGardenView.swift`、`MemoryGardenCanvas.swift`、`MemoryGardenModels.swift`、`AppQuotesView.swift`，共享主题在 `KeApp/Theme/Theme.swift`，主导航在 `KeApp/RootTabView.swift`。观察依据为 `Design/Build89/89-scene-courtyard.png`、`89-01-moon.png`、`89-08-dense-night-clusters.png`、`89-03-quotes.png`；`Approved/` 中的城堡、庭院图只记录确认过的方向，含装饰花的示意不可替代真实数据规则。

## Do's and Don'ts

### Do:

- Do 让每个可绘制节点对应唯一真实记忆 ID；空花园保留空态。
- Do 让花朵大小、颜色、状态与心光表达对应字段，聚合仍沿用相同语义与准确总数。
- Do 延续既有昼夜主题与原生控件，通过独立种植区调整花园排布。
- Do 保留花朵列表、明确错误提示和默认收起的床上语录。

### Don't:

- Don't 在背景加入记忆花或为画面丰满复制、凑数。
- Don't 将 withered 留在花园，或把客户端时间推断成服务端状态。
- Don't 将花园构图推广为全 App 必须遵守的界面规则。
- Don't 将方向图、设计面板示意、源码行为或模拟器截图表述为真机验收结论。
