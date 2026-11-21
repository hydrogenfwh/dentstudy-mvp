import { Player } from './dist/index.js';

const canvas = document.querySelector('#stage');
const cover = document.querySelector('#cover');
const error = document.querySelector('#error');
let player = null;
let ready = false;
let sleeping = false;
let pending = {pose: 'wave', expression: null};
const availableModels = new Set(['char06', 'char07', 'd01', 'd02', 'd03', 'd03ft', 'k01', 'k02', 'p01', 'p02', 'p03', 'q02', 'q03', 's01', 'v04', 'v05', 'v06', 'v07', 'w01']);
const params = new URLSearchParams(location.search);
let requestedModel = params.get('model');
if (params.has('follow')) {
  try { requestedModel = localStorage.getItem('livliv-preview-character'); } catch (_) {}
  window.addEventListener('storage', event => {
    if (event.key === 'livliv-preview-character' && availableModels.has(event.newValue) && event.newValue !== modelId) location.reload();
  });
}
const modelId = availableModels.has(requestedModel) ? requestedModel : 'p01';
const modelPath = modelId === 'p01' ? './p01/' : `./library/${modelId}/`;
cover.src = `${modelPath}cover.webp`;

function applyPose(pose, expression = null) {
  pending = {pose, expression};
  if (!ready) return;
  document.documentElement.dataset.pose = pose;
  const wantSleep = pose === 'sleep';
  if (sleeping !== wantSleep) {
    player.act('away');
    sleeping = wantSleep;
  }
  if (wantSleep) {
    player.setExpression(null);
  } else if (pose === 'praise') {
    player.setExpression('smile');
    player.act('hop');
  } else if (pose === 'happy') {
    player.setExpression('smile');
    player.act('shy');
  } else if (pose === 'pout') {
    player.setExpression(null);
    player.act('tilt');
  } else {
    player.setExpression(null);
    if (pose === 'wave' && !expression) player.act('nod');
  }
  if (!wantSleep && ['angry', 'sad', 'shy'].includes(expression)) {
    if (player.setExpression(expression)) {
      if (expression === 'shy') player.act('shy');
      if (expression === 'sad') player.act('tilt');
      if (expression === 'angry') player.act('shake');
      document.documentElement.dataset.expression = expression;
    }
  } else {
    document.documentElement.dataset.expression = '';
  }
}

window.addEventListener('message', (event) => {
  if (event.origin !== location.origin || event.source !== window.parent) return;
  let data;
  try { data = JSON.parse(event.data); } catch (_) { return; }
  if (data?.type === 'dentstudy-livliv-gaze' && ready && !sleeping) {
    if (data.reset) {
      player.lookAt(null);
      document.documentElement.dataset.gaze = 'rest';
    } else if (Number.isFinite(data.x) && Number.isFinite(data.y)) {
      player.lookAt(data.x, data.y);
      document.documentElement.dataset.gaze = `${data.x.toFixed(2)},${data.y.toFixed(2)}`;
    }
    return;
  }
  if (data?.type === 'dentstudy-livliv-pose' &&
      ['wave', 'happy', 'praise', 'sleep', 'pout', 'thinking', 'neutral'].includes(data.pose)) {
    applyPose(data.pose, data.expression);
  }
});

try {
  if (!Player.isSupported()) throw new Error('WebGL2 unavailable');
  player = new Player(canvas, { followPointer: false, maxPixelRatio: 1.5 });
  await player.load(modelPath);
  ready = true;
  document.documentElement.dataset.playerReady = 'true';
  applyPose(pending.pose, pending.expression);
  cover.style.display = 'none';
} catch (e) {
  console.error('LivLiv preview failed:', e);
  if (!cover.complete || !cover.naturalWidth) error.style.display = 'grid';
}
window.addEventListener('pagehide', () => player?.dispose(), { once: true });
