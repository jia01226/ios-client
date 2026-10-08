# 抽屉内部与月光牌背素材

## AppIcon · 已选择 01

用户选择六版对比中的 01「月牙托着山茶」，另行生成单幅正式图标。原始文件 `exec-42e9c5bb-1f94-429e-9362-11f805cec3b6.png` 为 1254×1254、不透明；系统 sips 仅按 AppIcon 打包规格缩至 1024×1024，不裁切、不改色，无预制圆角。

工程文件：`KeApp/Assets.xcassets/AppIcon.appiconset/app-icon.png`。

```text
Use case: precise-object-edit. The reference is a 6-icon comparison board. User selected ONLY ICON 01, TOP LEFT: a luminous nacre crescent cradling one small soft pink camellia in its lower opening. Produce the finished standalone iOS APP ICON of ONLY that exact design, preserving its crescent proportions, flower and warm opalescent lighting, subtle dusty rose shadows and pale blush color. Output a perfectly square 1024x1024 opaque RGB-style icon canvas. Completely filled edge to edge with smooth very pale blush pink #F5EEEE-family background. The crescent and camellia float on this background and occupy roughly 75% width and 78% height, centered, with comfortable safe margins. NOT the whole six-design sheet. Remove 01 number, remove all text, remove rounded square tile perimeter, remove outer tile shadow and all margins around the icon. Do NOT draw baked-in rounded corners, no transparent pixels, no white/black frame. iOS will clip the square itself. Only the soft dimensional shadow of the crescent/flower should remain. Fine pearl iridescence rather than frightening crater realism, no added stars, no added gold frame, no extra flowers, no ribbon, no letters. Premium soft luminous pearlescent moonlight pink, cohesive with the selected icon. This is the actual AppIcon1024 production asset, not a mockup.
```

使用 imagegen 内置工具生成；原始 alpha 保留，未用代码重绘或去背。界面中的文字和交互均为原生控件。

## KeepsakeNotesInterior

工程：`KeApp/Assets.xcassets/KeepsakeNotesInterior.imageset/artwork.png`

来源：`exec-ea36d175-f8eb-4717-9bb3-5663115ac614.png`

```text
Use case: precise-object-edit. Reference image is the existing pink pearl drawer asset. Create its OPEN INTERIOR CLOSE-UP sprite for a native iPhone cozy game, so interactive paper notes can be composited INSIDE the drawer. Preserve EXACT warm dusty pink moire silk, mother-of-pearl fine rim, tiny champagne metal edging, FIVE pearl handle beads, same elegant curved front. Change ONLY camera to high straight-on overhead-front view, completely symmetrical, no left/right side angle. Large empty rectangular interior floor should occupy x=12%-88%, y=12%-67% of canvas. This deep visible empty floor is crucial for readable notes. Front facade only occupies bottom 20%, pearl handle at bottom center. Entire tray within canvas with 4% transparent padding, near-square portrait composition. Empty tray, NO paper, NO words, NO props, NO ribbons, NO feet, no cabinet. Absolutely transparent outside object, no colored halo, no backdrop, no opaque shadow rectangle. Premium realistic warm pink same reference, not grey, no blown white. Top-down interior high angle for game object but front pearls visible. Crisp 1536px-class production asset.
```

## MoonTarotBack

工程：`KeApp/Assets.xcassets/MoonTarotBack.imageset/artwork.png`

来源：`exec-6fadb257-b4e7-492e-932e-f1d772e48b42.png`

```text
Use case: precise-object-edit. Reference is the approved moonlight camellia tarot card BACK design with two overlapping tilted cards. Deliver ONE SINGLE upright card back, perfectly straight-on, no perspective, no tilt, no overlapping other card. Same delicate moonlit blush translucent camellia and glowing crescent, pearl-ivory paper, very thin dusty rose ornamental double border, extremely restrained tiny stars. Extract and faithfully recreate the frontmost card's illustration as one high resolution complete card. Aspect card ratio 0.58 width/height, rectangle occupying 95% canvas height and as much width as possible, minimal transparent margin. Actual alpha transparent outside rounded card, NO shadow rectangle, NO backdrop. No title, no lettering, no number. Soft luminosity, lovely pale pink but readable border, not yellow or white blown out. Production asset used in actual card shuffle, card back and deck selector, not mockup.
```
