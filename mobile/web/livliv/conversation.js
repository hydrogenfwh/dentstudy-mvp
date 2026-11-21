(() => {
  const frame = document.querySelector('#kujira');
  const log = document.querySelector('#messages');
  const sleepButtons = document.querySelectorAll('[data-action="sleep"]');
  const fullscreenBubble = document.querySelector('#fullscreen-bubble');
  const dialog = document.querySelector('#character-dialog');
  const grid = document.querySelector('#character-grid');
  // Aster and Mira remain excluded, as requested for cropped hairstyles.
  const characters = [
    ['p01', 'Kujira', '今天也在这里陪着你'],
    ['p02', 'Kujira Q', '分你一口好心情'],
    ['p03', 'Pen', '咕咕嘎嘎，一起出发'],
    ['char06', 'Aoi', '陪你度过安静的学习时光'],
    ['char07', 'Sora', '今天也一起稳稳前进'],
    ['d01', 'Yui', '慢慢来，我会陪着你'],
    ['d02', 'Leo', '休息一下，再继续出发'],
    ['d03', 'Nana', '让今天多一点好心情'],
    ['d03ft', 'Nana 精修', '让今天多一点好心情'],
    ['k01', 'Sena', '和你一起闪闪发光'],
    ['k02', 'Elio', '把努力交给时间'],
    ['q02', 'Mochi', '软软的陪伴送给你'],
    ['q03', 'Kotaro', '元气满满，一起加油'],
    ['s01', 'Hana', '在这里等你休息一下'],
    ['v04', 'Kai', '呼吸一下，再轻松出发'],
    ['v05', 'Lilith', '陪你收藏今天的小进步'],
    ['v06', 'Usa', '给你一点柔软的好心情'],
    ['v07', 'Stella', '愿今天也温柔闪亮'],
    ['w01', 'Max', '打起精神，我们一起上'],
  ].map(([id, name, tagline]) => ({id, name, theme: id, tagline}));
  let current = characters[0];
  const folder = id => id === 'p01' ? './p01/' : `./library/${id}/`;
  let sleeping = false;
  let timer = null;
  let dots = null;
  let pending = {pose: 'wave', expression: null};
  const replies = {
    pet: {pose: 'happy', text: '摸摸头～今天也一起加油！ (｡•ᴗ•｡)'},
    praise: {pose: 'praise', text: '你已经很努力啦，给自己一个赞！✨'},
    angry: {pose: 'wave', expression: 'angry', text: '我有点生闷气啦，需要你陪我 (^_^)'},
    sad: {pose: 'wave', expression: 'sad', text: '今天有一点不开心，可以陪陪我吗？ (T_T)'},
    shy: {pose: 'wave', expression: 'shy', text: '这样夸我，我会害羞的啦！ (*^_^*)'},
    sleep: {pose: 'sleep', text: '休息一下，慢慢呼吸～🌙'},
    wake: {pose: 'wave', text: '醒啦，继续陪你一起学习～'},
    normal: {pose: 'neutral', text: '好啦，我在这里陪着你～ (｡•ᴗ•｡)'},
  };
  const names = {pet: '摸摸头', praise: '夸夸我', sleep: '睡一会', wake: '醒醒啦', angry: '生闷气', sad: '不开心', shy: '害羞', normal: '正常'};

  function sendPose(pose, expression = null) {
    pending = {pose, expression};
    frame.contentWindow?.postMessage(JSON.stringify({type: 'dentstudy-livliv-pose', pose, expression}), location.origin);
  }
  const frameUrl = id => `./frame.html?model=${encodeURIComponent(id)}&characters=4`;
  frame.addEventListener('load', () => {
    // Frame navigations are part of the browser's joint history. If an older
    // history entry resurfaces, restore the selected character before showing it.
    const shown = new URL(frame.contentWindow.location.href).searchParams.get('model') || 'p01';
    if (shown !== current.id) {
      frame.contentWindow.location.replace(frameUrl(current.id));
      return;
    }
    sendPose(pending.pose, pending.expression);
  });

  function addMessage(text, outgoing = false, thinking = false) {
    const row = document.createElement('div');
    row.className = `message ${outgoing ? 'outgoing' : 'incoming'}`;
    if (!outgoing) {
      const avatar = document.createElement('img');
      avatar.src = `${folder(current.id)}avatar.webp`; avatar.alt = '';
      row.append(avatar);
    }
    const bubble = document.createElement('div');
    bubble.className = `bubble${thinking ? ' dots' : ''}`;
    bubble.textContent = text;
    row.append(bubble);
    log.append(row);
    log.scrollTop = log.scrollHeight;
    return row;
  }
  const voice = document.querySelector('#role-voice');
  const voiceButtons = document.querySelectorAll('[data-voice]');
  const lines = fetch('./voices/lines.json').then(response => response.json()).catch(() => ({}));
  let playback = 0;

  function setVoiceButtons(playing) {
    for (const button of voiceButtons) {
      button.textContent = playing ? '停止播放' : '试听问候';
      button.setAttribute('aria-pressed', String(playing));
    }
  }
  function stopVoice() {
    playback++;
    voice.pause();
    setVoiceButtons(false);
  }
  voice.addEventListener('ended', () => setVoiceButtons(false));
  async function playGreeting() {
    authorChat.stopReading();
    if (!voice.paused) { stopVoice(); return; }
    const attempt = ++playback;
    const id = current.id;
    voice.src = new URL('./voices/' + id + '.wav?v=qwen2', location.href).href;
    try {
      // Start from the tap, before awaiting anything, including the transcript.
      const started = voice.play();
      setVoiceButtons(true);
      await started;
      const text = (await lines)[id];
      if (attempt === playback && text) {
        addMessage(text);
        fullscreenBubble.textContent = text;
      }
    } catch (_) {
      if (attempt !== playback) return;
      stopVoice();
      const message = '问候语加载失败，请再点一次试听。';
      addMessage(message);
      fullscreenBubble.textContent = message;
    }
  }
  voiceButtons.forEach(button => button.addEventListener('click', playGreeting));
  window.addEventListener('pagehide', stopVoice);
  document.addEventListener('visibilitychange', () => { if (document.hidden) stopVoice(); });

  const authorChat = window.createLivLivChat({
    role: () => current.id, addMessage, stopGreeting: stopVoice,
    presentReply: text => { fullscreenBubble.textContent = text; },
  });
  function act(key) {
    if (timer) clearTimeout(timer);
    dots?.remove();
    const action = key === 'sleep' && sleeping ? 'wake' : key;
    const reply = replies[action];
    if (!reply) return;
    addMessage(names[action], true);
    dots = addMessage('···', false, true);
    fullscreenBubble.textContent = '···';
    timer = setTimeout(() => {
      dots?.remove(); dots = null; timer = null;
      sleeping = action === 'sleep';
      sleepButtons.forEach(button => { button.textContent = sleeping ? '醒醒啦' : '睡一会'; });
      sendPose(reply.pose, reply.expression || null);
      addMessage(reply.text);
      fullscreenBubble.textContent = reply.text;
    }, 350);
  }
  document.querySelector('.actions').addEventListener('click', event => {
    const button = event.target.closest('button[data-action]');
    if (button) act(button.dataset.action);
  });
  document.querySelector('.fullscreen-actions').addEventListener('click', event => {
    const button = event.target.closest('button[data-action]');
    if (button) act(button.dataset.action);
  });
  function selectCharacter(character) {
    authorChat.reset();
    stopVoice();
    if (timer) clearTimeout(timer);
    timer = null;
    dots?.remove(); dots = null;
    sleeping = false;
    sleepButtons.forEach(button => { button.textContent = '睡一会'; });
    current = character;
    pending = {pose: 'wave', expression: null};
    frame.contentWindow.location.replace(frameUrl(character.id));
    document.documentElement.dataset.theme = character.theme;
    document.querySelector('#character-name').textContent = character.name;
    document.querySelector('#character-tagline').textContent = character.tagline;
    document.querySelector('#chat-name').textContent = character.name;
    document.querySelector('#portrait').src = `${folder(character.id)}avatar.webp`;
    document.querySelector('.character').setAttribute('aria-label', `${character.name} 角色预览`);
    document.querySelector('.chat').setAttribute('aria-label', `${character.name} 互动聊天`);
    document.title = `LivLiv 互动空间 · ${character.name}`;
    const credit = document.querySelector('#credit');
    if (character.id === 'p01' || character.id === 'p02') {
      credit.innerHTML = '角色：上善无形、ZipZipPipe · CC BY-NC-SA 4.0<br>模型：LivLiv，AI 辅助制作';
    } else if (character.id === 'p03') {
      credit.innerHTML = 'Pen 基于贱兔死顺盖创作的角色；LivLiv 不授予角色使用权<br>模型：LivLiv，AI 辅助制作';
    } else {
      credit.innerHTML = '角色：LivLiv（livliv.ai） · AI 辅助制作<br>许可说明见 LivLiv 角色素材';
    }
    log.replaceChildren();
    const intro = document.createElement('div');
    intro.className = 'intro';
    intro.textContent = `选择下面的互动，和 ${character.name} 打个招呼吧`;
    log.append(intro);
    const greeting = `你好，我是 ${character.name}。今天也一起加油吧！ (｡•ᴗ•｡)`;
    addMessage(greeting);
    fullscreenBubble.textContent = greeting;
    for (const item of grid.querySelectorAll('button')) {
      item.setAttribute('aria-pressed', String(item.dataset.id === character.id));
    }
    try { localStorage.setItem('livliv-preview-character', character.id); } catch (_) {}
  }
  let dialogOpener = null;
  function openPicker(event) {
    dialogOpener = event.currentTarget;
    if (typeof dialog.showModal === 'function') {
      dialog.showModal();
    } else {
      dialog.setAttribute('open', '');
      dialog.classList.add('fallback-dialog');
      grid.querySelector('[aria-pressed="true"]')?.focus();
    }
  }
  function closePicker() {
    if (typeof dialog.close === 'function') dialog.close();
    else {
      dialog.removeAttribute('open');
      dialog.classList.remove('fallback-dialog');
    }
    dialogOpener?.focus();
  }
  for (const character of characters) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'character-option';
    button.dataset.id = character.id;
    button.dataset.theme = character.theme;
    button.setAttribute('aria-pressed', String(character.id === current.id));
    const image = document.createElement('img');
    image.src = `${folder(character.id)}avatar.webp`;
    image.alt = '';
    image.loading = 'lazy';
    const label = document.createElement('span');
    label.textContent = character.name;
    button.append(image, label);
    button.addEventListener('click', () => { selectCharacter(character); closePicker(); });
    grid.append(button);
  }
  document.querySelector('#choose-character').addEventListener('click', openPicker);
  document.querySelector('#fullscreen-choose').addEventListener('click', openPicker);
  document.querySelector('#close-dialog').addEventListener('click', closePicker);
  let saved = null;
  try { saved = localStorage.getItem('livliv-preview-character'); } catch (_) {}
  const remembered = characters.find(character => character.id === saved);
  if (remembered && remembered.id !== 'p01') selectCharacter(remembered);
  const fullscreenArea = document.querySelector('.conversation');
  const fullscreenButton = document.querySelector('#fullscreen-character');
  let fullscreenAttempt = 0;
  function updateFullscreenButton() {
    const expanded = document.fullscreenElement === fullscreenArea || fullscreenArea.classList.contains('is-expanded');
    const slot = document.querySelector(expanded ? '#fullscreen-author-slot' : '#author-slot');
    const panel = document.querySelector('#author-panel');
    if (panel.parentElement !== slot) slot.append(panel);
    fullscreenButton.setAttribute('aria-label', expanded ? '退出人物全屏' : '全屏放大人物');
    fullscreenButton.setAttribute('title', expanded ? '退出全屏' : '全屏放大人物');
    fullscreenButton.setAttribute('aria-pressed', String(expanded));
  }
  fullscreenButton.addEventListener('click', async () => {
    if (document.fullscreenElement === fullscreenArea) {
      fullscreenAttempt++;
      await document.exitFullscreen();
    } else if (fullscreenArea.classList.contains('is-expanded')) {
      fullscreenAttempt++;
      fullscreenArea.classList.remove('is-expanded');
      document.body.classList.remove('character-expanded');
    } else {
      const attempt = ++fullscreenAttempt;
      // Show the viewport-sized layout immediately even when the browser's
      // fullscreen request is slow, unavailable, or denied.
      fullscreenArea.classList.add('is-expanded');
      document.body.classList.add('character-expanded');
      updateFullscreenButton();
      try {
        // The simulated phone is kept inside its frame; actual browsers use
        // native fullscreen where available, with a viewport fallback on iOS.
        if (new URLSearchParams(location.search).has('phone-preview') || !fullscreenArea.requestFullscreen) throw new Error('Use viewport fullscreen');
        await fullscreenArea.requestFullscreen();
        if (attempt !== fullscreenAttempt && document.fullscreenElement === fullscreenArea) {
          await document.exitFullscreen();
        } else if (document.fullscreenElement === fullscreenArea) {
          fullscreenArea.classList.remove('is-expanded');
          document.body.classList.remove('character-expanded');
        }
      } catch (_) { /* Keep the viewport-sized layout. */ }
    }
    updateFullscreenButton();
  });
  document.addEventListener('fullscreenchange', updateFullscreenButton);
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && dialog.hasAttribute('open')) {
      if (dialog.classList.contains('fallback-dialog')) closePicker();
      return;
    }
    if (event.key === 'Escape' && fullscreenArea.classList.contains('is-expanded')) {
      fullscreenAttempt++;
      fullscreenArea.classList.remove('is-expanded');
      document.body.classList.remove('character-expanded');
      updateFullscreenButton();
    }
  });
  document.querySelector('#close').addEventListener('click', () => {
    window.close();
    // A directly opened tab may not be script-closable. Do not use back():
    // it can navigate only the iframe, leaving the name and avatar unchanged.
    if (!window.closed) window.location.assign(new URL('../', location.href).href);
  });
})();
