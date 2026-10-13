---
name: 水畔 · 2.5D 网页预览
description: 单地点月光水边的实现记录，尚未获用户验收
colors:
  ink: "#30384b"
  rose: "#8f5367"
  surface: "rgba(247,243,245,.93)"
  canvas-ground: "#8a96b8"
  secondary-ink: "#515a6d"
  quote-ink: "#66617c"
  path-surface: "#f8f2f0e8"
  menu-surface: "#f6f3f0cc"
  hover-surface: "#fff5"
  active-surface: "#e6d7e19c"
typography:
  display:
    fontFamily: "Camellia, serif"
    fontSize: "28px"
    fontWeight: 400
    letterSpacing: ".15em"
  script:
    fontFamily: "Allura, cursive"
    fontSize: "28px"
  title:
    fontFamily: "Camellia, serif"
    fontSize: "22px"
    fontWeight: 500
    lineHeight: 1.5
  body:
    fontFamily: "Camellia, serif"
    fontSize: "15px"
    lineHeight: 2.1
  quote:
    fontFamily: "Camellia, serif"
    fontSize: "14px"
    lineHeight: 1.9
  label:
    fontFamily: "Camellia, serif"
    fontSize: "12px"
    lineHeight: 1.8
rounded:
  panel: "14px"
  path: "24px"
  circle: "50%"
spacing:
  control-block: "10px"
  control-inline: "14px"
  panel: "20px"
  list: "24px"
components:
  plain-button:
    textColor: "{colors.ink}"
    padding: "10px 14px"
  plain-button-hover:
    backgroundColor: "{colors.hover-surface}"
  plain-button-active:
    backgroundColor: "{colors.active-surface}"
  menu-button:
    backgroundColor: "{colors.menu-surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.circle}"
    padding: "11px"
  path-button:
    backgroundColor: "{colors.path-surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.path}"
    padding: "9px 14px"
  memory-card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
    padding: "30px 28px 24px"
    width: "min(430px,calc(100% - 36px))"
---

# Design System: 水畔网页预览

## Overview

**Creative North Star: "月光水畔"**

本文件只约束 `Design/WaterGardenPreview/` 的网页候选，记录代码和已保存截图呈现的视觉事实，不替代仓库根部设计体系或原生 App 规范。此表面采用 Experience 模式：用户进入一幅能拖动、抬头和点花的画，界面让位于水岸本身。材料方向是手绘柔光油画，莫兰迪浅粉、蓝、紫覆盖花海、天空与水面；月光清冷而明亮，不营造阴森感。这是本轮表面的方向，不将根产品中其他地点的水彩约束改写为全局油画规则。

依据为 [样式](dist/style.css)、[网页结构](dist/index.html)、[渲染与交互](dist/app.mjs)、[坐标与分配](dist/world.mjs)，以及四张实际网页截图：[水边](review/mobile-water.jpg)、[月亮](review/mobile-moon.jpg)、[记忆](review/mobile-memory.jpg)、[减弱动态时的记忆](review/mobile-reduced-memory.jpg)。`master.png` 是生成与校准母画，不参与运行时叠图，也不是获批 UI 效果图；本轮没有已批准 UI comp。原型尚未获用户验收，不是 App，没有接真实记忆。

**Key Characteristics:**

- 花海、石岸与枝叶共同存在于中景画中；24 处微亮花心是记忆入口，不另叠单花图片。
- 远、中、近三层制造有限画幅内的视差，保持单地点连续感。
- 蝴蝶飞落花心后出现浅色记忆卡片，背景保持可见。
- 中文衬线与一行法文手写体构成标题；功能文案小而可操作。
- 未开放的路径明确说明状态，所有记忆内容均为匿名合成示例。

## Colors

场景颜色来自本地位图，CSS 色值只描述界面与画布底色，不能据此把整幅画改成平涂色块。前置 tokens 的值是代码抽取值；下面只说明用途。

### Primary

- **灰玫瑰**（`rose`）：键盘焦点轮廓、选择框强调色和返回提示按钮文字。它是功能强调色，不是覆盖场景的主色。

### Neutral

- **蓝灰墨色**（`ink`）：标题、按钮、卡片正文。
- **柔粉纸面**（`surface`）：选项、列表、记忆与未开放提示的半透明共同表面。
- **灰蓝底色**（`canvas-ground`）：页面与每帧画布底色，场景位图覆盖其上。
- **次级蓝灰 / 引语灰紫**（`secondary-ink`、`quote-ink`）：日期、示例说明及引用层级。
- **暖白路径面 / 暖白菜单面**（`path-surface`、`menu-surface`）：画上导航与菜单按钮的阅读底。
- **透白悬停面 / 灰粉按下面**（`hover-surface`、`active-surface`）：普通文字按钮状态。路径及菜单按钮由更具体的背景声明覆盖，不承诺这些状态会改变所有按钮的背景。

**The Visible Water Rule.** 记忆卡片打开时不添加全屏压暗层；保留画面的月光、水色与花海。

## Typography

`Camellia` 是 CSS 为本地 `assets/NotoSerifSC.ttf` 起的字体别名，实际字体为 Noto Serif SC，回退为 `serif`。`Allura` 使用本地 `assets/Allura-Regular.ttf`，回退为 `cursive`，只用于 “Au bord de l’eau”。两者使用 `font-display: swap`；各自的 SIL OFL 1.1 文本随资产提交：[中文字体许可](dist/assets/NotoSerifSC-OFL.txt)、[Allura 许可](dist/assets/Allura-OFL.txt)。这不是外部字体服务，也没有名为 Camellia 的第三套字体。

前置 tokens 记录标题、正文、引语和辅助文字。页面标题保持疏朗字距，记忆标题使用中等字重，正文以较宽行距承接短段阅读。中文标题与手写副题有白色柔光文字阴影；功能控件延续中文衬线，不引入第三种标签字体。

小屏断点（480px）把页面标题改为（25px）、手写副题改为（26px）。路径标签从（13px）改为（12px）；记忆正文仍保持 body token。列表主文字（14px），日期（11px），日期不换行。源码未声明字体文件覆盖的字重轴范围，本文不作额外保证。

## Layout

这是全屏画布加少量覆盖控件，容器为（100vw × 100dvh），页面禁止整体滚动。原画坐标为（1536 × 1024）；按覆盖视口的比例再乘（1.32）与镜头缩放，边缘夹紧。初始镜头为（x 760、y 565、zoom 1），缩放交互范围（1–1.65）。它不是可以绕到物体背后的三维场景。

顶部标题靠左、菜单靠右；常规横向留白（30px），小屏（22px）。顶部常规样式计入安全区，但小屏规则覆盖为固定上边距（24px），不据此声称所有刘海设备已验证。底部提示与三条路径居中，底部安全区仍计入间距。打开记忆时底部区域隐藏，卡片居中靠底（26px），最大高度（70dvh）并可滚动。

选项面板宽（280px），右侧（24px，小屏18px），顶部（90px）。花列表最大宽（480px），常规四周定位为（100px 24px 32px），小屏为（88px 18px 20px），内容超出时在面板内滚动。没有桌面侧栏或多列信息架构。

截图检验记录为窄视口（365 × 733）。桌面截图受预览工具缩放故障影响，未完成有效桌面视觉验收；横屏坐标单测不等同于桌面布局验收。该限制及完整运行记录见 [交接](../../docs/HANDOFF-WATER-GARDEN-2P5D.md)。

## Elevation & Depth

空间主要由位图遮挡与视差产生：远景 `far.png` 包含天空、月亮、远山和远水；中景 `midground.png` 包含水面、岸石和整片花海；透明近景 `foreground.png` 为叶枝。镜头位移倍率分别为（0.68 / 1 / 1.26）。热点绘制与点击命中共用中景的变换，不能把花心固定在屏幕上。

覆盖面板共用轻柔环境阴影（`0 12px 40px #29314633`）和背景模糊（16px），以浅纸面保证文字可读，不把整页转为暗色。记忆卡片上沿有（1px）白边。header/footer 的局部透明渐变支持标题与底部提示阅读；它们不因点花而扩张成全屏遮罩。

普通镜头移动使用 cubic-out（`1 - (1 - t)^3`），默认（1300ms），返回记忆前视角（1050ms），看月亮（1700ms），进入未开放路径（1800ms）。这些是当前实现值，不是性能保证。水面局部微光、近景轻摆、8 个微光点与最多2片远处花瓣提供装饰运动。

## Shapes

控件形成三类轮廓：圆形菜单、圆角胶囊路径、柔和矩形阅读面板；半径以 tokens 为准。记忆卡片不是花瓣形状。画中的花和岸线保留绘制的不规则轮廓，热点只为花心加光，不插入独立花朵轮廓或灌木图片。SVG 线条端点与连接圆润，默认图标（22px）、路径图标（16px）。

## Components

### 画布与记忆花心

24 个 slot 为 `water-01` 至 `water-24`，坐标属于最终中景画；画中其余花属于环境素材，不代表额外已保存记忆。点击允许花心周围（28 CSS px）的邻近范围，移动距离小于（8px）才按点击处理；键盘用户可用文字列表选择，不需要猜测 Canvas 像素位置。左右拖动看两岸、向上拖动抬头，双指/滚轮缩放；画布获得焦点后支持四个方向键。

数据接口 `allocateMemories(records, previousManifest)` 保留有效的旧 ID→slot 映射。后续接真数据必须持久保存返回的 `assignments` 并传回；当前网页没有持久化服务，不能把稳定分配算法写成已完成的长期记忆存储。第25条起进入 `overflow`，提供 `water-deeper` 的后续地点标识；深处地点尚未实现。

### 蝴蝶与记忆卡片

点花后镜头靠近，现有贝母感半透明蝴蝶图集沿弧线飞向花心，飞行（1450ms）结束后出现卡片。卡片按日期、标题、正文、引语和匿名说明排列；进入时上升（14px）、淡入（450ms，`cubic-bezier(.16,1,.3,1)`）。卡片不是模态对话框，不锁定背景焦点；可以合上，也可以重新拖动画面。

打开卡片把键盘焦点移到合上按钮；合上后恢复原视角，并回到仍可见的先前焦点；先前控件已隐藏时回到可见画布。Escape 可合上记忆和面板。这里没有喜欢、纠错、枯萎、恢复或旧记忆开关，不能从原生产品能力推断这些操作已存在于网页。

### 探索菜单与文字列表

菜单按钮带可展开状态；选项包括回到水边、看月亮、寻找记忆花、减弱动态和录像。所有按钮最小高度（44px），键盘可见焦点为灰玫瑰轮廓（2px，外移3px）。寻找记忆花打开可滚动列表，条目呈标题与日期，使用轻分隔线；打开时聚焦返回按钮，返回后聚焦菜单按钮。网页有标签及状态公告，但本轮没有完成整体可访问性认证或计算对比度核验。

### 三个路径入口

“石岸 / 往深处 / 沿着水边”推进镜头后显示“小路还会继续。下一处花园尚未开放，先在水边走走。”，并提供回到水边按钮。三个入口目前共用这一未开放状态，不是三个已完成地点。

### 减弱动态

初始跟随系统 `prefers-reduced-motion`，菜单也可手动切换；之后系统设置变化仍会同步。减弱动态时镜头直接定位，蝴蝶使用静止帧，花心保持稳定微光，水纹、粒子、花瓣与叶枝摆动停止；记忆卡片直接可读。`body[data-reduced="true"] #memory` 同时停止 CSS rise，系统媒体规则也关闭 CSS 动画。常态下不持续请求新帧，交互或录制等需要更新时才渲染；静止截图本身不能证明动态已停止。

### 加载、失败与录像

图片未解码前显示“水畔正在醒来…”，失败时出现重试按钮。录像按钮录制实时 Canvas，镜头路线由脚本驱动，标题和记忆文字在录制画布上重绘；录像里的控件呈现不等同于实际 DOM 样式。它不是静态图拼接，也不是设备屏幕或手指操作录屏；实际 UI 以网页和截图为准。触碰画面、Escape 或切换后台可中断录制。字体加载完成后才开始录制；不支持录制时给出文字说明。

## Do's and Don'ts

### Do:

- **Do** 保留单地点连续水岸，让画面先于菜单和卡片被看见。
- **Do** 把真实记忆入口校准到中景花心，并让命中坐标与渲染坐标共用变换。
- **Do** 保留本地字体与 OFL 文件，明确 Camellia 是 Noto Serif SC 的别名。
- **Do** 同时尊重系统与网页减弱动态状态，保留直接可读的记忆和键盘替代入口。
- **Do** 明示匿名示例、未开放地点和原型验收边界。

### Don't:

- **Don't** 在花海上重复叠单花或灌木素材来充当画中的记忆花。
- **Don't** 打开记忆时压暗整幅背景，或把月光改成阴森夜景。
- **Don't** 把母画、录像或单测当作用户批准的 UI comp、真机测试或桌面视觉验收。
- **Don't** 把一张画里的全部装饰花计为已接入的记忆，或用一个 slot 叠放多条 ID。
- **Don't** 把本文件推广为 App 全局设计、更改真实数据权限或发布授权。
