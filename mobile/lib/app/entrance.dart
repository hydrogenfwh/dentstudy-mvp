import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'shared.dart';
import 'motion.dart';
import 'language_selector.dart';
import '../features/profile/profile_page.dart' show showAccountDialog;
import '../features/profile/alipay_checkout.dart';

/// A static web welcome screen. The application is already built underneath,
/// so either action opens immediately without a second loading step.
class Entrance extends StatefulWidget {
  final Widget child;
  const Entrance({super.key, required this.child});

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> {
  bool opened = false;

  @override
  void initState() {
    super.initState();
    final orderId = returnedAlipayOrderId();
    if (orderId == null) return;
    // A completed browser checkout returns to the same signed-in web build.
    // Fetch the server-authoritative result instead of trusting query text.
    opened = true;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reportPayment(orderId));
  }

  Future<void> _reportPayment(String orderId) async {
    try {
      // The return URL can arrive a moment before Alipay's asynchronous
      // notification.  Make a few bounded, server-authoritative checks so a
      // buyer normally sees the verified result without trusting URL text.
      for (var attempt = 0; attempt < 4; attempt++) {
        final order = await store.alipayOrderStatus(orderId);
        if (!mounted) return;
        switch (order['status']) {
          case 'paid':
            message(context, '支付已确认，VIP 服务已开通');
            return;
          case 'closed':
            message(context, '该支付订单已关闭');
            return;
          case 'created':
            if (attempt < 3) {
              await Future<void>.delayed(const Duration(seconds: 3));
              continue;
            }
            message(context, '支付结果正在确认，请稍后在“我的”查看');
            return;
          default:
            message(context, '支付状态：${order['status'] ?? '处理中'}');
            return;
        }
      }
    } catch (_) {
      if (mounted) message(context, '暂未确认支付结果，请稍后在“我的”查看');
    } finally {
      clearReturnedAlipayOrderId();
    }
  }

  void _start() {
    setState(() => opened = true);
    // This is an introduction for a new browser, rather than a way to leave
    // an existing account.  Keep the choice locally without touching auth.
    store.completeWebWelcome();
  }

  void _login() {
    setState(() => opened = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showAccountDialog(context, onSuccess: () async {
          await store.completeWebWelcome();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Native keeps the direct-to-app behavior it had before the web welcome
    // screen was introduced.
    // A securely restored session always goes straight to that account.  The
    // visitor button therefore can never look like an account switch while a
    // learner is already signed in.  Returning visitors who signed out also
    // skip this one-time introduction and enter the local visitor view.
    if (!kIsWeb ||
        opened ||
        store.token.isNotEmpty ||
        store.hasCompletedWebWelcome) {
      return widget.child;
    }
    return Stack(children: [
      ExcludeFocus(child: ExcludeSemantics(child: widget.child)),
      _WelcomeLayer(onStart: _start, onLogin: _login),
    ]);
  }
}

class _WelcomeLayer extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onLogin;
  const _WelcomeLayer({required this.onStart, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
        color: studyBackground(colors.brightness),
        child: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 390),
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 16),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: LanguageSelector(
                                      compact: true,
                                      value: store.languageCode,
                                      onChanged: (value) =>
                                          store.setLanguage(value))),
                              const SizedBox(height: 18),
                              SizedBox(
                                  width: 78,
                                  height: 78,
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: Image.asset(
                                          'assets/brand-logo.png',
                                          fit: BoxFit.cover))),
                              const SizedBox(height: 22),
                              Text(tr('齿间'),
                                  style: TextStyle(
                                      color: colors.onSurface,
                                      fontSize: 31,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 2)),
                              const SizedBox(height: 6),
                              Text(tr('DENTSTUDY'),
                                  style: TextStyle(
                                      color: colors.primary,
                                      fontSize: 12,
                                      letterSpacing: 4,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 12),
                              Text(tr('每天学一点，记牢一点。'),
                                  style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 14)),
                              const SizedBox(height: 8),
                              Text(tr('登录后会安全保持登录状态，不保存明文密码。'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 12)),
                              const SizedBox(height: 42),
                              SizedBox(
                                  width: double.infinity,
                                  child: PressFeedback(
                                      child: FilledButton.icon(
                                          onPressed: onStart,
                                          icon: const Icon(
                                              Icons.play_arrow_rounded),
                                          label: Text(tr('访客模式'))))),
                              const SizedBox(height: 10),
                              SizedBox(
                                  width: double.infinity,
                                  child: PressFeedback(
                                      child: OutlinedButton.icon(
                                          onPressed: onLogin,
                                          icon:
                                              const Icon(Icons.person_outline),
                                          label: Text(tr('登录 / 注册')))))
                            ]))))));
  }
}
