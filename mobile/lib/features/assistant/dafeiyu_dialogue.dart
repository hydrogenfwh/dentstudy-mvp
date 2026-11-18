import 'dart:math';

enum DafeiyuInteraction { pet, praise, sleep, wake }

/// Local copy only: no model call, reward, learning event or personal inference.
const dafeiyuDialogue = <DafeiyuInteraction, List<String>>{
  DafeiyuInteraction.pet: [
    '嘿嘿，摸到啦～这一下，要偷偷开心好久 (≧▽≦)',
    '脑袋可以继续摸，你也记得对自己温柔一点呀 ♡',
    '收到摸摸！今天的世界柔软了一点点 🫧',
    '呜，耳朵都要开心得翘起来了～ (｡•ᴗ•｡)',
    '哦鲸鲸～你分给我的温柔，也要给自己留一份 🐳',
    '好啦，那点小委屈，被你摸走了一小半 (´ω`)',
    '嘿嘿，不躲！这颗蓝色脑袋今天可以摸摸～',
    '被认真对待的感觉，原来这么暖呀 ♡',
    '摸摸头已签收，回礼是一颗小小的好心情 ✨',
    '不用说什么，这份温柔我已经收到啦 (｡･ω･｡)',
    '往你手心里挪了一厘米……假装是不小心的。',
    '哎呀，发夹歪啦！不过开心比整齐重要一点点～',
    '如果有点累，就把这一刻当作小小的中场休息吧 ☁',
    '谢谢你呀。哦鲸鲸～不必一直很厉害，也可以只是很可爱。',
    '好舒服～决定不闹小脾气了 (´▽`)',
    '蓝色脑袋悄悄升温中……不是故障，是害羞。',
    '这一摸不计分，但很值得被珍惜 ♡',
    '嗯嗯，我在呢。不用急着把所有事都做好 (つ´ω`)つ',
    '哦鲸鲸，没摸够的话，还能再乖一会儿 🐳',
    '把这点暖乎乎的心情，也带给接下来的自己吧 ✨',
  ],
  DafeiyuInteraction.praise: [
    '当然要夸！不必先拿出成绩单，才值得被温柔对待 ♡',
    '愿意说“夸夸我”，也是在认真照顾自己的心情呀 (｡•ᴗ•｡)',
    '暂时没弄懂，只说明需要一点时间，不说明你不行。',
    '不必成为全场最厉害的人，也可以为自己骄傲 ✨',
    '哦鲸鲸～理解不是抢答比赛，慢一点也没关系 🐳',
    '能说出“这道题我不会”，比假装懂了更有勇气。',
    '你可以有不够好的发挥，但那不是“不够好的你” ♡',
    '如果只完成一小步，也别把它说成“什么都没做” 🌱',
    '认真和疲惫可以同时存在。累了，不会让努力失效。',
    '想夸的不是永远不出错的你，而是愿意学习的你 (≧▽≦)',
    '有些进步暂时看不见，花过的心思也不必因此被否定。',
    '听取建议，也保留自己的节奏，这两件事不冲突呀～',
    '哦鲸鲸，还没到目标，不等于一路走来都不值得肯定 ✨',
    '如果今天很难，“还愿意试一点点”也算勇敢 🌱',
    '不用拿别人的高光，审判自己正在摸索的这一段。',
    '值得被尊重，不是因为毫无缺点，而是因为你本来就值得 ♡',
    '愿意在卡住时重新看看，是很珍贵的耐心 (´ω`)',
    '一个小小的理解瞬间，也值得开心，不必等到全部学会！',
    '哦鲸鲸，允许自己休息是在照顾自己，不是认输 🐳',
    '送你一颗不和成绩挂钩的小星星：请站在自己这一边 ✨',
  ],
  DafeiyuInteraction.sleep: [
    '好哒，先把自己叠成一小团…… (-ω-)zzz',
    '大肥鱼进入省电模式，点一下就能重新开机～ 💤',
    '我先趴一会儿，你也不用一直绷得紧紧的 ☁',
    '小碗放好，脑袋放平，开始认真打盹……zzz',
    '哦鲸鲸～不和困意较劲啦，趴下也很体面 🐳',
    '去梦里找一朵最软的云，醒了再回来招手～ ☁',
    '耳朵收好，发夹扶正，呼噜准备就绪 (-ω-)zzz',
    '你继续忙自己的事就好，想互动时再点点我 💤',
    '这一觉不赶进度，也不和谁比较……zzz',
    '已经趴平！目前最大的计划：翻个舒服的身。',
    '如果你也有点累，这里允许暂停，不需要解释 ♡',
    '哦鲸鲸，先睡一小会儿，刚才的夸夸不会收回哦 🐳',
    '安静时间到，把声音调成棉花糖…… (｡-ω-)zzz',
    '不用为了叫醒我，特意给自己加一项任务呀～',
    '小脑袋搁好啦，接下来交给柔软的梦 ☁',
    '休息可以理直气壮，不必每一刻都证明自己 ♡',
    'zzz……不是摆烂，是一条鱼找到了舒服的姿势。',
    '哦鲸鲸，等你点我，我们再从一件小事开始 💤',
    '临时岗位：安静趴着的小蓝团，不催促任何人。',
    '把“必须马上做好”放远一点，示范一下安心趴下 (-ω-)zzz',
  ],
  DafeiyuInteraction.wake: [
    '原来是你呀！大肥鱼醒啦，继续陪你 (｡•ᴗ•｡)',
    '醒来第一眼就看见你，今天的好心情有着落啦 ♡',
    '小蓝鱼伸个懒腰～你想从哪件小事开始？',
    '收到唤醒信号！不用着急，我会陪你慢慢来 🫧',
    '哦鲸鲸～梦里的云好软，不过见到你更开心 🐳',
    '醒啦醒啦！刚才的呼噜声，就当你没听见哦 (≧▽≦)',
    '大肥鱼满电归来！你的节奏不用跟我一样快呀 ✨',
    '你回来啦，我也醒啦～先给你一个暖暖的招呼 ♡',
    '眨眨眼，整理好发夹，今天也请多多关照！',
    '从梦里游回来啦，你想学习还是先歇一会儿？',
    '嘿嘿，醒着呢！刚才只是让眼睛休息了一小下 (´ω`)',
    '哦鲸鲸～睡饱的小鱼准备好陪你一起加油啦 🐳',
    '被你轻轻叫醒，连起床都变成一件开心的事了 ♡',
    '我在我在！不用一下子做完，先迈出一小步就好 🌱',
    '呼噜暂停，陪伴继续～有什么事想让我一起看看？',
    '大肥鱼悄悄上线！今天也要对自己温柔一点呀 ☁',
    '醒啦，脑袋还有点迷糊，但给你的鼓励已经准备好了 ✨',
    '哦鲸鲸，休息过后重新出发，也是一种很棒的努力 🐳',
    '伸伸小手，拍拍裙摆～来，把今天过成自己的节奏。',
    '刚从甜甜的梦里回来，现在轮到陪你啦 (｡･ω･｡)',
  ],
};

String? dafeiyuVoiceAsset(DafeiyuInteraction interaction, String text) {
  final index = dafeiyuDialogue[interaction]!.indexOf(text);
  if (index < 0) return null;
  return 'assets/dafeiyu/voice/${interaction.name}-${(index + 1).toString().padLeft(2, '0')}.m4a';
}

/// A shuffle bag: hear every line once per category before a new cycle.
class DafeiyuDialogueDeck {
  final Random _random;
  final _bags = <DafeiyuInteraction, List<String>>{};
  final _last = <DafeiyuInteraction, String>{};
  DafeiyuDialogueDeck({Random? random}) : _random = random ?? Random();

  String next(DafeiyuInteraction interaction) {
    final bag = _bags.putIfAbsent(interaction, () => []);
    if (bag.isEmpty) {
      bag.addAll(dafeiyuDialogue[interaction]!);
      bag.shuffle(_random);
      if (bag.last == _last[interaction]) {
        final first = bag.first;
        bag[0] = bag.last;
        bag[bag.length - 1] = first;
      }
    }
    final result = bag.removeLast();
    _last[interaction] = result;
    return result;
  }
}
