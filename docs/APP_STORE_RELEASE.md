# 齿间：iOS 与 Android 商店发布

项目是 Flutter 原生应用，而不是网站套壳。发布前请先确定不可随意更改的应用标识：

- Android `applicationId`：已设为 `uno.dentstudy`。提交前请在 Google Play Console 确认尚未被占用；一经发布，不要再修改。
- iOS Bundle Identifier：已设为 `uno.dentstudy`。请在 Apple Developer 中登记此标识；它必须由你的 Team 持有且不能与他人冲突。
- 显示名称当前为“齿间”；版本来自 `mobile/pubspec.yaml`，目前为 `1.1.2+112`。每一次提交商店都要递增 build number。

## 0. 本机工具

仓库已有 Flutter SDK（`tools/flutter`），无须重复下载。推荐从仓库根目录使用发布脚本，它会自动定位 SDK，并在缺少工具或签名信息时停止：

```bash
bash mobile/release.sh check    # 检查 Android 与 iOS 环境，不构建、不上传
bash mobile/release.sh android  # 生成正式签名 AAB
bash mobile/release.sh ios      # 生成正式签名 IPA
```

脚本固定生产地址 `https://dentstudy.uno/api`，从 `pubspec.yaml` 读取显示版本，并写入北京时间构建时间。它不会创建商店记录或上传安装包。

2026-10-22 本机检查：已有 Flutter；缺 JDK、Android SDK、完整 Xcode、CocoaPods、Android 上传密钥配置与 Apple Developer Team。尚未进行原生编译和签名验证。

在 macOS 安装 Flutter stable、Xcode、Android Studio（含 Android SDK）和 CocoaPods 后，在仓库根目录运行：

```bash
tools/flutter/bin/flutter doctor -v
cd mobile
bash bootstrap.sh
../tools/flutter/bin/flutter analyze
../tools/flutter/bin/flutter test
```

Android/iOS 工程当前均已存在。仅在缺失平台包装文件时使用 `bootstrap.sh`；它会自动定位仓库内 Flutter。生成后，用 Xcode 打开 `ios/Runner.xcworkspace`。

## 1. Android：建立上传密钥与 AAB

在安全的密码管理器中保存密钥密码，并在**不受版本控制**的位置创建上传密钥：

```bash
keytool -genkeypair -v -keystore ~/dentstudy-upload.jks -alias dentstudy-upload -keyalg RSA -keysize 2048 -validity 10000
cd mobile/android
cp key.properties.example key.properties
```

编辑 `key.properties`，填入密钥的真实路径和密码，`storeFile` 相对路径基于 `mobile/android`（也可用绝对路径）。该文件及 `.jks` 已被 Git 忽略。缺少或未填写正式签名配置时，Release 任务会停止；Debug 构建不需要正式密钥。没有调试签名回退。

Android ID 及 Kotlin 入口已设为 `uno.dentstudy`。从仓库根目录构建：

```bash
bash mobile/release.sh android
```

上传 `build/app/outputs/bundle/release/app-release.aab` 到 Google Play Console 的内部测试轨道，先完成封闭测试与崩溃检查，再创建正式版。中国安卓商店通常也接收 AAB 或要求其自有包格式、隐私与主体材料；按每家商店后台的当期要求提交。

## 2. iOS：签名、TestFlight 和 App Store

1. 登录 Xcode 和 Apple Developer，创建最终 Bundle Identifier 与 App Store Connect 应用记录。
2. 在 `ios/Runner.xcworkspace` 的 Runner target 中设置 Team、Bundle Identifier、版本与 Build；启用自动签名即可由 Xcode 创建开发/发行证书。
3. 本地通知已接入，实机测试系统授权、后台和重启后的提醒；仅本地通知不需要 APNs 远程推送能力。
4. 构建并上传：

   ```bash
   bash mobile/release.sh ios
   ```

5. 先邀请 TestFlight 测试员，再在 App Store Connect 填写截图、分级、隐私标签、支持 URL、隐私政策 URL 和审核说明，最后提交审核。使用 `https://dentstudy.uno/support.html` 作为支持 URL、`https://dentstudy.uno/privacy.html` 作为隐私政策 URL。

2026-10-22 经所有者明确授权后，账号删除功能及修订后的隐私政策、支持页已部署到生产环境。公网 `/api/health` 正常；未登录的删除请求返回 HTTP 401；线上政策页面、JavaScript 和 WebAssembly 产物哈希均与已测试的本地发布包一致。未对生产真实账号执行删除测试；原生真机验收仍待完成。

## 3. 提交前必须验证

- 生产 API 是 HTTPS，且注册、登录、同步、支付入口、题库下载都使用生产地址。
- 测试首次安装、升级安装、离线答题、登录同步、通知权限拒绝/允许、导入文件及账号注销。
- **已实现：应用内账号删除。** 入口“我的 → 设置 → 删除账号”及“服务与规则 → 数据删除申请 → 删除账号”；输入当前密码、勾选告知并二次确认后调用 `/v1/account/delete`。网页版直达链接为 `https://dentstudy.uno/?account=delete`。删除后撤销全部会话，清理本人在线数据与本机账号缓存；失败不会假报成功，断网可重试。必要交易记录解除账号关联后保留，备份和其他设备离线缓存的边界已在确认前说明。仍需原生真机验收，不代表已通过审核。依据：[Apple 账号删除要求](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)。
- 审核题库、版权/来源与医学内容表述；当前仓库题目含“待审核”内容，不能宣传为已审核真题。
- 隐私政策与 App 内收集/传输行为一致。不要在商店表单中遗漏账号、学习记录、上传题库、支付或第三方服务的实际数据处理。
- 若要在应用内销售数字会员、订阅或解锁内容，先确认商店内购政策和当前支付实现；不要在未经审核前开启真实收款。

## 还需由应用所有者提供的项目资料

- 最终反向域名应用 ID、Apple Developer Team、Google Play 开发者主体；
- 各商店的开发者账号访问权限；
- 商店图标源文件、至少一套 iPhone 与 Android 真机截图、隐私政策和支持网址；
- Android 上传密钥（只能由所有者创建并保存）。

发布脚本回归检查：`python3 -m unittest discover -s scripts/tests -p 'test_mobile_release.py' -v`。它模拟工具与凭据条件，检查缺失条件时停止及正确构建参数；不替代真实 Gradle/Xcode 编译。

## 2026-10-22 账号删除交付状态

- 本地已实现并构建：账号密码复验、二次确认、数据清理、所有会话撤销、文件清理重试、已删除账号交易归档及迟到回调处理。
- 验证：完整后端 70 项测试通过；账号删除、规则页、注册登录共 9 项 Flutter 测试通过；Flutter 静态分析通过；WebAssembly + JavaScript 双构建成功。
- 已发布版本：`20261022-account-deletion-r1`。API `/opt/dentstudy-releases/20261022-account-deletion-r1`，网页 `/var/www/dentstudy-releases/20261022-account-deletion-r1`；`dentstudy` 和 `nginx` 服务均为 active。
- 发布前已使用 SQLite backup API 做一致性备份，路径 `/opt/backups/dentstudy-20261022-account-deletion-r1/dentstudy.sqlite3`，完整性检查为 `ok`。在复制的发布目录更新程序和网页，健康检查通过后切换链接；没有替换或回滚用户数据库，没有执行真实账号删除。
- 公网验证：`/api/health` 返回 `ok`，未认证的 `POST /api/v1/account/delete` 返回 HTTP 401；`privacy.html`、`support.html`、`main.dart.js` 和 `main.dart.wasm` 的 SHA-256 均与本地产物一致。发布包 SHA-256：`dc007592af55aa0b938cd81c354de18cc663361c180113780e0e727ea90144bd`。
- 删除页面已在本地浏览器验证。发布后浏览器自动化连接超时，未完成公网 UI 复验；可手动打开 `https://dentstudy.uno/?account=delete` 检查。原生打包、签名及商店审核尚未完成。
- 保留上一版 API `/opt/dentstudy-releases/20261021-vip-notice-logo-r4` 和网页 `/var/www/dentstudy-releases/20261022-chat-stability-r1`。回退代码前须评估账号删除后的交易回调兼容性；禁止直接恢复旧数据库而复活已删除账号。

## 2026-10-22 设置入口整理

- “我的”新增单一“设置”入口，集中主题与外观、学习设置、服务与规则；删除账号入口为“我的 → 设置 → 删除账号”。网页版删除直达链接保持不变。
- 移除“我的”页“关于题库”卡片和学情页“小样本仅供参考”文字；统计计算和题目审核状态不变。
- 相关 Flutter 回归与手机尺寸渲染检查共 34 项通过，静态分析通过，WebAssembly + JavaScript 发布构建完成。
- 已发布静态网页 `/var/www/dentstudy-releases/20261022-profile-settings-r1`，保留前版 `20261022-account-deletion-r1`。本次没有更新后端或数据库。
- 公网健康接口正常，JavaScript、WebAssembly、隐私页和支持页哈希与本地构建一致。发布包 SHA-256：`bea233c622f1aba271c814a15623e46aa06fac4c11ddc1a32e87f8cb35aaa046`。

## 2026-10-22 羟基磷灰石：本地实现，未发布

> 此节记录首次本地交付；随后经所有者要求“直接同步”完成发布，见下方上线记录。

- 已实现按账号隔离的整数积分流水、签到与每连续七天奖励、学习/复习/分享各自每日首次奖励、上传每日最多三次奖励，以及重复请求防重和并发余额保护。日期统一按北京时间。
- “我的”消息入口左侧使用用户提供的原始牙齿金币 Logo，以 contain 等比例显示。钱包包含余额、时间与增减明细、规则、空商城；VIP 页面包含全石头兑换和石头 + 支付宝组合支付计算，¥6.90 对应 345 颗。
- 兑换、组合支付预扣、核验关闭/退款后的返还和账号删除清理已接入后端。全石头兑换默认关闭，现金支付仍保持原有关闭/作者限制，未扩大收款权限。未执行真实付款、兑换或生产数据库操作。
- 完整后端 83 项测试通过；相关 Flutter 回归含手机预览共 43 项通过。最终分享兼容修正后的钱包 6 项测试再次通过，静态分析通过，WebAssembly + JavaScript 发布构建成功。构建仍提示既有 Cupertino 字体族未打包警告。网页端直接使用 Web Share Promise，取消和不支持不领奖；原生分享尚待真机验收。
- 本地手机尺寸预览已检查：个人资料入口、钱包、VIP 数量展示；预览账户与 400 颗余额均为测试数据，不代表线上用户余额。
- 本轮未部署。线上仍使用 API `20261022-account-deletion-r1` 和网页 `20261022-profile-settings-r1`。发布须同时更新前后端和隐私说明，发布前备份数据库；是否开放全石头兑换需所有者确认。原生签名、商店内购与上架审核仍未完成。

## 2026-10-22 羟基磷灰石正式同步

- 所有者要求“直接同步”后，前后端同时发布为 `20261022-stones-r1`：API `/opt/dentstudy-releases/20261022-stones-r1`，网页 `/var/www/dentstudy-releases/20261022-stones-r1`。
- SQLite 在线一致性备份：`/opt/backups/dentstudy-20261022-stones-r1/dentstudy.sqlite3`，仅 root 可访问。在独立副本验证迁移后切换程序；既有用户、学习事件、订单与会员数量在副本迁移前后一致，正式库完整性与外键检查通过。未恢复/替换生产数据库，未补发历史奖励，未执行真实兑换或付款。
- 保留上一版 API `20261022-account-deletion-r1` 和网页 `20261022-profile-settings-r1`。仅回退代码，不通过恢复旧数据库回退；新增积分/订单字段需保留。
- 公网健康接口正常，匿名钱包请求 HTTP 401；公网 JavaScript、WebAssembly、Logo、隐私页、Service Worker 的 SHA-256 均与已测试本地产物一致。`dentstudy` 与 `nginx` 服务 active。
- 发布包 SHA-256：`8ba9bdfb0aea2312fdf55524bb775928cba337077e83d3e6b7ec8176362efd8d`。发布前后确认 `DENTSTUDY_MEMBERSHIP_PURCHASES_OPEN` 与 `DENTSTUDY_STONE_REDEMPTIONS_OPEN` 均未设置（关闭），未改变任何支付凭据或收款权限。
- 奖励与钱包已上线；作者与普通登录账号均可看到个人资料消息图标左侧的金币入口。已打开的旧页面需刷新获取新版。
- 后续浏览器验收遇到 Safari 空白，发现默认 Flutter 启动配置不允许 WebKit 使用 Skwasm；补入持久化 `mobile/web/flutter_bootstrap.js` 配置并重新构建，网页切换至 `/var/www/dentstudy-releases/20261022-stones-r2`，后端仍为 r1。静态包 SHA-256：`e42a936f726bc04cbe638e6984de2bdaf3b59d5a5602c51b3c66df6f49ecf566`。新版启动脚本、JS、WASM、Service Worker 公网哈希核对一致。
- **显示验收尚未完成**：自动化 Safari 窗口强制刷新后仍空白，暂不能断言上述配置已解决渲染问题；应用内浏览器读取超时。服务器资源请求正常，已询问所有者实际浏览器刷新结果。未声称在生产登录账号实测通过钱包页面，未因此清理浏览器数据或改动用户余额。

## 2026-10-23 启动数字类型兼容修复

- 用户提供的报错为启动读取本地数据时的 `Runtime type check failed`。新增回归在修复前复现：`SharedPreferences.getDouble` 对旧网页 JSON 中的整数 `0` / `1` 强制转换为 `double?`，分别在小齿位置与自定义背景参数读取时失败；WebAssembly 会区分整数和小数。
- 四个小数偏好改为读取 `num` 后在内存中 `toDouble()`，不重写旧偏好，不删除学习记录、未同步队列、草稿或背景图片。异常装饰性数值使用默认值，原始存储保留。
- 38 项相关 Flutter 回归通过；4 项启动专项在原生测试与 Chrome WebAssembly 测试中通过；静态分析和 WebAssembly + JavaScript 构建成功。浏览器专项使用模拟偏好、安全存储和题库资源，真实执行初始化与类型转换，不代表真实用户账号已验收。
- 仅网页发布到 `/var/www/dentstudy-releases/20261023-startup-numeric-r1`，保留前版 `20261022-stones-r2`。后端仍为 `20261022-stones-r1`，没有数据库迁移、数据清理、支付开关调整或真实交易。
- 静态发布包 SHA-256：`95c7ff38f1c34ef81a7f162e69ad984491b3c7b44d42de0539f4c56b1e972afe`。公网 JS、WASM 与启动脚本哈希与本地修复版一致，Nginx 和 API 服务正常。
- 发布后 Chrome 通过实际页面验收，显示完整学习首页、4,210 题、今日计划、签到和底部导航，无启动错误；未进行登录、签到、答题或支付操作。Safari 自动化窗口仍为空白，未声称 Safari 显示验收通过，用户原报错页面是否恢复仍需确认。无需清除网站数据。
