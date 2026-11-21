window.createLivLivChat = function ({role, addMessage, stopGreeting, presentReply}) {
  const form = document.querySelector('#author-form');
  const input = document.querySelector('#author-input');
  const send = document.querySelector('#author-send');
  const login = document.querySelector('#author-login');
  const status = document.querySelector('#author-status');
  const button = document.querySelector('#reply-play');
  const audio = document.querySelector('#reply-audio');
  const endpoint = '/api/v1/assistant/';
  let allowed = false, history = [], latest = null;
  let accessVersion = 0, chat = null, reading = null, audioUrl = null;
  let cached = new Map();

  async function call(path, data, signal) {
    const response = await fetch(endpoint + path, {
      method: data ? 'POST' : 'GET', cache: 'no-store', credentials: 'same-origin', signal,
      ...(data ? {headers: {'Content-Type':'application/json'}, body:JSON.stringify(data)} : {})
    });
    const value = await response.json();
    if (!response.ok) {
      const error = new Error(value.error || '请求失败，请重试。');
      error.status = response.status;
      throw error;
    }
    return value;
  }
  // Use the send gesture to activate this media element on mobile Safari.
  function activateAudio() {
    audio.src = 'data:audio/wav;base64,UklGRlQAAABXQVZFZm10IBAAAAABAAEAwF0AAIC7AAACABAAZGF0YTAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    audio.play().catch(() => {});
  }
  function releaseAudio() {
    audio.pause();
    audio.removeAttribute('src');
    audio.load();
    if (audioUrl) URL.revokeObjectURL(audioUrl);
    audioUrl = null;
  }
  function stopReading() {
    if (!reading) return;
    reading.abort();
    reading = null;
    releaseAudio();
    button.textContent = '朗读回复';
    status.textContent = '';
  }
  function reset() {
    chat?.abort(); chat = null;
    stopReading();
    history = []; latest = null; cached = new Map();
    send.disabled = false; input.value = ''; button.hidden = true;
    status.textContent = '';
  }
  async function updateAccess() {
    const version = ++accessVersion;
    try {
      const data = await call('livliv/access');
      if (version !== accessVersion) return;
      if (allowed && !data.allowed) {
        reset();
        document.querySelector('#messages').replaceChildren();
        presentReply('');
      }
      allowed = data.allowed === true;
    } catch (_) {
      if (version !== accessVersion) return;
      return; // The server rechecks every send and every audio request.
    }
    form.hidden = !allowed; login.hidden = allowed;
  }

  async function partBlob(message, part, signal, clips) {
    if (clips.has(part)) return clips.get(part);
    const until = Date.now() + 300000;
    while (!signal.aborted && Date.now() < until) {
      const result = await call('livliv/voice', {role: message.speech.role, reply: message.reply,
        ticket: message.speech.ticket, part}, signal);
      if (result.status === 'ready') {
        const bytes = Uint8Array.from(atob(result.audio), c => c.charCodeAt(0));
        const blob = new Blob([bytes], {type:'audio/wav'});
        clips.set(part, blob);
        return blob;
      }
      if (result.status !== 'pending') throw new Error('这段语音暂未生成，请点朗读重试。');
      await new Promise(done => setTimeout(done, 1500));
    }
    throw new Error('语音生成超时，请点朗读重试。');
  }

  function waitForEnd(signal) {
    return new Promise((resolve, reject) => {
      function cleanup() {
        audio.removeEventListener('ended', end);
        audio.removeEventListener('error', fail);
        signal.removeEventListener('abort', fail);
      }
      function end() { cleanup(); resolve(); }
      function fail() { cleanup(); reject(new Error('播放中断，可重新朗读。')); }
      audio.addEventListener('ended', end);
      audio.addEventListener('error', fail);
      signal.addEventListener('abort', fail, {once:true});
      audio.play().catch(error => { cleanup(); reject(error); });
    });
  }
  async function read(message) {
    stopReading(); stopGreeting();
    const controller = new AbortController(), signal = controller.signal;
    reading = controller;
    button.hidden = false; button.textContent = '停止朗读';
    try {
      for (let i=0; i<message.speech.parts; i++) {
        status.textContent = '正在准备角色声音…';
        const blob = cached.get(i) || await partBlob(message, i, signal, cached);
        if (signal.aborted || message !== latest) return;
        if (audioUrl) URL.revokeObjectURL(audioUrl);
        audioUrl = URL.createObjectURL(blob); audio.src = audioUrl;
        status.textContent = '正在朗读';
        const ended = waitForEnd(signal);
        // Prepare the next clause while the current one plays.
        if (i+1 < message.speech.parts) {
          await Promise.all([ended, partBlob(message, i+1, signal, cached)]);
        } else await ended;
      }
      if (!signal.aborted) status.textContent = '';
    } catch (error) {
      if (!signal.aborted) status.textContent = error.name === 'NotAllowedError'
        ? '点击「朗读回复」播放角色声音。' : (error.message || '语音暂时不可用。');
    } finally {
      if (reading === controller) {
        controller.abort(); reading = null; releaseAudio(); button.textContent = '朗读回复';
      }
    }
  }
  form.addEventListener('submit', async event => {
    event.preventDefault();
    const message = input.value.trim();
    if (!allowed || chat || !message) return;
    stopReading(); stopGreeting();
    activateAudio(); latest = null; cached = new Map(); button.hidden = true;
    const selected = role(), controller = new AbortController();
    chat = controller; send.disabled = true;
    const outgoing = addMessage(message, true); input.value = '';
    status.textContent = '正在回复…';
    try {
      const result = await call('chat', {companion:'livliv:'+selected, message, history}, controller.signal);
      if (chat !== controller || selected !== role()) return;
      addMessage(result.reply); presentReply(result.reply);
      history = [...history, {role:'user',content:message},
        {role:'assistant',content:result.reply.slice(0,1000)}].slice(-6);
      status.textContent = '';
      if (result.speech?.role === selected && result.speech.parts > 0) {
        latest = result; read(result);
      }
    } catch (error) {
      if (chat !== controller) return;
      outgoing.remove();
      if (!input.value) input.value = message;
      status.textContent = error.message || '发送失败，请重试。';
      if (error.status === 403 || error.status === 401) updateAccess();
    } finally {
      if (chat === controller) {chat = null; send.disabled = false;}
    }
  });
  button.addEventListener('click', () => { if (reading) stopReading(); else if (latest) read(latest); });
  window.addEventListener('focus', updateAccess);
  window.addEventListener('storage', e => {
    if (!e.key || e.key === 'flutter.userId' || e.key === 'flutter.email') {
      reset(); document.querySelector('#messages').replaceChildren(); presentReply(''); updateAccess();
    }
  });
  window.addEventListener('pagehide', () => { reset(); });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) stopReading(); else updateAccess();
  });
  updateAccess();
  return {reset, stopReading};
};
