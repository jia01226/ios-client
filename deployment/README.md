# Build 73 交付记录

用户在本轮明确授权直接收尾并更新原网页安装入口，取代此前只交 Claude 审核的流程。

## 经期接口

`period-end-73.patch` 是从 VPS 实际运行的 test1 副本制作的窄补丁，不是从 GitHub 过时的后端副本覆盖上线。部署于 2026-10-07 05:41 UTC，仅改 `/root/.goodlove-test1/runtime/db.py`、`routes/daily.py`、`context.py`。未修改原版线、聊天、记忆或提醒行为。

- `POST /api/periods/end` 用已有 id 更新 `end_date`，验证日期、已有记录和重复请求；重复同日结束幂等，不删除/重建原记录。
- `GET /api/periods` 返回 `end_date`（未记录为 null）；新建开始记录的重试不重复插入，也不擦掉结束日期。
- 数据库初始化兼容旧表加列；上线前发现真实 test1 表已有该列，只是旧读取和写入函数尚未接上。
- 上下文优先读取实际结束日期；本轮没有改变用药提醒或剂量。
- 服务上线前检查三文件 SHA 与备份一致、没有正在生成的聊天任务；以 Gunicorn HUP 平滑加载。
- 备份：`/root/ke-deploy-backups/period73-20261007T054111Z/`，含三份原文件和 SQLite 一致性备份。
- 回滚代码时仅还原三文件并 HUP；不要用整库备份覆盖后来产生的聊天和用户记录。保留新增列无害。

测试：服务器 Python 3.10 / Flask，在临时 SQLite 库运行 `test_period_end.py`，3 项通过，覆盖迁移两次、保留原 id/备注、重复开始/结束、删除、非法日期和 id、缺失记录、上下文结束状态。上线后只读返回和无效空请求（400）验证通过，没有向真实账号添加经期样例。

山屋实际返回由本次 iOS 的 `RemoteHut` 解码器读取成功；只读核验，没有发送测试信或改动记忆。

## 网页安装

`deploy_ota.py <暂存目录>` 在 VPS 执行。暂存目录需 `KeApp.ipa`、`index.html`、`manifest.plist` 和 `expected.json`。expected 中含 `ipa_sha256` 和线上原三文件的 `before` 哈希。部署拒绝同号/降级及并行修改；先备份，再发布版本固定的 IPA/manifest，最后切换首页。不会重写 Nginx 配置。

73 的 IPA SHA256：`32f0eed469c41759b3ada111f2838c01effd39ff5013df524aaa6ba45c0bb248`。

正式上架完成于 2026-10-07 05:48 UTC。OTA 回滚备份：`/root/ota-deploy-backups/20261007T054800Z-build73/`。公网下载完整 `KeApp-73.ipa` 的 SHA256 与上面的构建产物一致，首页、安装按钮及 `manifest-73.plist` 均为73；默认 manifest 也已更新。

正式 IPA 来自提交 `9664f8a`、[Build iOS run 37576556340](https://github.com/jia01226/ios-client/actions/runs/37576556340)。后续提交只补测试专用匿名数据（`#if DEBUG`）、UI测试、部署脚本与文档，不改变 Release 业务代码。

第一次模拟器检查 [37576554341](https://github.com/jia01226/ios-client/actions/runs/37576554341) 通过74项单元测试和1套UI流程；原有抽屉样例缺失导致截图显示重试，已确认线上真实抽屉可被现有Swift模型解析，并补齐匿名响应后再次核验。

补充核验 [37578110465](https://github.com/jia01226/ios-client/actions/runs/37578110465) 于06:04 UTC成功：74单元测试+1套UI，经期开始/结束确认、抽屉内容断言和24张截图全部完成。
