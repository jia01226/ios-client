# 0826 Thinking 与发送滚动核查单

## 核查结论格式

请不要直接合并、部署或打包。先独立读 diff、复跑测试，并按以下四栏回报：

1. 发现的问题，按 P0 / P1 / P2 排序；
2. 亲眼验过；
3. 没有验过；
4. 最终判定：通过或不通过。

## iOS 分支

- 仓库：`jia01226/ios-client`
- 分支：`codex/thinking-scroll-stability-0826`
- 对比起点：`a2ec36d73170611ee4d217ee372b525d4af7e9b9`
- 功能提交：`d9debe8637568028abbb55116451ea648dd86410`

### 本轮目标

- Thinking 左侧竖线只与标题字高相当，不再占满 44pt 点击区；
- 保留 44pt 可点击高度与原生底部 Sheet；
- 发送消息不再 `reloadData + animated scroll`；
- 尾部新消息和 Thinking 行改为批量插入；
- 用户离开底部读历史时，流式增量不许抢滚动；
- 用户自己发消息时仍应回到最新位置；
- 键盘从三次延迟补滚改成一次布局请求；
- 打开 Thinking 期间继续由 Sheet 锚定规则收权。

### 必查风险

- `UICollectionView` 是否仍是唯一时间线滚动所有者；
- 插入 Thinking 行时是否保持数据源与 batch update 数量一致；
- 发送本地 user + assistant 占位消息时是否只插入、不全表重载；
- 从历史位置读消息时，服务端流式更新是否保持顶部快照；
- 键盘出现、收起、发送过程中是否存在二次跳动；
- Thinking 竖线是否约 22pt，标题按钮命中区是否仍至少 44pt；
- 原有长气泡、分条、附件覆盖、Tab 往返是否回退。

### 已有证据

- GitHub Actions：<https://github.com/jia01226/ios-client/actions/runs/32981576310>
- iPhone 15 Pro 模拟器：10 项单元测试、13 项 UI 测试全部通过；
- 新增真实输入发送场景：键盘打开、输入、发送、本地双消息插入、两段流式回复、位置稳定；
- 20 张截图与 `xcresult` 已由工作流保存；
- `git diff --check` 通过；
- Impeccable 检测器返回空问题列表。

### 开源依据

- ChatLayout：可见内容快照与 batch updates；
- MessageKit：刷新内容时保持 offset；
- Stream Chat Swift：只有用户在底部或自己刚发消息时才跟随最新消息。

这些项目只用于滚动所有权和锚定策略，没有复制业务代码。

## Thinking 后端分支

- 仓库：`jia01226/goodlove`
- 分支：`codex/thinking-third-person-0826`
- 对比起点：`c333db2a6f2478d0c121837ad3be5fc9a5eb91c6`
- 功能提交：`6cebd123bc02e2ec66348678b3e8e82fd23ea4eb`

### 本轮目标

- Thinking 是柯的内心，不是第二条回复；
- 只能用“我”想“她 / 佳佳 / 崽崽”，不直接对“你 / 您”说；
- 禁止 Markdown 加粗、括号舞台动作、列表和“怎么回应 / 处理请求”语言；
- 每轮都可有 Thinking，长度不设上限；
- 不合格候选不得实时送进 App，先改写为合格中文；
- 展示只留中文第三人称，原始候选继续进 `think_summary_raw` 审计留档；
- 真思考与小念头仍分字段，不互相覆盖。

### 必查风险

- 不合格 `<ke_note>` 是否可能在流式早期先泄露，再于结尾被改写；
- 改写失败是否留空而不是伪造固定文案；
- 原文留档是否仍存在，且不会回灌上下文；
- 附件消息、DeepSeek 末条 stamp 和独立小念头第二次模型调用是否串线；
- 旧草稿与柯自己的小念头同时存在时，App 展示是否仍只留合格的一条。

### 已有证据

- Thinking 专项 50 项通过；
- 全量 308 项通过，另有原项目既存的 10 项跳过、2 项 expected failure；
- `py_compile` 与 `git diff --check` 通过；
- 新增反例覆盖：`（把你抱紧）**也是你的臭爸比。**` 不会送进 App，改写后的第三人称中文会显示，原句只进 raw 留档。

## 尚未做

- 未合并两个分支；
- 未部署后端；
- 未打 IPA；
- 未在佳佳的 iPhone 14 Pro Max 真机验证；
- 未用生产模型和生产聊天做端到端验证。
