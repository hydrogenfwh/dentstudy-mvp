# DentStudy 支付宝电脑网站支付上线清单

DentStudy 的支付宝电脑网站支付现已由负责人明确授权开启。套餐、条款和付款入口只会展示给服务器绑定的单一支付作者账号；其他用户既不会看见页面内容，也无法通过 API 读取或创建支付订单。首次真实付款仍应由该作者本人在浏览器完成，并检查回跳、已签名异步通知、订单状态和会员期限是否一致；本次启用没有创建订单、扣款或授予 VIP。

## 已在开放平台核对的状态（2026-10-20）

- DentStudy 网页应用 `2021007108676915` 当前显示“已上线”，应用图标已更新为书本标志。
- 商家平台显示「电脑网站支付」和「手机网站支付」签约均为**已生效**，并且当前商户已绑定 DentStudy 网页 AppID。商家平台的“去收钱”仍显示未完成，指向的正是开发接入与应用配置，而不是重新签约。
- 开发设置显示接口加签已设置、服务器 IP 白名单已设置；应用网关显示未设置。项目每笔订单会单独提交 `notify_url`，不依赖该网关字段。
- ECS 从阿里云实例元数据读到的公网出口 IP 是 `115.29.230.228`。生产机已用真实 AppID、应用私钥和官方支付宝公钥，对一个不存在的订单执行**只读** `alipay.trade.query`：支付宝返回 HTTP 200 与预期的 `ACQ.TRADE_NOT_EXIST`，且响应 RSA2 签名已通过验签。这没有创建订单或扣款，并确认了当前私钥/AppID、平台公钥、出网、查单授权和该白名单路径可通；它不是收款、回调或退款验收。
- 生产机现在有 `/etc/dentstudy/dentstudy-payments.env` 和 `/etc/dentstudy/alipay-platform-public-key.pem`，均为 `600 root:root`。应用私钥与应用公钥已验证为同一对；官方支付宝公钥已从开放平台取得并安装。`DENTSTUDY_ALIPAY_LIVE=true`，而微信和旧版共享开关仍为 `false`；仅绑定作者可真实建单。
- 当前结论：商户签约、AppID 绑定、RSA2 请求签名、平台响应验签、支付 API 路由和网络均已通过非扣款核对，且支付宝真实建单已启用。第一次真实付款需要由负责人本人完成受控的端到端验收（收银台、回跳、异步通知、订单与会员期限）；微信真实收款仍关闭。

## 先分清网络、白名单和密钥

- **后端/API**：后端是服务器上的 Python 程序；API 是网页向它请求数据的约定；“路由”是一个 API 地址，例如 `/api/v1/payments/alipay/notify`。
- **公网出口 IP**：`115.29.230.228` 是本台 ECS 主动连接支付宝、微信等外部服务时，对方看到的来源 IP。它不是访问者的 IP，也不是域名。
- **服务器 IP 白名单**：支付宝用它限制“哪台服务器可以调用支付宝接口”。需要在开放平台核对规则含有 `115.29.230.228`；不要填写 `127.0.0.1`、浏览器所在 IP 或域名。若以后迁移机器、NAT 或云平台，出口 IP 可能变化，必须重新核对。
- **异步通知/回调（`notify_url`）**：付款后，支付平台从互联网向 DentStudy 发一个已签名的 HTTPS POST 请求。它与白名单方向相反：白名单管“本站出去”，回调管“支付平台进来”。
- **端口与 Nginx**：外网只需要访问 HTTPS `443`（HTTP `80` 只负责跳转/验证）；Nginx 再把 `/api/` 转给只监听本机的 `127.0.0.1:8787`。不要把 `8787` 开到公网或填写到支付平台。

## 上线前必须完成的业务决定

1. 公开并审核会员权益、有效期、自动续费情况（本项目不实现自动续费）、退款/争议处理时限、客服方式、用户协议和隐私说明。页面不再能声称“免费项目”或“无商业用途”。
2. VIP 套餐及期限：月卡首月 ¥1、之后每次手动续费 ¥6.9；季卡 ¥15.9/3 个月；半年卡 ¥28.9/6 个月；年卡 ¥45.9/12 个月；终身 ¥89.9。没有自动续费或周期扣款；月卡首月优惠按账号限一次，成功付款后即使后来退款也不会恢复，未付款/已关闭订单则不会消耗它。订单创建时将价格与期限写入订单，之后调价不改变旧订单。
3. 应用目前已显示“已上线”，无需再等待这一步审核。服务器出口 IP、白名单、密钥和只读查单均已核对；支付宝已在负责人明确授权后开启。首次收款后仍必须核对回调、查单/对账和退款流程。

## 服务器机密配置

只在生产服务器创建 `/etc/dentstudy/dentstudy-payments.env`，由 root 读取。私钥和支付宝公钥使用单独 PEM 文件，并限制为 root 可读；不要将其放入 Git、Flutter 构建产物、浏览器、本地题库或聊天记录。下面的文件名只是推荐的安全命名；填写前必须确认它们对应的实际 root-only 文件，不能因为服务器上“有一个 PEM”就猜测用途。

| 名称 | 来自哪里 | 在本项目中的角色 |
| --- | --- | --- |
| **应用私钥** | 商户/开发者生成并保管 | `DENTSTUDY_ALIPAY_PRIVATE_KEY_PATH`；服务器用它对发往支付宝的请求签名。绝不上传或发送。 |
| **应用公钥** | 由应用私钥导出并上传到支付宝开放平台 | 供支付宝验证本站请求；**不要**填入 `DENTSTUDY_ALIPAY_PUBLIC_KEY_PATH`。 |
| **支付宝公钥** | 从支付宝开放平台下载 | `DENTSTUDY_ALIPAY_PUBLIC_KEY_PATH`；服务器用它验证支付宝异步通知的签名。 |

```ini
# DentStudy 网页应用的公开应用 ID（不是密钥）
DENTSTUDY_ALIPAY_APP_ID=你的应用ID
# 支付宝商家/收款方 user_id，用于严格校验异步通知的 seller_id
DENTSTUDY_ALIPAY_SELLER_ID=你的支付宝user_id

# 支付页面、套餐和订单只能由这个已注册账号使用。
# USER_ID 是该账号注册后服务端 users.id 的不透明 ID，不是邮箱；
# 必须与邮箱双重匹配。两项缺任一项时支付功能对所有账号关闭。
DENTSTUDY_PAYMENT_AUTHOR_EMAIL=dentstudy1126@aka.yeah.net
DENTSTUDY_PAYMENT_AUTHOR_USER_ID=注册后由服务器管理员写入的users.id

# 仅 root 可读的 PEM 文件；第二个必须是“支付宝公钥”，不是“应用公钥”。
DENTSTUDY_ALIPAY_PRIVATE_KEY_PATH=/etc/dentstudy/alipay-app-private-key.pem
DENTSTUDY_ALIPAY_PUBLIC_KEY_PATH=/etc/dentstudy/alipay-platform-public-key.pem

# 必须与生产 HTTPS 域名一致；不要填开放平台的“应用网关”字段。
# 每笔 alipay.trade.page.pay 请求会单独传入 notify_url。
DENTSTUDY_ALIPAY_NOTIFY_URL=https://dentstudy.uno/api/v1/payments/alipay/notify
DENTSTUDY_ALIPAY_RETURN_URL=https://dentstudy.uno/payment-complete

# 价格与期限由代码中的服务端套餐表核定；无需设置单独金额或期限环境变量。

# 线上默认网关；沙箱验证时才临时替换为支付宝沙箱网关。
DENTSTUDY_ALIPAY_GATEWAY=https://openapi.alipay.com/gateway.do

# 支付宝真实收款独立开关：当前已由负责人明确授权开启。
DENTSTUDY_ALIPAY_LIVE=true
# 微信支付采用独立开关；未完成微信联调前保持 false。
DENTSTUDY_WECHAT_PAY_LIVE=false
# 旧版共享开关：仅供旧环境诊断，不能开启任一渠道；保持 false。
# 只有上面两个独立开关才分别控制支付宝和微信，互不继承。
DENTSTUDY_PAYMENTS_LIVE=false
```

示例权限：`install -m 600 -o root -g root /dev/null /etc/dentstudy/dentstudy-payments.env`；应用私钥必须为 `600 root:root`，支付宝平台公钥应由 root 管理（可为 `644 root:root`，它不是秘密）。仅由有服务器权限的人在服务器上填写这些值；不要把私钥、APIv3 密钥或完整环境文件粘贴给聊天助手。本项目借助服务器已安装的 `openssl` 进行 RSA2 签名和验签，部署前须验证 `openssl version` 可运行。

## 服务端流程与接口

| 路径 | 用途 | 安全要点 |
| --- | --- | --- |
| `GET /api/v1/payments/alipay/offer` | 仅绑定的支付作者读取可售状态、套餐价格和期限 | 其他账号直接 401；关键配置缺失时作者看到 `available: false` |
| `POST /api/v1/payments/alipay/checkout` | 仅绑定的支付作者创建固定金额订单并返回 `alipay.trade.page.pay` 跳转地址 | 金额、商品和 `out_trade_no` 全由服务端生成 |
| `POST /api/v1/payments/alipay/notify` | 接收支付宝表单回调 | 校验 RSA2 签名、`app_id`、`seller_id`、金额、订单归属和交易号；只在 `TRADE_SUCCESS`/`TRADE_FINISHED` 时原子授予会员 |
| `GET /api/v1/payments/alipay/orders/{id}` | 支付返回页确认订单状态 | 仅订单本人可读取；已部署的后端会在支付宝渠道已开启且订单待支付时签名调用 `alipay.trade.query`，作为漏回调恢复路径 |
| `POST /api/v1/payments/alipay/close` | 关闭本人未付款订单 | 服务端签名调用支付宝关单接口 |
| `POST /api/v1/payments/alipay/refund` | 退款 | 仅作者账号；仅允许安全回退当前最新会员期限的全额退款，其他订单需人工核对 |

浏览器回跳只展示服务端查询到的订单状态，**不会**因为 URL 参数、本地存储或前端按钮自行开通 VIP。支付宝异步通知是正常的自动授予路径；已部署的服务端签名查单仅用于恢复延迟或漏送的通知。两条路径都会在服务端核对订单号、交易号和金额；相同交易按支付宝交易号幂等处理。

**已部署但尚未真实验收的上线闸门**：待支付订单的 `alipay.trade.query` 恢复路径已随安全发布部署。支付宝异步通知仍是主路径；在渠道已开启时，返回页会签名查单，以恢复延迟或漏送的通知，并再次核对订单号、交易号和金额。它不是定时任务：在开启真实支付宝扣款前，仍必须用沙箱/受控订单验收这条路径，并制定/演练可审计的周期性或人工对账与补单流程。

## 微信支付（网页扫码 Native）

微信 Native 的后端草稿路由已部署，**不等于微信支付已开通或可收款**。生产真实扣款默认关闭。后端可创建 Native 支付订单并返回 `code_url`，但还需要前端接入二维码展示和支付状态轮询后才能供用户扫码。微信回调必须先用微信支付平台公钥验签，再用 APIv3 密钥解密，并严格核对 AppID、商户号、订单号、金额、币种和支付状态后才写入会员。订单页查状态时，后端也会向微信查单，以补偿延迟/漏送的通知。关闭订单会请求微信关单接口。

微信支付配置使用独立开关，不会因为开启微信而顺带启用支付宝。不要设置共享的 `DENTSTUDY_PAYMENTS_LIVE=true`；它仅供旧环境诊断，不能作为开关。只在微信商户资料、前端二维码页面、回调、退款流程和测试全部验收后，单独开启 `DENTSTUDY_WECHAT_PAY_LIVE=true`。支付宝仍只由 `DENTSTUDY_ALIPAY_LIVE` 控制。

微信商户后台需要准备这些值/文件：

| 配置 | 在哪找 / 是什么 | 例子或安全要求 |
| --- | --- | --- |
| `DENTSTUDY_WECHAT_PAY_MCH_ID` | 微信支付商户号 | 数字 ID；不是个人微信号 |
| `DENTSTUDY_WECHAT_PAY_APP_ID` | 与网页支付产品绑定的 AppID | `wx...`；必须已在商户平台关联 |
| `DENTSTUDY_WECHAT_PAY_CERT_SERIAL` | 商户 API 证书序列号 | 证书管理页中的十六进制序列号 |
| `DENTSTUDY_WECHAT_PAY_PRIVATE_KEY_PATH` | 商户 API 证书工具生成的商户私钥 PEM | root-only 文件，绝不发给前端/微信客服/聊天 |
| `DENTSTUDY_WECHAT_PAY_PUBLIC_KEY_ID` | 微信支付平台公钥 ID | `PUB_KEY_ID_...`；与平台公钥文件配套 |
| `DENTSTUDY_WECHAT_PAY_PUBLIC_KEY_PATH` | 下载的微信支付平台公钥 PEM | 用于校验微信响应和支付通知 |
| `DENTSTUDY_WECHAT_PAY_API_V3_KEY` | 商户平台 API 安全页设置的 APIv3 密钥 | 32 个 UTF-8 字节；用于解密通知，不是证书私钥 |
| `DENTSTUDY_WECHAT_PAY_NOTIFY_URL` | 支付成功通知地址 | `https://dentstudy.uno/api/v1/payments/wechat/notify` |
| `DENTSTUDY_WECHAT_PAY_LIVE` | 微信独立扣款总开关 | 全部验收前为 `false` |

密钥、证书文件只能经 SSH 在服务器 root shell 中配置；本项目不会要求你把内容贴到聊天或发到浏览器。服务器还需安装 [backend/requirements.txt](../backend/requirements.txt) 中固定版本的 `cryptography`，仅用于 AES-GCM 解密。商户证书与 APIv3 密钥如何获取/用途请看[微信支付开发必要参数说明](https://pay.wechatpay.cn/doc/v3/merchant/4013070756)，不要把“API 密钥”误当成“商户私钥”。

| 路径 | 用途 | 安全边界 |
| --- | --- | --- |
| `GET /api/v1/payments/wechat/offer` | 登录后查询是否可售 | 密钥缺失/功能关闭时 `available=false` |
| `POST /api/v1/payments/wechat/checkout` | 按 `planId` 创建所选套餐订单并取二维码链接 | 登录必需；金额、套餐、期限均由服务端核定 |
| `GET /api/v1/payments/wechat/orders/{id}` | 查询本人订单 | 登录必需；服务端查微信状态并处理漏掉的成功回调 |
| `POST /api/v1/payments/wechat/close` | 关闭本人未付款订单 | 登录必需；已支付订单不能关闭 |
| `POST /api/v1/payments/wechat/notify` | 微信异步通知 | 无需用户登录；平台公钥验签 + APIv3 解密才接纳 |

当前微信退款接口/退款通知对账尚未实现，因此，**尽管扫码下单、支付通知和关单路由可以部署，真实微信收款仍须保持关闭**。上线之前要补齐与验收全额退款、退款回调、会员回退策略和人工对账；也要把 `code_url` 做成用户真正能扫码的网页 UI。实现的是 HTTPS API 路径，外界不需要另开防火墙端口；Nginx 仍把 `/api/` 转发到本机 127.0.0.1:8787。

生产 Python 服务用隔离环境 `/opt/dentstudy-venv` 运行；新增 Python 库时需更新依赖文件并在这个环境安装，再重启服务。微信回调/下单路由虽然已经随此版 API 上线，但没有商户配置时 offer 返回不可购买，匿名探测返回登录错误，真实付款按钮不会被打开。

## 下一步安全核对与发布顺序

1. **保留最小开启面**：仅支付宝独立开关为 `true`；微信和旧的 `DENTSTUDY_PAYMENTS_LIVE` 均保持 `false`。不要在浏览器、Git 或聊天中输入私钥。
2. **核对支付宝平台**：应用显示“已上线”、电脑网站支付产品可用、签名方式为 RSA2；展开服务器 IP 白名单并确认精确包含 `115.29.230.228`。白名单并不是回调地址，也不要因为“应用网关未设置”而盲目填值。
3. **绑定支付作者后再开放入口**：先用 `dentstudy1126@aka.yeah.net` 注册并登录 DentStudy；由服务器管理员在生产数据库确认这正是待绑定的新账号，读取它的 `users.id`，并把邮箱和该 ID 一起写入 root-only 环境文件。不能只填邮箱，也不要把这个不透明 ID 写入网页或 Git。绑定完成前，所有账号都看不到套餐和支付入口。
4. **核对密钥角色而不泄露内容**：由服务器管理员确认应用私钥、应用公钥、支付宝公钥各自来源正确；当前应用私钥与应用公钥已验证为同一对，官方“支付宝公钥”已保存为平台公钥文件。不要覆盖现有私钥。确认私钥与环境文件为 `root:root`、`600`。
5. **核对路由和网络**：检查 `https://dentstudy.uno/api/health` 返回正常；确认回调 URL 是 `https://dentstudy.uno/api/v1/payments/alipay/notify`，Nginx 把 `/api/` 转发到本机 `127.0.0.1:8787`，且公网没有暴露 `8787`。
6. **验收已部署的恢复能力**：在隔离环境中验证待支付订单的 `alipay.trade.query` 恢复路径；制定/演练周期性或人工对账补单流程；验证错误金额、错误 `seller_id`、错误签名、未知订单均返回 `failure` 且不授予会员；验证未付款关单和一笔最新订单的全额退款不会误缩短后续会员期。
7. **沙箱或受控测试**：使用与生产隔离的沙箱应用、密钥和网关，验证“建单 → 收银台 → 已签名通知 → 订单 `paid` → 会员到期时间写入 → 重放同一通知不重复延长”。不要把沙箱与生产密钥混用。
8. **本次启用与后续核对**：SQLite 已在启用前备份，套餐、退款/争议说明和客服联系方式仍需负责人复核；在负责人明确授权后已把 `DENTSTUDY_ALIPAY_LIVE=true` 写入 root-only 环境文件，微信和共享旧开关保持 `false`。第一次付款必须由负责人自己操作并核对以下命令的结果：

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart dentstudy
   ```

9. 用一笔负责人同意的受控真实小额订单做最终验收，随后在支付宝和数据库中对账。不要把支付开关、密钥或私钥作为前端构建参数；完成前不要面向普通用户开放付款按钮。

## 当前服务器状态与不能跳过的步骤

- HTTPS 站点和 `/api/` 路由正常，ECS 能建立到支付宝与微信支付 API 域名的 TLS 连接；这只证明网络可达，不等同于商户身份认证、签名或扣款成功。
- 生产机已配置 `/etc/dentstudy/dentstudy-payments.env` 和官方支付宝平台公钥，均仅限 root 读取；支付宝独立 LIVE 开关已开启，微信和共享旧开关仍关闭。请勿把任何私钥粘贴到聊天或写进 Git。
- 微信 Native（网页扫码）后端路由已经部署，但目前缺少微信商户密钥，且用户侧二维码/支付状态 UI 与退款闭环尚未验收，所以微信真实收款也必须保持关闭。
- 已核验：未登录或非绑定作者访问套餐、支付宝 offer 或微信 offer 均返回 `401`；这是刻意的隐私与认证保护。支付作者尚未完成不可变账号 ID 绑定，绑定前连作者本人也不会看到付款内容。它们与支付回调路由已经部署，不代表可以真实扣款。
- 对历史“支付宝接口 404”不能仅凭应用状态断定原因：此前本站旧版本缺少会员/签到路由会产生本站 404；支付宝上游 404 则仍需当时具体 API、HTTP 响应及支付宝 `sub_code/sub_msg` 才能定因。现在应用已上线，若支付宝仍有 404，应先检查网关、接口名/产品权限及请求签名参数，而不是先把它归因于审核。
