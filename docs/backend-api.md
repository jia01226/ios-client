# 🔌 后端接口清单（给原生 App 对接用）

> **产出者**：能上 VPS 的窗 · 2026-08-14 · 只查只写、一行后端代码没改。
> **给谁**：写 `app-柯/KeApp/Core/APIClient.swift` 的人（知言/Codex）。
> **原则**：**APIClient 照这份对齐后端，不是让后端迁就 App。**
> ❓ = 还没完全查实/需拍板的，别当定论。

---

## 0. 一句话地基

- **服务地址**：`https://jiagude.love`（也接受 `www.jiagude.love`）
- **证书**：Let's Encrypt 正式证书（Certbot 管），**不是自签** → 原生 App 不会有证书报错，直接 https 连。
- **架构**：nginx（443）→ 反代 → gunicorn `127.0.0.1:8000` → Flask `app:app`
- **技术栈**：Python 3.10.12 · Flask 3.1.3 · SQLite 3.37.2（单库 `memories.db`）· 模型走外部 API（不在本机）
- **聊天引擎**：后端把消息交给 Claude Code CLI 子进程生成（App 无需关心，只管调 `/api/chat`）

---

## 1. 鉴权（原生 App 的第一个坎）

**现状 = Flask session cookie（不是 token）。**
- 登录：`POST /api/login`，body 里带口令 → 成功后 `session["ok"]=True`，服务器种一个**签名 cookie**（`Set-Cookie`）。
- 之后每个请求**带上那个 cookie** 才算已登录。
- ❗ **原生 App 不是浏览器**，不会自动管 cookie。App 必须：① 登录后从响应头抓 `Set-Cookie` 存起来（Keychain）；② 之后每个请求手动带上 `Cookie:` 头。iOS 的 `URLSession` 默认有 `HTTPCookieStorage` 能自动干这事，**但要确认它把 cookie 持久化了**（App 重启后还在）。
- **⚠️ 要柯拍板**：维持 cookie 这套，还是**给原生 App 单加一个 token 机制**（登录返回一个长期 token，App 放 header `Authorization: Bearer xxx`）？后者对原生更干净、更好调试。**我倾向加 token**，但这要动后端（几十行），你点头我再动——这一版可以先用 cookie 跑通。
- ❓ 口令是单一共享密码（她和柯共用一个）。具体存哪、能不能多设备，需再确认。

---

## 2. 聊天（第一版重点，就靠这几个）

### 2.1 发消息（流式）—— `POST /api/chat`
**请求 body（JSON）**：
| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `text` | string | 是 | 她说的话 |
| `session_id` | int | 是 | 会话 id（默认 1；见 `/api/sessions`） |
| `client_msg_id` | string | 建议 | 客户端生成的唯一 id（`[A-Za-z0-9._:-]{8,120}`），**防重发/断线重连去重** |
| `model` | string | 否 | 不传用默认 |
| `bedroom` | bool | 否 | 兼容旧前端；正常别传，卧室由后端信号切 |
| `image`/`attachments` | 见 ❓ | 否 | 发图，格式待补 |

**返回 = SSE 流**（`Content-Type: text/event-stream`），逐条 `data: {json}\n\n`，App 按顺序解析这几种：
| 事件 json | 含义 | App 怎么处理 |
|---|---|---|
| `{"user_message_id":..,"bedroom":bool,"job_id":".."}` | **首事件**：回执 | 记下 `job_id`（断线重连用）；`bedroom` → 交给 `Theme.applyServerSignal(bedroom:)` |
| `{"t":"增量文字"}` | 柯回复的**一小块正文** | **追加**到当前气泡（这是主力事件，流式拼起来就是回复全文） |
| `{"think_summary":".."}` | 柯的小念头（可展开的 ke_note） | 可选显示，不显示也行 |
| `{"error":"..","done":true}` | 出错/结束 | 显示错误、结束本轮 |
| 流自然结束 / `: keepalive\n\n` | 心跳/收尾 | `:` 开头的是心跳，忽略即可 |

> 🔴 **卧室模式**：就来自首事件的 `bedroom` 字段（还有 `/api/room/signal`、`/api/sessions/bedroom`），**App 不用给按钮，收到信号自动切**——正对上你 `applyServerSignal`。

### 2.2 断线重连（手机必备）—— job 机制
- 每次发消息后端建一个 `job`，SSE 里给了 `job_id`。
- 手机切后台/断网导致 SSE 断了，可用 `job_id` **重连拉未收到的事件**（后端按 `after_seq` 续发，有 `: keepalive` 心跳）。
- ❓ 重连的确切端点/参数（`_chat_job_response` 那条，疑似 `GET /api/chat/jobs?...`）——第一版可先不做重连、断了就重发；要做我再补精确签名。

### 2.3 拉历史 —— `GET /api/messages`
- 参数：`session_id`、游标（`around_id` + `limit`，`messages_around` 游标翻页）。
- 返回：消息数组。`chat_messages` 关键字段见 §5。
- 其他：`GET /api/chat/unread`（未读数）、`POST /api/chat/seen`（标已读）、`GET /api/sessions`（会话列表）。

---

## 3. 推送（先看清，APNs 是后面的活）

- **现状 = 浏览器 Web Push（VAPID）**：`GET /api/push/vapid`（公钥）→ `POST /api/push/subscribe`（存浏览器订阅）→ 存 `push_subscriptions` 表 → 由 `proactive.py`/`notification_outbox` 发。
- ❗ **原生 App 收不了 Web Push，要走 APNs**。这是**做原生 App 的唯一硬理由**（iOS 网页推送收不到）。
- **要新增（等 Apple 账号 + .p8 到位后）**：① 后端加一个端点 `POST /api/push/register-apns`（存 App 传来的 APNs device token，`KeApp.swift` 里 `didRegisterForRemoteNotifications` 那个 token）；② 发送侧在现有发 Web Push 的同一处，**并接一路 APNs**（用 .p8 + token-based auth）。
- **这半我能做**（后端加端点 + 发送逻辑），但**卡在 Apple 的 .p8 推送密钥**（账号激活后才能生成）。→ App 侧先把 `registerPushToken` 的桩留着。

---

## 4. 其余四个 tab 要的接口（第一版可先假数据，够用时再接）

- **【我们】**：`GET/POST /api/anniversaries`（纪念日）、`GET/POST /api/shifts`（排班）、`GET /api/schedule`、`GET /api/concerns`（❓提醒是否走这个，待确认）、`GET /api/protocol/today`
- **【玩】**：`GET /api/drawer`（抽屉）、`/api/treasures`、`/api/capsules`；调教室 = `/api/bobo/*`（config/status/session/poll/ack/disarm）
- **【回忆】**：`GET /api/diary`（枕边日记）、`/api/moments`（朋友圈）、`GET /api/memory/cards`（记忆卡）
- 完整端点还有几十个（moods/periods/readings/uploads…），要哪个我再逐条展开返回结构。

---

## 5. 数据表（App 对齐字段名用；SQLite `memories.db`）

- **聊天**：`chat_messages`（`id, session_id, author('ke'/'me'?见❓), content, msg_type, created_at, image, is_push, model, thought_note, scene_mode, client_msg_id, sensitive`）、`chat_sessions`、`chat_jobs` + `chat_job_events`（流式/重连）
- ❓ `author` 存的是 `ke`/`me` 还是别的枚举，写 App 前我确认一下再定 `Message.Sender` 的映射。
- **我们**：`anniversaries`、`shifts`、`ke_schedule_tasks`
- **回忆**：`diaries`(+`diary_comments`)、`moments`(+`moment_comments`)、`posts`(记忆卡/L2)、`private_memories`
- **推送**：`push_subscriptions`、`notification_outbox`、`notification_deliveries`

---

## 6. 流式格式再强调一次（解析错了就是一片空白）

- `Content-Type: text/event-stream`，事件之间 `\n\n` 分隔。
- **只认 `data:` 开头的行**，取后面的 JSON；`:` 开头（`: keepalive`/`: open`）是注释/心跳，**丢弃别报错**。
- 正文靠把所有 `{"t":".."}` 的 `t` **顺序拼接**。
- iOS 侧：`URLSession` 的 `bytes(for:)` 逐行读，或用现成 SSE 库；`APIClient.stream(_:)` 那个 `AsyncThrowingStream` 就是留给这个的。

---

## 7. 还没查实 / 要柯拍板的（❓清单）

1. **鉴权**：cookie 维持，还是给原生 App 加 token？（我倾向加 token，要动后端）
2. `author` 枚举的确切取值。
3. 发图/附件的请求格式（`/api/upload` 先传再带 url？）。
4. job 重连端点的精确签名（第一版可不做）。
5. 提醒（【我们】那格）到底落哪张表/哪个接口。
6. APNs：等 Apple .p8，后端并接那一路我来写。

> **需要我把哪一条展开成"真实 JSON 示例"，说一声我抓一条脱敏的贴上来。** 第一版聊天要跑通，先啃 §1（登录拿 cookie）+ §2（发消息解析 SSE + 拉历史）这两块就够。
