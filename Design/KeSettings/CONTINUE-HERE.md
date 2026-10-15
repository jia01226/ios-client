# 接着做：柯 · 月隐与长窗

当前分支 `codex/settings-drawer`。本次按用户新需求把聊天页、四页设置、整轮钉住、挑选带走、换窗确认和旧窗回看串成单文件原型。

1. 当前入口 `Design/KeSettings/index.html`，内联 CSS/JS/字体/图片，不依赖后端。默认象牙，中文思源宋体 250 字重，装饰英文 Pinyon Script。
2. 用户要逐个点状态，顶部演示目录提供 16 个入口；所有交互数据是示例、刷新重置。README 中有行为与验证说明。
3. `DESIGN.md` 记录当前设计。`DESIGN-LEGACY.md`、`moon-drawer-original.html` 和原 spec/app.js/style.css/motion.js 保留上一版八页抽屉，不能混作当前网页的真源。
4. 新增 `tests/single-file.test.cjs` 六项测试，原测试七项保留。修改主页面后需执行新测试，浏览器刷新验证对应状态。
5. 当前 HTML 内已包含字体与图片，不要重新加外部字体/CDN/fetch。页面可以独立复制给用户。新加中文文案如果字体子集不包含，会回退系统宋体；需要完整视觉一致时更新子集。
6. 仍待用户视觉反馈和 iPhone Safari 真机触摸检查；不是原生验收。当前未合并、未打 App 包、未发布、未碰服务器。

原始设计分支基线记录：`claude/swipe-103` 的 `f0335fb526d7fd42df9db8411755e6cd0554d66d`；首次设置交接为 `7602c46`，随后补文档为 `77ef6e1`。
