# OTA 真机安装

本目录保存 Ad Hoc 安装页、manifest 和 Nginx 独立静态目录配置。IPA 不进 Git。

- 安装页与 IPA 必须通过受信任的 HTTPS 提供。
- `.plist` 使用 `text/xml`，`.ipa` 使用 `application/octet-stream`。
- 安装入口只允许手动分享，不在 PWA 首页增加链接。
- 当前包只允许 Apple Developer 后台已登记 UDID 的设备安装。
- 后续替换 IPA 时应保持 Bundle ID `love.jiagude.ke`，并同步更新 build number。

服务器目录为 `/var/www/ke-ota/`。安装地址使用不可猜路径，避免把私人 IPA 暴露在固定 URL 下。
