import 'package:web/web.dart' as web;

/// Alipay's WAP cashier is the mobile-web route.  Let the backend sign that
/// route only for phone/tablet browsers; desktop browsers retain QR/desktop
/// cashier behavior.  The user agent is advisory only and never controls
/// price, membership or callback validation.
bool shouldUseAlipayWap() {
  final userAgent = web.window.navigator.userAgent.toLowerCase();
  return RegExp(r'android|iphone|ipod|ipad|mobile|windows phone')
      .hasMatch(userAgent);
}

void openAlipayCheckout(String checkoutUrl) {
  final uri = Uri.parse(checkoutUrl);
  if (uri.scheme != 'https' || uri.host.isEmpty) {
    throw ArgumentError.value(checkoutUrl, 'checkoutUrl', '支付链接无效');
  }
  // Both Alipay's desktop and WAP products document a browser form submit as
  // the navigation mechanism.  Posting the server-signed fields (rather than
  // opening a popup or constructing an alipay:// URL) lets the mobile cashier
  // perform its own safe App handoff and works in browsers that block popups.
  final form = web.HTMLFormElement()
    ..method = 'post'
    ..action = '${uri.origin}${uri.path}'
    ..style.display = 'none';
  for (final entry in uri.queryParametersAll.entries) {
    for (final value in entry.value) {
      form.append(web.HTMLInputElement()
        ..type = 'hidden'
        ..name = entry.key
        ..value = value);
    }
  }
  web.document.body?.append(form);
  form.submit();
}

String? returnedAlipayOrderId() {
  final value = Uri.base.queryParameters['order'];
  return Uri.base.queryParameters['payment'] == 'alipay' &&
          value != null &&
          RegExp(r'^DS[a-f0-9]{40}$').hasMatch(value)
      ? value
      : null;
}

void clearReturnedAlipayOrderId() {
  final uri = Uri.base;
  final parameters = Map<String, String>.from(uri.queryParameters)
    ..remove('payment')
    ..remove('order');
  final clean =
      uri.replace(queryParameters: parameters.isEmpty ? null : parameters);
  web.window.history.replaceState(null, '', clean.toString());
}
