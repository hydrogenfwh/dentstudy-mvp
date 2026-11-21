import 'package:web/web.dart' as web;

// Open directly from the tap. Browsers that block new tabs can use the same tab.
void openLivLivConversation() {
  final url = '/livliv/conversation.html';
  final opened = web.window.open(url, '_blank');
  if (opened == null) web.window.location.assign(url);
}
