# 月光改版素材与生成记录

使用内置 imagegen；以下透明 PNG 已复制进工程，并由原生布局叠加可读文字和交互。设计图不作为整页背景。日记日期、翻页、抽屉拉动都由原生代码实现。

## UsMoonBloom

工程文件：`KeApp/Assets.xcassets/UsMoonBloom.imageset/artwork.png`

最终提示词：

Use case: compositing. Create a production iOS UI illustration asset isolated on a GENUINELY TRANSPARENT alpha background. No whole UI, no text, no typography, no frame, no shadow rectangle, no watermark. Same luminous warm blush and delicate pearl-white realism as reference, airy fine details, beautiful restrained moonlight, not gold or dark. Isolated object occupies most of canvas with transparent padding, high resolution clean edges.Extract/recreate only the reference's upper-right decoration: one large translucent luminous pale blush camellia blossom with one bud and a few pale warm-grey leaves in front of a very faint milky moon. Front blossom on right, faint moon disc behind left. Same elegant light, no page background. No floating glitter or petals. Square composition asset; entire object visible so app can crop edge. The transparency surrounds the pale moon and flower silhouette.

## KeMoonCamellia

工程文件：`KeApp/Assets.xcassets/KeMoonCamellia.imageset/artwork.png`

最终提示词：

Use case: compositing. Create a production iOS UI illustration asset isolated on a GENUINELY TRANSPARENT alpha background. No whole UI, no text, no typography, no frame, no shadow rectangle, no watermark. Same luminous warm blush and delicate pearl-white realism as reference, airy fine details, beautiful restrained moonlight, not gold or dark. Isolated object occupies most of canvas with transparent padding, high resolution clean edges.Extract/recreate only the reference's upper-right moon with small camellia: one full pearly pink-white luminous moon disk, subtle soft texture and bright crescent edge, one small pale blush camellia flower and pale muted leaves at lower-right edge. Entire moon visible, square canvas. The flower is only 20% moon diameter. Soft warmth no harsh lunar craters, bright but muted. No sun rays. Transparent around the celestial ornament.

## MoonDiaryCover

工程文件：`KeApp/Assets.xcassets/MoonDiaryCover.imageset/artwork.png`

最终提示词：

Use case: background-extraction. Input is a reference UI page. Create a single isolated production asset of ONLY its closed pearly ivory blush diary with the crescent arc and small camellia inlay, matching that unique cover design exactly. No page UI, no background, no date rail, no screen, no other props. Book FRONT VIEW straight-on, no slant, fully visible entire outline with narrow transparent margins about 3%, narrow cream page block at bottom and rose ribbon below. Material smooth softly luminous satin-touch ivory blush, subtle fine surface, no felt, no stitches. Elegant pearl moon arc on the upper cover sweeping into ONE delicate camellia relief, lower half left empty for native typography. REMOVE ALL TEXT and numbers from cover; native app will overlay text. Avoid ordinary rectangular decorative border, gold decorations, excessive flowers. Preserve crescent and flower identity from reference. Real transparent alpha background, portrait roughly 3:4.

## MoonTarotPair

工程文件：`KeApp/Assets.xcassets/MoonTarotPair.imageset/artwork.png`

最终提示词：

Use case: compositing. Create a production iOS UI illustration asset isolated on a GENUINELY TRANSPARENT alpha background. No whole UI, no text, no typography, no frame, no shadow rectangle, no watermark. Same luminous warm blush and delicate pearl-white realism as reference, airy fine details, beautiful restrained moonlight, not gold or dark. Isolated object occupies most of canvas with transparent padding, high resolution clean edges.Only the two overlapping elegant tarot card backs in reference, no entire screen. Two thin pale blush cards at slight opposing angles, pearl-ivory paper, very fine muted rose borders, each with a luminous small crescent moon and pink camellia motif centered; almost no extra stars. Crisp readable shapes, restrained illumination. Portrait 3:4 composition, isolated transparent background. No titles or labels.

## MoonGomokuBoard

工程文件：`KeApp/Assets.xcassets/MoonGomokuBoard.imageset/artwork.png`

最终提示词：

Use case: compositing. Create a production iOS UI illustration asset isolated on a GENUINELY TRANSPARENT alpha background. No whole UI, no text, no typography, no frame, no shadow rectangle, no watermark. Same luminous warm blush and delicate pearl-white realism as reference, airy fine details, beautiful restrained moonlight, not gold or dark. Isolated object occupies most of canvas with transparent padding, high resolution clean edges.Only the minimal diamond-oriented square gobang board shown lower left in reference, no app UI. Pale pearl-ivory board with fine muted rose grid and border, very shallow 3D angle. Eight smooth small stones in a loose little cluster, dusty pink and warm grey alternating. Grid subtle but visible. Very fine moonlit edge, no petals, no blossom, no extra objects. Square canvas transparent outside the board.

## 日期交互的最新视觉参考

月牙下垂落一束柔和月光，日期沿光排列；不再使用普通白色纸书签。保留 Allura 的细长英文 a day with you，月份和年份可以打开日历。参考生成图为 exec-71a344c3-1a12-42a5-9020-6553bf81cfcb.png；实际画面以模拟器截图为准。

## 最终选定的我们页装饰

内置 image_gen，根据最后确认的第六版设计生成透明素材；已检查透明通道。代码绘制文字和交互，素材仅作装饰。

### UsQuietMoon

保存：`KeApp/Assets.xcassets/UsQuietMoon.imageset/artwork.png`

完整提示词：

```text
Use case: background-extraction / product UI artwork asset. Reference is an approved mobile page. Create ONLY the warm pearly, softly luminous CRESCENT MOON seen in its upper-right, as an isolated reusable UI illustration on a genuinely transparent alpha background. No screenshot, no UI, no text, no numerals, no stars, NO flower. Complete crescent fully inside1024x1024square with breathingroom, floating centered, tipped similarly to reference. Very faint warm ivory-blush, delicate subtle surface like thin porcelain lit from behind, absolutely no harsh lunar craters, no dark unlit disk, no outlined geometric icon. Crescent edge subtly glows but most light soft and quiet, glow must fade to transparent alpha. It will be cropped at top-right of a #FAF3F4 UI. Generate transparent cutout only; do not bake pink opaque square/checkerboard.
```

### UsCamelliaSprig

保存：`KeApp/Assets.xcassets/UsCamelliaSprig.imageset/artwork.png`

完整提示词：

```text
Use case: background-extraction / UI artwork asset. Reference is approved mobile page. Create ONLY the tiny graceful pale pink CAMELLIA BUD ON A STEM with 2gray-sage delicateleaves from its lower-left, fullyisolatedon genuinelytransparentalpha. No screenshot,noUI,noletters,notext,nootherflowers. A slender diagonal stem rising from bottomleft to a partiallyclosed smallpearlescent blushcamellia atuppercenter, same quiet restrained shapeasreference, subtle cream moonlight alongoneedge. Flower pale smallbud, not hugeopenrose/bloom. Include one extremely faint halfmoonhalo behindbud like reference, its light smoothly fades totransparent, no opaque disk.1024square with entireplantuncroppedand roomat edges. Nearlytransparent warm airy rendering suitable for160pointdecoration; noframe,no glitter,noextra petals,nofabric. Background completelytransparent notpink/checkerboard.
```

