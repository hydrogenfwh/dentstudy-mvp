import 'dart:math';
import 'dafeiyu_dialogue.dart' show DafeiyuInteraction;

/// Local-only dialogue. The three actions each have twenty distinct lines.
const gugaDialogue = <DafeiyuInteraction, List<String>>{
  DafeiyuInteraction.pet: [
    '嘿嘿，摸到企鹅帽啦～ (｡•ᴗ•｡)',
    '咕嘎把脑袋往你手心里靠一点 ♡',
    '摸摸头收到！今天心里暖乎乎的 ☀',
    '咕咕嘎嘎～这下开心得翅膀都要晃起来啦！',
    '帽子软软的，你的温柔也软软的 (´▽`)',
    '这颗小脑袋，今天也可以放心摸摸～',
    '嘿嘿，给你回赠一份企鹅式的好心情 🐧',
    '被摸摸了！我先悄悄开心三秒钟 ♡',
    '小翅膀接住啦，谢谢你的温柔 (｡･ω･｡)',
    '你的手好温柔，烦恼也跟着轻一点点～',
    '咕嘎乖乖站好，接受摸摸头！',
    '咕咕嘎嘎，企鹅帽今天也被认真照顾啦 🐧',
    '这一摸不计分，但可以兑换一个微笑 ✨',
    '如果你有点累，也记得摸摸自己的心呀 ♡',
    '啾咪，咕嘎把暖暖的心情送还给你～',
    '摸摸头时间到，不用着急做下一件事 (´ω`)',
    '好舒服呀，帽子歪一点也没关系～',
    '咕嘎收到啦！小翅膀开心地扑腾扑腾 ✨',
    '咕咕嘎嘎～温柔已经成功传达到企鹅星球！',
    '谢谢你陪我这一小会儿 (｡•ᴗ•｡) ♡',
  ],
  DafeiyuInteraction.sleep: [
    '咕嘎先躺一会儿，等你轻轻叫醒我～ Zzz',
    '小翅膀当枕头，企鹅进入休息时间 💤',
    '咕咕嘎嘎……梦里的小鱼排队来啦 (－ω－) zzz',
    '帽子盖好，眼睛闭好，开始安心打盹 ☁',
    '咕嘎躺平啦，你也可以按自己的节奏休息 ♡',
    '先充一会儿电，醒来再一起慢慢来～',
    '呼噜呼噜……企鹅睡得像一团小云朵 💤',
    '小黄脚收好，今天的休息任务开始！',
    '如果你也困了，不必勉强自己一直撑着 (´ω`)',
    '这不是偷懒，是企鹅的认真休息模式～',
    '咕咕嘎嘎，梦里见到一座软软的冰山 ☁',
    '我先安静躺着，想找我时轻轻点一下就好 ♡',
    '今天的风有点轻，适合睡个小小的觉 Zzz',
    '小脑袋靠稳啦，烦恼先放在一边 💤',
    '闭上眼睛数企鹅：一只、两只……咕嘎睡着啦。',
    '休息不需要证明什么，你也值得放松一下 ♡',
    '咕嘎去梦里散个步，很快就回来 (－ω－)',
    '咕咕嘎嘎……小翅膀已经困得不动啦 🐧',
    '给你留一朵柔软的云，咕嘎先打个盹 ☁',
    '晚安不分时间，困了就先让眼睛休息一会儿 Zzz',
  ],
  DafeiyuInteraction.praise: [
    '你愿意来找鼓励，已经很会照顾自己啦 ♡',
    '不必先做到完美，你现在就值得被夸夸 (｡•ᴗ•｡)',
    '慢一点没有关系，按自己的步子走就很好 🌱',
    '咕咕嘎嘎！给认真生活的你一枚企鹅勋章 🐧',
    '遇到不会的地方愿意停下来看看，很有耐心呀。',
    '小小的一步也算数，咕嘎给你鼓掌 ✨',
    '你有权利休息，也有权利为自己感到骄傲 ♡',
    '愿意说出“我需要夸夸”，是一件勇敢的事。',
    '不需要拿别人的进度衡量自己，你有自己的节奏～',
    '你已经给今天留了一点温柔，真不错 (´▽`)',
    '咕咕嘎嘎～咕嘎认证：你值得一份大大的鼓励！',
    '暂时没想明白不代表不行，给自己一点时间吧。',
    '能承认疲惫，也是认真照顾自己的表现 ☁',
    '你不需要永远精神满满，偶尔慢下来也很好。',
    '给你一颗小星星：愿你对自己多一点耐心 ✨',
    '就算今天只迈了一小步，那也是属于你的进展。',
    '愿意再试一试的心意，很值得被珍惜 ♡',
    '咕咕嘎嘎！企鹅挥舞双翅为你加油 (≧▽≦)',
    '不把困难藏起来，愿意寻求帮助，也很了不起。',
    '今天的你不必证明什么，也一样值得被善待 🐧',
  ],
  DafeiyuInteraction.wake: [
    '咕嘎醒啦～继续陪你 (｡•ᴗ•｡)',
    '小翅膀伸个懒腰，我们慢慢来 ♡',
    '嘿嘿，咕嘎醒着呢！🐧',
  ],
};

class GugaDialogueDeck {
  final Random _random;
  final _bags = <DafeiyuInteraction, List<String>>{};
  final _last = <DafeiyuInteraction, String>{};
  GugaDialogueDeck({Random? random}) : _random = random ?? Random();
  String next(DafeiyuInteraction interaction) {
    final bag = _bags.putIfAbsent(interaction, () => []);
    if (bag.isEmpty) {
      bag.addAll(gugaDialogue[interaction]!);
      bag.shuffle(_random);
      if (bag.length > 1 && bag.last == _last[interaction]) {
        final first = bag.first; bag[0] = bag.last; bag[bag.length - 1] = first;
      }
    }
    final result = bag.removeLast();
    _last[interaction] = result;
    return result;
  }
}
