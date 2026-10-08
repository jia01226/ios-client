# 便利贴抽屉、塔罗查看与卷轴核对 · Build 81

本分支 `codex/notes-tray-tarot-build81` 接在已交付的 Build 80 上，保留 79 的修复、80 的全屏日记、三层柜和单聊天。佳佳确认第一层纸条必须在抽屉内部；新包仍由 Claude 核对后走网页安装，GPT 不上架。

## 本次变更

- 用户从六版图标中选择 01：月牙托着山茶。单独生成正式图标，导出为 1024×1024、不透明、无预制圆角的 AppIcon，随本包安装。

- 第一层拉开后进入同一只抽屉的近景。佳佳、柯的真实便利贴摆在内底上，纸色区分作者；两张一组，左右翻取更多纸条。空抽屉不生成示例便利贴。
- 点纸条进入全屏纸张：佳佳的可编辑，柯的只读；放回去回到原来的抽屉。新增保存继续用既有 StickyNotesStore、接口和缓存，“我们”页保持同一份内容。
- 补齐已选月光山茶设计的单张牌背。牌堆、洗牌、发牌背面、主题选择都用同一素材；一次性迁移旧选择到月光山茶，之后可以再自行换回。
- 具体塔罗牌面继续读取服务器抽到的原图，不把装饰牌背冒充 78 张牌面。点牌面全屏查看，双指缩放至 4 倍、拖动、双击还原／放大，上一张／下一张浏览已有牌；保留正逆位，不重新抽牌，不向柯发送消息。牌面载入失败可重试。
- 预览传输修正 URLSession httpBodyStream 的读取，隔离便利贴的成功回包能被验证；没有改生产服务器或正式接口。

## 卷轴：仓库链路存在，线上轻装柯待 Claude 确认

只读核对 goodlove 提交 `eb93c820d1ce3bdcc54cdee430de6b7b270f5db6`：

1. `platform/chat_ai.py:353` 的 DRAWER_ACTION_RULE 教柯 save / tease / release，并在 build_system_prompt 中加入；`_drawer_block()` 为模型提供私藏。
2. `platform/routes/chat.py:54` 从 ke_note 提取 drawer_action，`_apply_drawer_actions` 保存或公开；聊天流 `_process_private_note` 调用它并移除隐藏动作。
3. `platform/db.py:4012` 有 add_drawer_item、tease_drawer_item、release_drawer_item。`public_drawer_view` 只返回 released 正文和 teaser 外壳，private 不返回。
4. `GET /api/drawer` 由客户端读取。App 只将已公开的条目画成卷轴，没有另一个需要柯调用的“卷轴接口”。

在本机一次性 SQLite 上运行仓库已有的两项测试，均通过：`test_private_drawer_content_never_enters_public_view`、`test_drawer_can_leave_a_teaser_then_release_without_browser_write_api`。这只验证仓库数据库逻辑，不代表线上写入已验收。

请 Claude 核对当前轻装柯运行进程是否真的使用上述提示与动作处理，数据库是否和 `/ke-test1/api/drawer` 一致；精简开窗须知指向 KONGKONG_DIR 下的文件，本次未读取运行环境，不能确认实际内容。验收应覆盖柯发起保存、返回真实 ID、公开后 GET 返回同条正文、App 刷新出现并可读；口头说“放好了”不算成功。若线上缺连接或有不同协议，由 Claude 修复并安排部署，GPT 未改任何服务器文件或重启服务。

## 验收记录

待当前模拟器流程和审核包完成后填写。不得把生成素材或设计图称为手机实测。

素材与完整生成提示见 [notes-tray-tarot-assets.md](notes-tray-tarot-assets.md)。
