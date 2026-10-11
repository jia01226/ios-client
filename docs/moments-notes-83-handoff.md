# 朋友圈与便利贴 · 83 版候选交接

从已上架 82 版 `codex/foreground-recovery-build82` 的 `d2024e3` 继续，分支 `codex/moments-notes-build83`。交 Claude 核对后上架。本次只改 iOS 仓库，没有 SSH、修改服务器、重启或发布安装页。

## 本次行为

- 「玩」增加朋友圈入口、小红点，页面采用封面、头像、动态流、赞与评论的结构，沿用月光主题的花卉素材和配色。头像为花卉加名字，未假设服务器存在个人头像字段。
- 支持文字、单图、纯图发布；照片复用客户端压缩与受保护上传接口。图片可独立查看，加载失败可重试。
- 只能修改、删除自己的动态与评论。界面和 Store 双层核对作者；柯的内容没有修改入口。删除自己内容需确认。
- 写入失败保留当前草稿；重复点击被阻止。写入已确认但刷新失败时显示「已保存」，避免把刷新故障变成重复发布。
- 「我们」便利贴只展示 `author=ai` 的提醒，移除新增、编辑、删除入口。「知道啦」收起，有「已收起」可放回去，抽屉内同样只读。旧 user 笔记与本机草稿保留在原存储位置，未删除或自动搬家。
- **「知道啦」当前仅保存到本机**，界面明确显示「收起状态暂存本机」；同一线路的「我们」与抽屉即时一致，重启仍保留。没有虚构服务器确认接口。跨设备同步尚未完成。
- 未改聊天、经期、排班、塔罗、棋局、日记、宝盒私密权限或运动权限。

## 已核对的接口

来源：本地只读后端 `platform/routes/moments.py`、`platform/db.py`、`platform/routes/media.py`，及现有客户端 `APIClient.swift`。GitHub 最新《工单-给codex.md》截至本次读取仍停在 82 版上架记录；无法读取 Claude 附件链接。

| 方法/路径 | 请求/响应要点 |
| --- | --- |
| GET `/api/moments` | 数组；`author=user/ke`，`image` 单个 URL，赞为整数，内嵌 `comments`；当前服务器最多 50 条，未提供分页 |
| GET `/api/moments/status` | `last_ke_activity_at:String, waiting:Bool` |
| POST `/api/moments` | `{content,image,visibility:"private"}`，允许纯图；成功返回 `id` |
| POST `/api/moments/like` | `{id,liked:Bool}` |
| POST `/api/moments/edit`、`/delete` | `{id,content}` / `{id}` |
| POST `/api/moments/comment` | `{moment_id,content}` |
| POST `/api/moments/comment/edit`、`/delete` | `{id,content}` / `{id}` |
| POST `/api/upload` | multipart `file`，返回 `url` 原样写进 `image` |
| GET `/api/sticky-notes` | `[{id:String,author:"user"或"ai",content,created_at}]` |

红点使用服务器的柯活动时间（包括新帖子、评论及点赞）。只在列表成功加载后记为已读，先取状态再读列表，避免吞掉读取途中到来的新活动；按线路保存。本机不向服务器写已读状态。页面在前台轮询，等待回复 5 秒、其余 45 秒；编辑器打开时暂停列表轮询。

## 待 Claude 的服务端工作

1. 恢复朋友圈；动态和回复由长窗里的柯本人写，停止旧自动生成路径。
2. 将旧便利贴的长文迁入朋友圈，保留原作者与原内容。
3. 给出并上线便利贴确认、恢复的准确契约（路径、方法、请求体、返回字段、已收起内容如何读取）。本次本机交互可验收，接入服务器后再验跨设备同步。
4. 核对删除权限：参考副本的动态/评论 delete 路由没有作者限制，App 已封住柯的改删入口，服务器仍应拒绝删除柯的内容。
5. 核对活动时间：旧实现对已被柯点赞的动态使用 `updated_at`，用户编辑或点赞可能触发假红点。客户端按当前状态接口读取，未更改后端语义。
6. 花园新工单未提供，本次未猜测花园需求，也未恢复旧的代发聊天按钮。

## 验收记录

待补充本分支 CI、原生截图与最终 IPA 哈希。测试使用匿名内存数据，不向生产朋友圈或便利贴写入。真机照片选择、生产服务恢复后端到端交互、跨设备收起同步需要单独验收。
