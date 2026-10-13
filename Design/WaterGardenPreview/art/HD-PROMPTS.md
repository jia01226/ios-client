# 高清修订素材与处理记录

2026-10-13。本轮保留原3:2全景构图，三层先经内置 image_gen 细节修复，再使用 Real-ESRGAN `realesrgan-x4plus` 做4倍神经网络超分。最终6144×4096，不宣称原生生成6K或找回真实细节。

工具来源：[Real-ESRGAN 官方](https://github.com/xinntao/Real-ESRGAN)，使用官方 v0.2.5.0 macOS 便携包，临时目录运行；没有关闭 Gatekeeper、修改系统安全配置或安装全局插件。模型和二进制不入仓库。

命令：

```sh
./realesrgan-ncnn-vulkan -i INPUT.png -o OUTPUT-4x.png -n realesrgan-x4plus -s 4 -t 256 -j 1:1:1
python Design/WaterGardenPreview/scripts/prepare-hd.py OUTPUT_DIRECTORY
```

WebP RGB质量94，alpha无损；预览质量86。没有额外锐化/补噪点。脚本中1:1裁切只用于检查，没有再缩放。检查了中景花瓣、石缘与近景叶片，未见明显拼块缝和光晕；AI推断可能改变细小纹理，画风是否喜欢仍由用户判断。

## 三层生成提示词

### far

参考目标为上一版同名PNG，生成源保存在 art/hd-source/far.png。

Use case: precise-object-edit. Input image is the exact edit target. Re-render ONLY to restore crisp, richly resolved hand-painted fine detail for a high-density mobile 2.5D game. Keep the existing 3:2 panoramic composition, all object positions and silhouettes, the exact shoreline and flower-center coordinates, original quiet Morandi lavender-blue/ivory/dusty pink palette, same upper-right moonlight. Request maximum resolution, ideally 6144x4096. The image will be zoomed on a 3x phone screen. Resolve petal overlaps, flower stamens, thin leaf edges and leaf veins, clean deliberate gouache/oil brushstrokes and limestone detail. Soft lighting is allowed, defocused subject edges are not. No global mist veil, no Gaussian blur, no bokeh, no sharpening halos, no artificial scratch/grain pattern. No extra flowers or buildings, no rearrangement, no UI or text. This is restoration of the SAME image, not a new scene.
Preserve all sky/cloud/mountain/water positions. Keep atmospheric depth in distant mountains but use resolved edges and delicate brushwork. No foreground vegetation.

### midground

参考目标为上一版同名PNG，生成源保存在 art/hd-source/midground.png。

Use case: precise-object-edit. Input image is the exact edit target. Re-render ONLY to restore crisp, richly resolved hand-painted fine detail for a high-density mobile 2.5D game. Keep the existing 3:2 panoramic composition, all object positions and silhouettes, the exact shoreline and flower-center coordinates, original quiet Morandi lavender-blue/ivory/dusty pink palette, same upper-right moonlight. Request maximum resolution, ideally 6144x4096. The image will be zoomed on a 3x phone screen. Resolve petal overlaps, flower stamens, thin leaf edges and leaf veins, clean deliberate gouache/oil brushstrokes and limestone detail. Soft lighting is allowed, defocused subject edges are not. No global mist veil, no Gaussian blur, no bokeh, no sharpening halos, no artificial scratch/grain pattern. No extra flowers or buildings, no rearrangement, no UI or text. This is restoration of the SAME image, not a new scene.
Preserve the TRUE TRANSPARENT sky area and EVERY visible flower exactly in place; do not add a sky or mountains. Flower petals and foliage must have crisp fine edges while keeping painted texture. The river, shoreline stones and entire painted flower sea are one inseparable midground layer.

### foreground

参考目标为上一版同名PNG，生成源保存在 art/hd-source/foreground.png。

Use case: precise-object-edit. Input image is the exact edit target. Re-render ONLY to restore crisp, richly resolved hand-painted fine detail for a high-density mobile 2.5D game. Keep the existing 3:2 panoramic composition, all object positions and silhouettes, the exact shoreline and flower-center coordinates, original quiet Morandi lavender-blue/ivory/dusty pink palette, same upper-right moonlight. Request maximum resolution, ideally 6144x4096. The image will be zoomed on a 3x phone screen. Resolve petal overlaps, flower stamens, thin leaf edges and leaf veins, clean deliberate gouache/oil brushstrokes and limestone detail. Soft lighting is allowed, defocused subject edges are not. No global mist veil, no Gaussian blur, no bokeh, no sharpening halos, no artificial scratch/grain pattern. No extra flowers or buildings, no rearrangement, no UI or text. This is restoration of the SAME image, not a new scene.
Preserve true transparent canvas and the exact top-left and bottom-right camellia branches. No flowers. Keep the central area completely transparent; edges of individual leaves finely resolved, no cloudy halos.
