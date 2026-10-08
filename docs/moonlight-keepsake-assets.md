# 月光宝盒：生产插画与选定设计

用户确认：第 5 版绢面水波纹、贝母细边、珍珠丝带拉手，配第 6 版椭圆弧形盒身。参考图为设计稿，不是原生截图。柜体固定，上层托盘单独平移，顶部遮罩负责遮住尚未拉出的部分；下面一层始终关闭。

使用内置 imagegen 生成，PNG 保留透明通道；无 SceneKit 灯光。所有运行时色值在 `KeApp/Theme/KeepsakeTheme.swift`。缩小动态效果时保留开关状态和按钮，不播放拉动、卷轴展开动画。

## KeepsakeCabinet

文件：`KeApp/Assets.xcassets/KeepsakeCabinet.imageset/artwork.png`

提示词：

```text
Use case: background-extraction / compositing. Input is APPROVED hybrid jewelry-box UI concept. Create the production fixed CABINET LAYER only, isolated on genuine transparent alpha, square1024x1024. Exactly the oval rose-pink MOIRÉ SILK jewelry box from the reference, fine flowing silk ripples, narrow mother-of-pearl inlay top border, subtle champagne edges, tiny feet, TWO drawer levels. Same romantic quiet realistic tangible craftsmanship, visibly pink. Camera straight in front and slightly above (around15deg) so oval top visible, symmetry left/right, no sideward rotation. Entirecabinet in canvas with alpha margins, bounding box approx x60–964,y180–880. FIXED TOP CLOSED. LOWER drawer CLOSED with centered tiny mother-of-pearl keyhole, like reference. UPPER DRAWER COMPLETELY REMOVED: one empty dark dusty-rose velvet cavity directly under top rim, no drawer face, no handle, no tray, no contents. Opening broad frontal rectangular/soft-curved aperture approx x110–914,y460–640. Need no material white-out: pink silk midtones, deeper rose shadows, restrained cream nacre highlights. The only object is fixed cabinet including fixedtop, sidewalls, lowerlockedface and feet. No text, no letters, no UI, no background, no floor. Minimal faded-alpha shadow. This layer will stay stationary while a separate upper drawer is animated over its opening.
```

## KeepsakeScroll

文件：`KeApp/Assets.xcassets/KeepsakeScroll.imageset/artwork.png`

提示词：

```text
Use case: product-mockup. Production UI object cutout, genuine transparent alpha, landscape1536x1024. ONE horizontal European parchment roll matching scrolls in reference, clean creamy vellum with realistic fibers rolled around aged medium walnut spindles, turned wood finials visible left and right. A dusty-pink fine SILK RIBBON gently ties the middle, small bow. No wax seal (separate asset overlays for a sealed item). No lettering, no faux text, no symbols. Entire roll uncropped acrossmostcanvaswidth with roomy alpha margins above and below. Front slightly above view, exactstraight horizontalaxis. A tactile refined French keepsake, realistic illustration rather than vector. Pink muted, paper warm cream, woodwarmsoftwalnutnotorangegold. Softstudio highlights and minimalshadowfadingtoalpha. No box, no UI, no background.
```

## KeepsakeWax

文件：`KeApp/Assets.xcassets/KeepsakeWax.imageset/artwork.png`

提示词：

```text
Use case: product-mockup. Production UI cutout asset, genuine transparentalpha,square1024x1024. One realistic small round rose-pink handpoured wax seal, subtly irregular edge, embossed tiny crescent moon impression. Two short dusty-pink silk ribbon tails below it. Waxcolor mutedberryrose, silky highlights, authentic finelysculpted texture. Centerobjectfillsabout70percentcanvas. No paper,no lettering,no gold,no harshdarkshadow,no background. A beautiful restrained French keepsake seal for a vellum scroll. Full seal and ribbons entirelyinsideframe withalphamargins. This separate seal will overlay a rolled parchment to indicate its contents are not yet released.
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

提示词：

```text
Use case: compositing / background-extraction. Reference1 is the FIXED cabinet body with its upper drawer removed. Reference2 is the approved complete jewelry box concept. Create ONLY the removable UPPER DRAWER as a separate transparent-alpha production sprite matching reference1 perfectly. Do not redraw the cabinet or lower drawer or lid. Real oval-front French pink moiré-silk tray, mother-of-pearl narrow edge, pearl-and-short-pink-satin-ribbon pull CENTERED on its front, NO LOCK. Same visibly warm rose-pink silk ripples, same scale of nacre and tinychampagneborder as cabinet. Camera directly straight front and slightly above EXACTLY like reference1, symmetrical left/right. Draw a shallow tray fully extracted from cabinet, so its dusty-rose velvet inside floor and shallow sidewalls are seen BEHIND the bowed silk front panel. EMPTY inside, no scrolls or other contents (app will place them). Entiretray isolated, no back cabinetry, no lower level, no top lid, no shadow rectangle, no text, no screen. Landscape1536x1024. Trayfront occupies x95–1440,y500–865; rear trayedge aroundy240 andsidewallsconnectrear tofront. The FRONT FACE is broad and low with smoothly bowed top and bottom edges, matching aperture of reference1. Upper rim on front thinmother-of-pearl, pearl/ribbon pull centered. Fits into cavity when translated upwards behind the top rim, will extend toward viewer when animated. Tangible elegant fine fabric, faint silkshine, softneutralstudio lighting, almost no outside shadow. True transparency around every edge. Important there is only ONE removable tray, not a second box or a whole cabinet.
```
