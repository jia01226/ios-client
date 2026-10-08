# 月光宝盒：生产插画与选定设计

用户最终确认：粉色绢面水波纹、贝母细边、椭圆弧形盒身，正面摆放；拉手为五颗珍珠，去掉飘带。页面不显示“月光宝盒”中文，只留细长英文 keepsakes。保留日记／抽屉切换。新增中层放与“我们”共用的便利贴，上层放卷轴信，最下层始终锁着。柜体固定，上中两层分别拖动，曲面遮罩遮住尚未拉出的部分。参考图为设计稿，不是原生截图。

使用内置 imagegen 生成，PNG 保留透明通道；无 SceneKit 灯光。所有运行时色值在 `KeApp/Theme/KeepsakeTheme.swift`。缩小动态效果时保留开关状态和按钮，不播放拉动、卷轴展开动画。

## KeepsakeCabinet

文件：`KeApp/Assets.xcassets/KeepsakeCabinet.imageset/artwork.png`

最初两层柜体提示词（随后按下方编辑提示增加中层）：

```text
Use case: background-extraction / compositing. Input is APPROVED hybrid jewelry-box UI concept. Create the production fixed CABINET LAYER only, isolated on genuine transparent alpha, square1024x1024. Exactly the oval rose-pink MOIRÉ SILK jewelry box from the reference, fine flowing silk ripples, narrow mother-of-pearl inlay top border, subtle champagne edges, tiny feet, TWO drawer levels. Same romantic quiet realistic tangible craftsmanship, visibly pink. Camera straight in front and slightly above (around15deg) so oval top visible, symmetry left/right, no sideward rotation. Entirecabinet in canvas with alpha margins, bounding box approx x60–964,y180–880. FIXED TOP CLOSED. LOWER drawer CLOSED with centered tiny mother-of-pearl keyhole, like reference. UPPER DRAWER COMPLETELY REMOVED: one empty dark dusty-rose velvet cavity directly under top rim, no drawer face, no handle, no tray, no contents. Opening broad frontal rectangular/soft-curved aperture approx x110–914,y460–640. Need no material white-out: pink silk midtones, deeper rose shadows, restrained cream nacre highlights. The only object is fixed cabinet including fixedtop, sidewalls, lowerlockedface and feet. No text, no letters, no UI, no background, no floor. Minimal faded-alpha shadow. This layer will stay stationary while a separate upper drawer is animated over its opening.
```

三层正面柜体编辑提示词：

```text
Use case: production asset edit. Edit the exact FRONT VIEW pink oval jewelry cabinet in reference. Increase it to THREE drawer levels by adding one middle drawer bay. Output the FIXED CABINET BODY ONLY, both TOP and MIDDLE movable trays completely removed; bottom drawer closed with its existing tiny centered keyhole. Keep entire pink moiré body, fine mother-of-pearl border, champagne fine edging, shallow oval top and feet, same straight frontal centered symmetric camera slightly above just enough to see top. NO side perspective and no sideways rotation. It's an elegant French pearl-pink cabinet, not felt or plastic, authentic visibly pink. Exactly three levels: top empty dusty-rose velvet cavity, thin fixed divider rim, middle empty dusty-rose velvet cavity, thin fixed divider rim, bottom CLOSED locked pink moiré face. No handles or ribbons on empty openings, no contents, no pearls floating in openings. All private bottomcontents hidden. IMPORTANT geometry for animated removable sprites: on a PORTRAIT1024x1536 canvas, entire cabinet approximately x60..964, y220..1310; shallow ovaltop y220..520; TOP opening front roughly y490..780; fixed divider at y790; MIDDLE opening roughly y810..1060; fixeddivider y1080; BOTTOM lockedface y1100..1260; littlefeetbelow. Straight horizontal edges gently convex from ovalshape, left-right symmetry, topopening andmiddleopening SAME width and height so same movable tray sprite can be used twice. Preserve material and illumination of reference; natural light from upperleft. Isolated on genuine transparent alpha, no background, no ground plane, no glowy fog rectangle, no text, no UI, no scene. Layer is fixed while two independently animated front trays overlay the two open cavities.
```

## KeepsakeScroll

文件：`KeApp/Assets.xcassets/KeepsakeScroll.imageset/artwork.png`

提示词：

```text
Use case: product-mockup. Production UI object cutout, genuine transparent alpha, landscape1536x1024. ONE horizontal European parchment roll matching scrolls in reference, clean creamy vellum with realistic fibers rolled around aged medium walnut spindles, turned wood finials visible left and right. A dusty-pink fine SILK RIBBON gently ties the middle, small bow. No wax seal (separate asset overlays for a sealed item). No lettering, no faux text, no symbols. Entire roll uncropped acrossmostcanvaswidth with roomy alpha margins above and below. Front slightly above view, exactstraight horizontalaxis. A tactile refined French keepsake, realistic illustration rather than vector. Pink muted, paper warm cream, woodwarmsoftwalnutnotorangegold. Softstudio highlights and minimalshadowfadingtoalpha. No box, no UI, no background.
```

## KeepsakeWax

最终蜡封选择 A：粉色蜡封、香槟金月牙、粉色丝带（2026-10-08 用户确认）。在原始粉色插画上仅改月牙；未采用全金版本。珠光白盒身作为对照试稿，最终仍选择粉色盒身。

文件：`KeApp/Assets.xcassets/KeepsakeWax.imageset/artwork.png`

提示词：

```text
Use case: precise-object-edit. Edit this exact wax seal cutout. Keep the wax disk and both silk ribbon tails original dusty PINK with all their exact shape, texture, color and proportions preserved. Change ONLY THE RAISED CRESCENT MOON at center to an extremely fine low-saturation CHAMPAGNE GOLD metallic wax/gilded inlay, delicate soft warm gold, not yellow, no excessive sparkle. The irregular rim stays pink, the center background stays pink; only the moon is gold. Preserve lighting and original geometry exactly. True transparent alpha background around complete object; no text, no labels, no scene. One isolated production-quality seal, uncropped, same composition.
```

## KeepsakePaper

文件：`KeApp/Assets.xcassets/KeepsakePaper.imageset/artwork.png`

提示词：

```text
Use case: product-mockup. A completely blank VERTICAL parchment SHEET texture for a native readable letter,portrait1024x1536,genuine transparentalpha around edges. High quality creamy warm vellum, elegant paper fiber details and barely uneven edges, subtle pinkishwarm lighting matching the providedpinkjewelrybox style. Paperfillsimage fromx35to989,y35to1501 withfullsheetvisible. NO RODS, no ribbon, no seals, NO TEXT OR LETTERING, no scratches resembling text, no dirtybrownstains. Main centeralmostuniformwarmcreamwithquiet organicfibersso darknativeChinese textisreadable. Fine edge lightlycurledinplaces, butthecenterliesflat. This will stretch verticallyas letterunrolls,with separatelygeneratedwoodenrodsaboveandbelow. Onlypaperontransparentbackground,no table,noscene.
```

## KeepsakeRod

文件：`KeApp/Assets.xcassets/KeepsakeRod.imageset/artwork.png`

提示词：

```text
Use case: product-mockup. Production iOS scroll roller cutout,landscape1536x1024,true transparentalpha. One elegant horizontal wooden spindle/bar for a parchment scroll, front view, straight horizontal, carefully turnedmediumwalnutfinials at bothendsandonecreamvellumroll wrappedaroundcentralshaft. Fullrod roughlyx80–1456,y430–590, centered, no tilting. HighdetailbeautifulsmallFrenchletterobject, neutralwarmlight,finewoodgrain, narrow champagne collars butprimarilywood. Whole rod andbothfinialsvisible.No unrolledsheet, no hangingpaper,noribbon,noseal,no text,noUI,nobackground. It willbeusedasTOP andBOTTOM roller ofverticalunrollingletter.
```

## KeepsakeUpperDrawer

文件：`KeApp/Assets.xcassets/KeepsakeUpperDrawer.imageset/artwork.png`

原始分层提示词（随后按下方编辑提示改为五颗珍珠）：

```text
Use case: compositing / background-extraction. Reference1 is the FIXED cabinet body with its upper drawer removed. Reference2 is the approved complete jewelry box concept. Create ONLY the removable UPPER DRAWER as a separate transparent-alpha production sprite matching reference1 perfectly. Do not redraw the cabinet or lower drawer or lid. Real oval-front French pink moiré-silk tray, mother-of-pearl narrow edge, pearl-and-short-pink-satin-ribbon pull CENTERED on its front, NO LOCK. Same visibly warm rose-pink silk ripples, same scale of nacre and tinychampagneborder as cabinet. Camera directly straight front and slightly above EXACTLY like reference1, symmetrical left/right. Draw a shallow tray fully extracted from cabinet, so its dusty-rose velvet inside floor and shallow sidewalls are seen BEHIND the bowed silk front panel. EMPTY inside, no scrolls or other contents (app will place them). Entiretray isolated, no back cabinetry, no lower level, no top lid, no shadow rectangle, no text, no screen. Landscape1536x1024. Trayfront occupies x95–1440,y500–865; rear trayedge aroundy240 andsidewallsconnectrear tofront. The FRONT FACE is broad and low with smoothly bowed top and bottom edges, matching aperture of reference1. Upper rim on front thinmother-of-pearl, pearl/ribbon pull centered. Fits into cavity when translated upwards behind the top rim, will extend toward viewer when animated. Tangible elegant fine fabric, faint silkshine, softneutralstudio lighting, almost no outside shadow. True transparency around every edge. Important there is only ONE removable tray, not a second box or a whole cabinet.
```

最终拉手编辑提示词：

```text
Use case: precise-object-edit. Edit FIRST image, a production transparent-alpha standalone pink moiré silk removable upper drawer. SECOND image is the approved app comparison; use the pink cabinet's FIVE PEARL HANDLE as the handle reference, nothing else. Change ONLY the handle on the front of first image: COMPLETELY REMOVE its hanging pink ribbon and the single large pearl. Replace with an elegant slightly curved cluster/row of FIVE ivory pearls, central pearl a little larger, two on each side gradually smaller, tiny discreet champagne mounting, like the center pink cabinet in reference2. The five pearls together should occupy about x650–890 at original1536wide, centered around y610; no ribbon, no bow, no trailing textile, no dangling chains. Restore pink moiré fabric continuously behind where ribbon was removed. KEEP EVERYTHING ELSE EXACTLY THE SAME: camera front slightly above, transparent margins, drawer silhouette, dimensions, upper empty interior, nacre edges, colors, lighting, whole object placement, no scrolls inserted. Do NOT draw the cabinet, lower drawer, top, UI, floor or background. Only isolated removable upper tray. Genuine transparent alpha, same1536x1024landscape composition, no opaque backdrop and no extra glowy rectangle around object. This exact image goes into an animated layered iOS illustration, so maintain pixel alignment and geometry.
```
