# DentStudy 支付接入前置清单

当前代码只提供作者可见的支付内测卡、服务端会员表和评论金牙标识。它**没有**生成付款链接、二维码或订单，也不会因为浏览器本地状态授予 VIP。

真实收款前，必须同时完成以下事项：

1. 经营主体、网站备案、域名持有人和实际服务内容保持一致；若首页仍声明“无任何商业用途”，不要启用付费会员。
2. 分别在支付宝开放平台和微信支付商户平台，以主体完成实名认证、产品/网站审核、签约以及结算账户绑定。
3. 制定并公开会员服务内容、生效规则、退款/争议处理、客服渠道、隐私说明和用户协议；价格及权益不能与页面不一致。
4. 把商户号、应用 ID、私钥/证书和回调验签材料仅保存到服务器 root 可读的 `/etc/dentstudy/dentstudy-payments.env`；不要提交到 Git、题库文件、浏览器前端或聊天记录。
5. 先实现并验证：创建订单 → 调起官方支付 → 服务端验签回调 → 原子写入 `payment_orders` 和 `vip_memberships` → 幂等测试 → 退款/关单。只有第 4、5 步完成后才能设置 `DENTSTUDY_PAYMENTS_LIVE=true`。

示例环境文件仅说明名称，不含真实密钥：

```ini
DENTSTUDY_ALIPAY_APP_ID=你的支付宝应用ID
DENTSTUDY_WECHAT_PAY_MCH_ID=你的微信支付商户号
# 真实私钥、平台证书序列号和 API v3 密钥应按各官方 SDK/验签实现单独保存。
# 未完成回调验签前，请不要设置为 true。
DENTSTUDY_PAYMENTS_LIVE=false
```

发布后重载服务：`sudo systemctl daemon-reload && sudo systemctl restart dentstudy`。不要把此环境文件上传至 GitHub。
