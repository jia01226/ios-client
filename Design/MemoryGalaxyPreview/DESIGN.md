---
name: 记忆星河
description: 冷黑夜空、自然白色星尘与局部灰粉星云中的记忆亮星
colors:
  night: "#05070d"
  text: "#f1f0ed"
  muted: "#b7bdce"
  line: "rgba(194,203,223,.2)"
  script: "#e5dbee"
  focus: "#d8c4fb"
  popover: "#141923"
  sheet: "rgba(20,25,35,.95)"
  sheet-opaque: "#21192f"
  love: "#e4cddd"
  love-selected: "#ffc4d1"
typography:
  body:
    fontFamily: '-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif'
    fontSize: "15px"
    lineHeight: 1.6
  headline:
    fontFamily: "Song,serif"
    fontSize: "28px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: ".12em"
  script:
    fontFamily: "Pinyon,cursive"
    fontSize: "36px"
    lineHeight: 1.5
  title:
    fontFamily: "Song,serif"
    fontSize: "23px"
    fontWeight: 400
    letterSpacing: ".02em"
  label:
    fontSize: "12px"
    letterSpacing: ".11em"
rounded:
  circle: "50%"
  menu-item: "8px"
  love-button: "11px"
  popover: "15px"
  sheet: "20px"
spacing:
  compact: "8px"
  control: "12px"
  sheet-inset: "14px"
  sheet-padding: "24px"
components:
  icon-button:
    backgroundColor: "transparent"
    textColor: "{colors.text}"
    rounded: "{rounded.circle}"
    size: "44px"
  star-target:
    backgroundColor: "transparent"
    rounded: "{rounded.circle}"
    size: "44px"
  popover:
    backgroundColor: "{colors.popover}"
    rounded: "{rounded.popover}"
    padding: "10px"
    width: "222px"
  memory-sheet:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.text}"
    rounded: "{rounded.sheet}"
    padding: "14px 24px 24px"
  love-button:
    backgroundColor: "#d8c5e91c"
    textColor: "{colors.love}"
    rounded: "{rounded.love-button}"
    width: "100%"
  love-button-selected:
    backgroundColor: "#b0505d30"
    textColor: "{colors.love-selected}"
---

# Design System: 记忆星河

## Overview

**Creative North Star: "自然星光中的记忆"**

冷黑夜空承载倾斜的粒子旋涡，圆形星核和细星芒标记可以打开的记忆。星尘以冷白和淡暖白为主，局部灰粉；不均匀密度和暗带打断规则旋臂。文字与控件沿屏幕边缘布置，把中央空间留给银河。色光借鉴天文照片，不是物理模拟；候选效果仍由用户确认。

**Key Characteristics:**

- 低饱和星尘、柔白中心与大小不同的记忆亮星。
- 宋体中文标题、手写英文副题与系统字体正文。
- 冷灰蓝半透明浮层，细边线和柔和投影。

## Colors

主色来自自然白色星光；`night` 承载夜空，`text` 和 `muted` 分隔正文与辅助信息。`line` 用于列表、页脚与菜单的轻边界。`love-selected` 只用于已喜欢状态，亮星同时转为粉色柔光。程序绘制的粒子混色和光晕保留在绘制代码中，不另造静态色阶。

## Typography

`Song` 由本地 Noto Serif SC 字体提供，用于页面标题、旁白和记忆标题。英文副题采用用户选定的 15 号：Pinyon Script Regular，额外右倾 `skewX(-16deg)`、横向比例 `.9`，不伪造细字重；常规 36px、窄屏 32px、短屏 30px（窄屏规则优先）。正文使用系统无衬线。卡片正文行高为 1.95，引用为 1.9；辅助文字为 11–13px。此预览没有统一比例生成的字号系统。

## Layout

移动端画布铺满可视高度，最小高度 580px、最大宽度 500px，并尊重顶部与底部安全区。宽度达到 600px 时，以 430px 宽的居中预览展示，高度最多 932px，外框圆角 26px。标题、页脚覆盖于独立绘制层之上。

记忆卡片与列表固定在底部，左右留 14px，最大高度为画布的 75%；高度不超过 700px 时提升到 82%，内容可独立滚动。点击与图标控件保留至少 44px 的触达范围。

## Elevation & Depth

银河依靠粒子密度、加法混色、星核柔光与星芒产生深度。界面浮层采用背景模糊、顶部细边线与柔和投影。菜单投影为 `0 16px 48px #0008`，底部浮层为 `0 18px 70px #0009`；浮层模糊为 24px。系统要求降低透明度时，底部浮层使用 `sheet-opaque` 并关闭模糊。

## Shapes

记忆触点与图标按钮呈圆形。菜单、喜欢按钮和底部浮层采用各自已实现的圆角。四芒亮星由曲线绘制，纵轴较长，外围柔光扩散；星尘保持细小颗粒。

## Components

- **银河与亮星**：WebGL 粒子、Canvas 雾光和流星、HTML 记忆按钮分层。星尘无交互；每颗亮星对应固定记忆 ID。拖动平移、双指或滚轮缩放；设置提供拉近、拉远和复位。
- **图标按钮与设置菜单**：透明圆形按钮打开深紫菜单，菜单项悬停加浅色底。按钮按下透明度降至 .65，键盘焦点使用 2px 描边、4px 偏移。
- **记忆卡片与列表**：共用底部浮层。卡片含标题、正文、引用、日期与喜欢按钮；列表提供逐条打开入口。打开后焦点进入弹层、背景控件暂停接收焦点，Tab 在弹层内循环；Escape 关闭，焦点回到入口。
- **喜欢按钮**：用文字、`aria-pressed`、粉色状态和心形填色共同表达切换；状态只保留在本次预览。
- **动态**：卡片以 450ms、`cubic-bezier(.16,1,.3,1)` 从下方 24px 出现。银河慢速自转，流星偶发。系统减弱动态时停止装饰动画与 CSS 过渡，视角直接变化；用户也可手动暂停。

## Do's and Don'ts

- Do 保留近黑天空、最亮的柔白中心和局部低饱和云色，不把粉紫铺满背景。
- Do 用 `starPulse` 为记忆星错开呼吸和轻闪；`meteorPath` 固定右上到左下。暂停和系统减弱动态时停止这些装饰循环。
- Do 为可点击的记忆保留 HTML 按钮、可见键盘焦点与列表入口。
- Do 将减弱动态与降低透明度的系统偏好落实到现有组件。
- Don't 将参考截图的字幕、播放键或作者按钮加入界面。
- Don't 把环境星尘表现为可打开的记忆。
