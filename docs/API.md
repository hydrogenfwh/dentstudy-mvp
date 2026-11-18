# API v1 与数据结构

API 默认 `http://127.0.0.1:8787`，JSON UTF-8。线上浏览器通过 `https://dentstudy.uno/api` 访问；Nginx 将这个同域前缀转发给只监听本机的 `127.0.0.1:8787`，不应把 8787 暴露到公网。私有接口使用 `Authorization: Bearer <token>`。token 在数据库只存 SHA-256 摘要，客户端使用系统安全存储；密码使用随机盐和 PBKDF2-SHA256。会话有效期 30 天。

| 方法 | 路径 | 输入 / 输出 |
| --- | --- | --- |
| GET | `/health` | 服务版本与状态 |
| GET | `/v1/questions` | 完整题库，用于本地缓存 |
| GET | `/v1/vip/plans` | 仅服务器绑定的支付作者读取套餐目录；价格、期限和首月说明由服务端固定返回，不创建订单 |
| POST | `/v1/auth/register` | `{email,password}` → `{token,userId,email}` |
| POST | `/v1/auth/login` | 同上 |
| POST | `/v1/auth/logout` | `{}`，撤销当前 token |
| POST | `/v1/account/delete` | 当前登录账号 `{password,confirmation:"DELETE"}` → `{ok:true,deleted:true,fileCleanupPending:bool}`；永久删除当前账号，不接受目标用户 ID |
| POST | `/v1/sync` | `{events:[...]}`，最多 500 条；返回完整快照 |
| GET | `/v1/state` | 返回当前账号快照 |
| POST | `/v1/question-bank-submissions` | 登录后提交 `{filename,content}`；仅 `.json`，原文件最大 12 MB |
| POST | `/v1/ai/question-bank/prepare` | 登录后提交 `{text,name,subject,chapter,mode}`，将 Word/TXT 已提取的文字整理为待审核 JSON；最多 6 万字、每账号每日 3 次 |
| POST | `/v1/assistant/chat` | 仅配置的作者账号可用的 AI 聊天入口（不是本地互动）`{message,history?,deep?,companion?}`；`companion` 仅允许 `xiaochi`（省略时默认，兼容旧客户端）或 `dafeiyu`，后端选择固定身份与站点只读知识，不接受客户端系统提示。共用原额度与权限；其他账号仍返回升级中。单条最多 1000 字、上下文最多 6 条，不保存聊天原文 |
| GET | `/v1/question-bank-submissions` | 登录后查看自己的投稿；配置的作者账号可查看全部投稿元数据 |
| GET | `/v1/admin/question-bank-submissions/{id}` | 仅作者可下载一份投稿的原始 JSON；响应不缓存且不会经静态目录公开 |
| GET / POST | `/v1/profile` | 当前账号资料；读取结果只对本人额外给出 `isPaymentAuthor` 布尔值。保存 `{nickname,avatar,university}`。头像兼容预设键或客户端裁剪的 PNG data URI（512 KB、512 像素以内） |
| GET | `/v1/checkins?year=2026` | 登录后读取该账号的签到日历；目前支持 2026–2035，日期和连续签到按北京时间计算 |
| POST | `/v1/checkins` | 登录后签到当天；重复请求幂等，不能补签 |
| GET | `/v1/questions/{id}/comments` | 返回 `comments`、去重后的 `participantCount` 和 `totalCount`；携带登录 token 时附带每条评论的 `myVote` |
| POST | `/v1/questions/{id}/comments` | `{body,parentId?}`；登录后评论或回复，回复限定同一题目 |
| POST | `/v1/comments/{id}/vote` | `{value:1/-1/0}` 表示赞/踩/取消；同账号仅保留一种评价，返回 `likes,dislikes,myVote` |
| GET | `/v1/users/search?q=关键词` | 登录后按昵称搜索 2–40 个字符；最多返回 20 个不含邮箱的公开资料 |
| GET | `/v1/friends` | 登录后返回好友、收到的申请和已发出的申请 |
| POST | `/v1/friends/requests` | 登录后提交 `{userId}` 发起好友申请；同向重试幂等，交叉申请自动成为好友 |
| POST | `/v1/friends/requests/{id}/accept` 或 `/reject` | 收件人处理好友申请 |
| GET | `/v1/notifications?limit=100` | 登录后返回点赞、评论回复、好友和私信通知，以及 `unreadCount`；不返回邮箱 |
| POST | `/v1/notifications/read` | `{ids?}`；省略 `ids` 时标记本人全部通知已读，指定时最多 100 条 |
| GET | `/v1/conversations` | 登录后返回已接受好友的私信会话及未读数 |
| GET / POST | `/v1/conversations/{friendId}/messages` | 仅已接受好友可读取或发送；POST `{body}` 限 1–1000 字，按发送人每会话限速每秒一条 |
| GET | `/v1/admin/users` | 仅作者可见用户资料和邮箱；返回 `users`（最多 1000 条）、实际注册账号总数 `totalCount` |
| POST | `/v1/comments/{id}/delete` | `{}`；仅发布者可删除自己的评论。清除正文与赞踩，保留他人回复所需的占位关系；评论列表返回 `canDelete`、`deletedAt` |
| GET | `/v1/admin/comments?offset=0` | 仅作者可见评论管理，含发布者邮箱、昵称、题目 ID/题干/章节、评论和时间；每页 50 条，返回 `totalCount`、`nextOffset` |
| GET | `/v1/admin/payment-preview` | 仅作者查看支付配置预览；不创建订单，也不代表支付已开通 |
| GET | `/v1/payments/alipay/offer` | 仅服务器绑定的支付作者读取支付宝是否可售与套餐；缺少任一生产配置或开关关闭时 `available=false` |
| POST | `/v1/payments/alipay/checkout` | 仅该支付作者提交 `{planId}`；仅在支付宝独立开关和全部配置有效时才创建订单、返回收银台跳转地址 |
| GET | `/v1/payments/alipay/orders/{id}` | 仅该支付作者读取订单状态；在支付宝开启且订单待支付时，服务端会签名调用 `alipay.trade.query` 作恢复校验 |
| POST | `/v1/payments/alipay/close` | 仅该支付作者关闭未付款支付宝订单 |
| POST | `/v1/payments/alipay/refund` | 仅该支付作者；仅安全条件满足时处理最新会员期的全额退款 |
| POST | `/v1/payments/alipay/notify` | 支付宝服务器的表单回调；不使用用户 token，必须通过 RSA2、应用 ID、收款方、金额和订单校验 |
| GET | `/v1/payments/wechat/offer` | 仅支付作者读取微信渠道是否可售；当前生产环境应为 `available=false` |
| POST | `/v1/payments/wechat/checkout` | 登录后提交 `{planId}`；后端 Native 路由返回 `codeUrl`，但用户二维码页面尚未完成 |
| GET | `/v1/payments/wechat/orders/{id}` | 登录后读取本人订单，并在未支付时向微信查单 |
| POST | `/v1/payments/wechat/close` | 登录后关闭本人的未付款微信订单 |
| POST | `/v1/payments/wechat/notify` | 微信服务器回调；不使用用户 token，必须先验平台签名并用 APIv3 密钥解密 |

大肥鱼形象及摸头、夸赞、睡觉／唤醒是面向游客和所有用户的免费本地互动，没有对应的业务 API，不调用模型、不消耗 AI 额度、不改石头余额。没有明确形象偏好的账号默认大肥鱼，设置中可切换小齿；已明确选择小齿的偏好保留。本地互动与上述作者专用的 `/v1/assistant/chat` 权限独立，客户端发送层和服务端均保留聊天门禁。首次下载静态图片或网站原有的资料／消息轮询不是 AI 调用。

头像由客户端提供可拖动、缩放的正方形裁剪页，确认后导出为 256×256 PNG，再通过资料接口保存。
登录表单的“记住密码”使用浏览器或系统密码管理器的 Autofill 功能；本地偏好仅保存是否启用和邮箱，不保存明文密码。

账号删除在写事务内重新验证会话与当前密码；5 次密码错误后暂停 10 分钟。删除用户、所有会话、资料、学习记录、签到、投稿元数据、评论/赞踩、好友、涉及该账号的私聊/通知及 AI 请求计量；他人的回复保留为独立评论。投稿文件通过持久化队列清理，启动及每分钟重试，失败时 `fileCleanupPending=true`。发起删除的会话摘要保留 24 小时，仅允许同一删除请求重试，不能访问其他接口。管理员被删除时保存地址摘要，阻止重新注册者继承管理权限，恢复管理角色需由运维核验后明确处理该阻断记录。

付款订单转入 `deleted_account_payments`，不含用户 ID、邮箱或资料，仅保留交易编号、金额、状态、日期和退款编号用于对账。已验签迟到通知更新归档并标记人工核对，不重新创建账号或会员；删除账号不自动退款。数据库与文件备份不属于在线删除事务。恢复旧备份前必须另存当前 `deleted_account_tombstones`、`deleted_account_role_blocks` 和订单归档，用旧备份用户 ID 的 SHA-256 对照删除摘要并清理命中账号后才能恢复服务，不能直接回滚用户数据库。

快照：`events` 原始日志，`states` 每题排期/题本状态，`attempts` 用于统计的作答记录，`plan` 含今日 due、新题与 newLocked，`settings` 为账号级学习目标。

`/v1/sync` 可同时带 `settings`：

```json
{
  "events": [],
  "settings": {
    "dailyNewLimit": 20,
    "dailyReviewTarget": null,
    "updatedAt": "2026-09-26T08:30:00.000Z"
  }
}
```

`dailyNewLimit` 为 0–1,000,000；`dailyReviewTarget` 为 0–200，`null` 表示无限制。服务端按 `updatedAt` 保留较新的设置。

答题事件：

```json
{
  "id": "device-random-unique-event-0001",
  "questionId": "demo-001",
  "at": "2026-09-25T08:30:00.000Z",
  "kind": "review",
  "value": {"answer":"B", "grade":"mastered", "mode":"practice"}
}
```

`kind` 还可为 `favorite`（value 为 bool）、`note`（字符串最多 10000 字）、`removeWrong`（null）。grade 为 wrong/guessed/mastered；mode 为 practice/review/exam。主观题 answer 为用户书写的文本。事件时间必须带时区，不得超过服务器当前时间 5 分钟。超时请求可按原事件 ID 原样重试。

常规请求体限制 2 MB；题库投稿允许原文件最大 12 MB（为容纳 JSON 传输封装，请求上限 16 MB）；AI 整理请求上限 512 KB，原文字上限 6 万字；小齿聊天请求上限 24 KB。仅 `/health`、`/v1/questions` 与公开评论读取不要求登录；其余面向用户的业务接口通常无 token 返回 401。套餐与所有买方支付接口额外要求服务器配置的支付作者账号 ID 和邮箱同时匹配，其他登录用户同样收到 401；支付页面也不会向其请求或渲染价格。两个支付 `notify` 路由例外：它们不接受用户 token，而是分别通过支付平台签名和回调数据验真。支付路由已部署不等于真实收款已启用；当前生产环境没有加载支付环境文件，两个独立 LIVE 开关均为关闭。校验失败 400，AI 未配置、免费额度耗尽或服务器预算到顶返回 503。同步批次原子提交，一条无效则整个批次回滚。不同账号的事件使用复合主键隔离。

AI 整理使用服务器受限环境变量中的阿里云百炼 API Key，客户端、Git 和响应中都不携带密钥。只有用户在导入对话框显式点击“AI 智能整理”时，当前文字才会发送给模型；服务端不持久化原文或模型原始输出，只保存账号标识、调用时间、token 计数与预算金额用于限流。模型仅可提取原文中已有的题干、2–8 个选项和与选项一致的答案；不完整或答案不明确的条目会被丢弃，结果统一标为用户导入、待医学审核，不能进入公开题库。

小齿聊天当前仅配置的作者账号可用；其他账号在客户端点击会显示“小齿正在升级中···”，服务端也会拒绝此类请求。消息与最近最多 6 条临时上下文只在本次请求中发给模型；服务端不写入消息或回复，也不写入题库或学习事件。为实现作者账号的每日额度，服务端只保存账号标识、调用类别（闲聊/专业）与调用时间、token/预算计数；每个账号每天最多 10 句闲聊，口腔医学与备考问题不占该闲聊额度，站点仍保留全站预算保护。小齿只讨论人类口腔医学与口腔备考；无关话题会被温和引导回具体学习目标。它不能点击、上传、下载、跳转或改变网站，也不能协助未授权资料、版权规避或医疗诊断。

题库投稿先在客户端本地校验、合并至该设备的离线题库；登录后才会把原始 JSON 副本提交至服务端。服务端再次执行 `backend/bank.py validate` 校验，保存到 `DENTSTUDY_SUBMISSIONS` 指向的私有目录，不经 Nginx 对外提供。投稿文件只用于人工审核，用户须确保拥有分享权限，不得上传个人隐私、受限或来源不明的内容。`DENTSTUDY_ADMIN_EMAIL` 对应的账号可在客户端投稿箱查看文件名、题数、大小、时间及投稿邮箱，并可通过仅作者可用的下载接口将原始 JSON 保存到本地；下载响应为 `no-store`，不会生成公开链接。

用户自行导入的题库题目 ID 不属于服务端的官方题库。此类题目的作答、收藏、笔记等事件仅保留在该设备本地，不会进入 `/v1/sync`；这样既能正常练习，也不会被服务端按不存在的题目 ID 拒绝。官方题库题目的同步、事件 ID 与排期契约不变。

题目 JSON 模板见 `mobile/assets/questions.json`。主要字段：

- `id` 为不可变内容版本 ID；`subject/chapter/topics/tags` 支撑学习检索。
- `modes`：考研、本科期末、执医；研究生和助理医师细分用标签筛选。
- `type`：A1/A2/A3/A4/B/简答题/案例分析；共用题干题型提供 `groupId/sharedStem`。B 型同组共用 `options`。
- `answer`：客观题为选项键，主观题为 null，主观题提供 `rubric`。
- `paperId/paperName/durationMinutes/order/points` 定义试卷、时长、顺序与分值。
- `school/year/sourceType/sourceUrl/license` 记录来源；真实院校试题不能用演示元数据代替。
- `citation`：publisher/title/edition/chapter/page/verified；正式发布需核实。
- `reviewStatus/reviewer/reviewedAt`：正式导入必须为 approved 并有审核记录。

数据库当前含用户、会话、事件、学习设置、题库投稿元数据与不含原文的 AI 调用计量；运行题库仍为经校验的版本化 JSON。已有 Web 后端可保持此 API 契约，用数据库题库表替换 JSON，并以 PostgreSQL 持久化事件。

## 羟基磷灰石（站内奖励积分）

- `GET /v1/stones?before=<ledger-id>`：需登录，仅返回本人的可用 `balance`、待支付预扣 `reserved`、`items`（`id/amount/reason/createdAt`）、`nextCursor`、实时 VIP 方案和支付开关。每页最多 50 条，时间为带时区的 ISO 8601，界面按北京时间展示。
- `POST /v1/stones/share`：`{"systemShareCompleted":true}`。每天首次系统分享 +1；客户端取消、不支持、单独复制链接不请求奖励。它是每日限次的客户端分享结果声明，**不是收件人送达证明**，服务端不能验证用户确实选中了分享对象。返回 `stoneRewards`。
- 签到、题库上传、同步接口在同一事务中记奖励，返回 `stoneRewards`；前端提示“获得1羟基磷灰石”，每个奖励 ID 在当前会话只显示一次。响应丢失不会重复入账，可在钱包查看。
- 签到每日 +1；连续每满 7 天额外 +7，断签重新计数。学习和复习分别每天首次达到目标 +1；分享每天首次 +1。上传有效新内容每份 +1、每日最多 +3；题目内容相同但换文件名、题目 ID、排版或顺序不重复奖励。未授奖的重复上传不会隔日补领。
- 按服务器北京时间划分日期，不追溯补发历史学习奖励。学习目标在当天首次同步时按服务器已有目标与题库冻结：新题目标不超过可学新题数；复习目标不超过当天到期题数，无限复习时需完成全部到期题。零任务不领奖、同题重复作答不累计、本机私有题库不计。`/v1/sync` 增加 `mode`，限定考研/本科期末/执医；更换方向不重置当天奖励目标。
- `POST /v1/stones/redeem`：`planId/requestKey/expectedPriceFen`。由服务端计算价格，以整数分计算 `1 stone = 2 fen`；¥6.90 对应 345 颗。要求余额足够且交易编号幂等；余额扣减、兑换订单与 VIP 授予原子提交。首月优惠仍沿用既有价格，石头兑换同样消耗首月资格。客户端保存未确认的请求编号用于断网重试。
- `POST /v1/payments/alipay/checkout` 增加可选 `stoneCount`（默认 0）、`expectedPriceFen`。组合支付创建订单时预扣石头，支付宝仅支付剩余金额；全额石头走兑换接口。重复请求沿用原订单，不能改变原抵扣数量。签名支付回调/查单成功后授予 VIP，不再次扣石头。只有已核验的订单关闭或退款才返还石头，不能按客户端超时擅自解冻。
- 钱包显示待支付订单，支持查询结果与请求关闭。未被支付平台确认关闭的订单可能持续预扣，应继续核验或人工处理，不可直接改余额。
- `DENTSTUDY_STONE_REDEMPTIONS_OPEN=true` 独立开放全石头兑换，默认关闭。组合支付继续服从原有 `DENTSTUDY_MEMBERSHIP_PURCHASES_OPEN`、商户配置、支付宝 live 开关及作者身份限制，**未开放普通用户现金支付**。原生端不展示可执行的网页支付宝支付操作；原生上架支付方案仍须另行实现与验收。
- 这是不可转让、不可提现、不可充值的站内奖励积分。账号删除清理钱包与任务数据，必要兑换记录和含抵扣数量的支付记录解除用户关联后保留。没有给旧账号批量补币，也没有商城商品。

网页端直接等待 Web Share 的 Promise，解决 share_plus 11.1.0 在浏览器成功后仍报告 unavailable 的差异；不使用邮件或复制链接作为降级奖励依据。取消、不支持与异常不会请求奖励。不同浏览器成功回调可能仅代表调起系统分享，不保证分享对象收到内容。

系统分享参考：[Web Share API](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share)、[share_plus 11.1.0](https://pub.dev/packages/share_plus/versions/11.1.0)。不同平台对分享结果的反馈能力不同；原生分享仍需真机验证。
