# 从 MVP 到发行版本

当前代码适用于本地开发与产品验证。不会自动部署服务器、注册开发者账号、上传题库、发送推送或发布应用商店。

## 原生验收

1. `mobile/bootstrap.sh` 生成包装工程，`flutter analyze`、`flutter test` 与 Android debug 构建全部通过后，提交生成文件与 `pubspec.lock`。
2. 真机测试：中文字体缩放、窄屏、主观题键盘、切换应用后的模考计时、跨天复习、断网保存、同步重试、不同账号切换。
3. 本地提醒权限与重启恢复需分别测试 Android/iOS；本版按未来 14 天当前计划预排，学习或同步后应刷新。Android 使用非精确闹钟，操作系统可能延迟提醒。
4. iOS 需正式 Bundle ID、证书、签名和隐私资料；Android 需自己的发行密钥、应用 ID 与签名配置。

## 后端部署

- 以生产 HTTP 应用服务器/框架替换 Python `http.server` 开发服务器；HTTPS、限流、邮件验证、密码重置、日志审计、监控、备份恢复、账号注销与数据导出需补齐。
- 不把 SQLite 数据库、密钥或用户日志提交到代码仓库。可使用 `DENTSTUDY_DB` 配置数据库路径。
- 正式题库采用经过审核的发布文件，用 `DENTSTUDY_BANK` 指定；生产题库校验不得放宽为演示模式。
- 大数据量时将事件表迁移 PostgreSQL；支持游标增量同步、事件压缩与分页；移动端用 SQLite 保存大题库和事件。
- 所有现有个人学习数据按用户 ID 隔离。客户端令牌存安全存储；离线学习笔记当前保存到应用私有 SharedPreferences，未额外加密。

## 远程推送接入

当前实现的是本地通知。若要在不启动 APP 的情况下跨设备更新任务，需要：设备推送令牌表、服务端每日任务扫描、送达去重、用户时区/静默时间/退订状态，以及 APNs、FCM 或国内厂商凭据。本次未创建这些第三方资源，也未宣称已实现服务端推送。

## 题库与模考

真实院校试卷、考试真题、教材内容需授权和医学审核。图形化 CMS 后续应支持导入预览、题目版本、审核流、来源附件和撤回。当前提供 JSON 校验与追加导入 CLI。

当前模考按客户端时钟限时，客观题自动计分；未答题计零分但不伪造答题事件；主观题显示参考要点并手动评价。模考答对默认记为“蒙对/不稳”安排复习。尚未提交的模考答案保存在页面内存，关闭进程后不会恢复。用于正式考核需添加服务端计时、持久化考试会话和人工阅卷。

配置依据：[Flutter 创建工程](https://docs.flutter.dev/reference/create-new-app)、[通知插件 19.x 原生配置](https://pub.dev/packages/flutter_local_notifications/versions/19.0.0)。

## LivLiv 作者聊天和本地朗读

互动空间和主站须同源。Nginx 将 `/api/` 转发给现有后端并保留 Host。作者登录或恢复个人资料时，后端发放仅限助手路径的 HttpOnly Cookie。切换形象沿用作者聊天额度。语音服务只监听 127.0.0.1:8796，每个音频请求要携带后端为该账号、角色和原回复签发的短期凭据。

服务器上的 Qwen3-TTS Base 0.6B 使用与该角色问候对应的说话人向量、参考音频编码和台词。19 段问候可用 `scripts/design_livliv_voices.py` 和本地 Qwen3-TTS VoiceDesign 重新生成。更换声音时也要重新生成同名的 `.spk` 和 `.rvq`。

1. 在 `/opt/dentstudy-livliv-tts/2edb35f/src` 检出 [qwentts.cpp](https://github.com/ServeurpersoCom/qwentts.cpp) 的 `2edb35f87b709a070b2d5379f77e5c52a1daa585` 和对应的 ggml 子模块。在推理引擎源码根目录应用本仓库的 `deploy/livliv-qwen-short-context.patch`。它限制短句上下文并在单次推理结束后释放生成模型权重，给音频解码留出内存。
2. 运行 `cmake -S . -B ../build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_BLAS=OFF -DGGML_OPENMP=ON` 和 `cmake --build ../build --target qwen-tts qwen-codec -j2`。
3. 将 [量化模型文件](https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF) 放入 `/opt/dentstudy-livliv-tts/models/`。核对 `qwen-talker-0.6b-base-Q4_K_M.gguf` 的 SHA-256 为 `4b468ec7b1f62b90ef4ca316c0aa57deadfd54b2cf9651703ea753cedaf04226`，`qwen-tokenizer-12hz-Q4_K_M.gguf` 为 `cf3788b4d50aaa665fb6e57c170396aae03a3555fea52d2b5d0cda902d658039`。
4. 随后端一起部署 `backend/livliv_refs/` 和 `mobile/web/livliv/voices/lines.json`。更新某个角色时，用 `qwen-codec --model <codec.gguf> --talker <talker.gguf> -i <角色.wav>` 生成配套的两个参考文件。
5. 安装 `deploy/dentstudy-livliv-tts.service` 到 systemd，运行 `systemctl daemon-reload` 和 `systemctl enable --now dentstudy-livliv-tts`。重启该服务可清除短期音频缓存。部署后分别用访客和作者身份打开互动空间，验证访客问候、作者对话、切换音色和停止朗读。
