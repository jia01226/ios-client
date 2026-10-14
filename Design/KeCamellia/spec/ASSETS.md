# 素材说明

## 两套文件的用途

目录根部的三个 PNG 是定稿网页的原文件。它们不属于 @3x 拆分包：背景是原不透明图，花枝包含花和花苞，蝴蝶是完整图。保留它们用于像素和构图对照。

`assets/` 是原生用的 21 张 @3x PNG。尺寸、真实 alpha 像素数、有效内容边界和用途统一记录在 [layout.json](layout.json) 的 `assets` 中。文件名中的 @3x 指逻辑点尺寸乘三，不表示原图细节无限增大。

| 类别 | 文件 | 说明 |
| --- | --- | --- |
| 背景 | background@3x.png | 透明雾、远景和植物投影层，无花瓣；叠在底色上 |
| 主枝 | stem@3x.png | 主干与浅绿叶；不含六朵花和花苞 |
| 六花 | diary / dream / drawer / tarot / moments / memory@3x.png | 每张仅一朵花，不含叶和枝 |
| 六挂签 | tag-入口ID@3x.png | 空白薄卡、细框、小菱形；不含文字和挂线 |
| 蝶 | wing-left / wing-right / body@3x.png | 各占同一方形注册画布；身体需要使用坐标文件的局部校准 |
| 落瓣 | petal-01 / petal-02 / petal-03@3x.png | 三种独立粉色落瓣 |
| 菱形框 | diamond-frame@3x.png | 透明中心、白框与浅投影；内容缩略图由 App 独立放在框下面 |

## 拆分方法与保真边界

花、枝、背景、蝴蝶和落瓣用内置图像编辑工具，逐张以定稿为参考提取或重建透明层；挂签与菱形框从网页原生几何样式导出。之后统一导出目标 @3x 尺寸，未调用外部图像 API。

生成规格与提示词保存在 [generation-prompts.json](generation-prompts.json)。

生成式拆分不是 PSD 原图分层，花瓣轮廓、叶片细节、枝条接缝存在差异。枝条去掉花苞后，拆分版也会比定稿更简洁。已提供 [layers.html](../layers.html) 供组装比较；正式接入前请确认该差异。需要严格复现定稿时，先用根目录原花枝整图加独立点击区域，后续再换分层图。

挂线由 App 绘制；六枚挂签文字分别来自 `flowers[].label`，不得烘进图片。蝴蝶 body 层不是“自动居中即可”：用 `butterfly.localLayers.body.frame` 对齐到翅根，三层共用同一个父坐标系。

背景图保留透明中心，使用 `background.baseColor` 和 `background.opacity` 合成；不能在黑底查看器里把透明部分误认成黑色背景。

## 导出工具

`tools/export-assets.cjs` 用 Node.js + sharp 做尺寸归一化、原生挂签/框栅格化，并生成坐标清单；不执行图像提取。输入是各层原始 PNG 的本机路径映射，键名与 assets ID 相同。仓库不包含本机绝对路径。已导出的 PNG 可直接使用，无需运行工具。
