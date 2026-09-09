# 星云预渲染

在 Mac 上用原来的 `TimeNebulaVolume.fragment` 生成纹理，保留已确认的白金星云外观。
手机只采样纹理、随月面转场做轻微视差；停留时不运行体积积分或持续漂移动画。

从仓库根目录执行

```sh
xcrun swiftc -O KeApp/Features/Us/TimeSpace/TimeNebulaVolume.swift Design/TimeSpaceTools/Bake.swift -o /tmp/loveapp-nebula-bake
/tmp/loveapp-nebula-bake KeApp/Resources/time-nebula-baked.png
```

脚本同时对比两种材质在 645×1275 渲染目标上的 GPU 时间，排除前四帧预热。
这是背景专项，不能作为整页帧率或真机滑动验收。
真机同场景对照测试为 `TimeRenderingPerformanceTests`，不发网络请求。
