bool shouldUseAlipayWap() => false;

void openAlipayCheckout(String checkoutUrl) {
  throw UnsupportedError('电脑网站支付请在网页浏览器中完成');
}

String? returnedAlipayOrderId() => null;

void clearReturnedAlipayOrderId() {}
