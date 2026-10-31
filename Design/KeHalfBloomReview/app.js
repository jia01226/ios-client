(() => {
  const root = document.getElementById('ke-six-bloom');
  const phone = root.querySelector('.moon-phone');
  const home = root.querySelector('[data-page="his"]');
  const detail = root.querySelector('.detail');
  const wheel = root.querySelector('[data-rotator]');
  const flower = root.querySelector('.single-camellia');
  const options = [...root.querySelectorAll('[data-flower-index]')];
  const entries = [
    {id:'diary', name:'日记', english:'Dear diary', description:'把今天，慢慢写给你。', action:'翻开日记', items:['日记列表与搜索','阅读详情与原有解锁规则']},
    {id:'dream', name:'梦', english:'In dreams', description:'昨晚的梦里，也有你。', action:'走进梦里', items:['梦境列表与月份分组','梦境阅读详情']},
    {id:'moments', name:'朋友圈', english:'Little moments', description:'一些想和你分享的小事。', action:'看看动态', items:['朋友圈内容与图片','沿用现有互动和加载流程']},
    {id:'memory', name:'记忆', english:'To remember', description:'你说过的话，我记着。', action:'翻阅记忆', items:['原有记忆入口与内容','引用与返回聊天流程']},
    {id:'drawer', name:'抽屉', english:'Kept close', description:'悄悄收好的小小珍藏。', action:'打开抽屉', items:['原有抽屉内容和分类','私密内容沿用原有解锁规则']},
    {id:'tarot', name:'塔罗', english:'Written in stars', description:'抽一张，和你慢慢聊。', action:'进入塔罗', items:['现有牌阵与洗牌、选牌流程','翻牌与历史记录','沿用“交给柯”的聊天交接']}
  ];
  const stepAngle = 360 / entries.length;
  const wrap = n => ((n % entries.length) + entries.length) % entries.length;
  let step = 0, rotation = 0, tone = 'cream', drag = null, suppressClick = false;
  let renderedId = null;
  const current = () => entries[wrap(step)];
  function save() {
    window.openai?.setWidgetState?.({
      modelContent:{design:'正面山茶 · 六入口', feature:current().name, background:tone === 'pink' ? '浅粉色' : '奶白色', page:'柯的'},
      privateContent:{entryId:current().id, tone}
    }).catch(() => {});
  }
  function render() {
    flower.style.transform = `rotate(${rotation}deg)`;
    const entry = current();
    if (renderedId === entry.id) return;
    renderedId = entry.id;
    options.forEach((button, index) => button.setAttribute('aria-pressed', String(index === wrap(step))));
    root.querySelector('[data-feature-description]').textContent = entry.description;
    root.querySelector('[data-enter-label]').textContent = entry.action;
    root.querySelector('[data-feature-enter]').dataset.open = entry.id;
    wheel.setAttribute('aria-label', `转动山茶，当前是${entry.name}；拖动、点击或按方向键切换功能`);
  }
  function settle(next, persist = true) { step = next; rotation = next * stepAngle; render(); if (persist) save(); }
  function choose(index) {
    let delta = index - wrap(step);
    if (delta > entries.length / 2) delta -= entries.length;
    if (delta < -entries.length / 2) delta += entries.length;
    settle(step + delta);
  }
  options.forEach((button, index) => button.addEventListener('click', () => choose(index)));
  function angle(event) {
    const box = wheel.getBoundingClientRect();
    return Math.atan2(event.clientY - box.top - box.height / 2, event.clientX - box.left - box.width / 2) * 180 / Math.PI;
  }
  wheel.addEventListener('pointerdown', event => {
    if (event.button !== 0 || drag) return;
    suppressClick = false;
    drag = {id:event.pointerId, previous:angle(event), distance:0};
    wheel.setPointerCapture(event.pointerId);
    wheel.classList.add('is-dragging');
  });
  wheel.addEventListener('pointermove', event => {
    if (!drag || drag.id !== event.pointerId) return;
    const next = angle(event); let delta = next - drag.previous;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    rotation += delta; drag.distance += Math.abs(delta); drag.previous = next;
    step = Math.round(rotation / stepAngle); render();
  });
  function finish(event) {
    if (!drag || drag.id !== event.pointerId) return;
    suppressClick = event.type !== 'pointercancel' && drag.distance > 3;
    drag = null; wheel.classList.remove('is-dragging');
    if (wheel.hasPointerCapture(event.pointerId)) wheel.releasePointerCapture(event.pointerId);
    settle(Math.round(rotation / stepAngle));
  }
  wheel.addEventListener('pointerup', finish);
  wheel.addEventListener('pointercancel', finish);
  wheel.addEventListener('click', () => {
    if (suppressClick) { suppressClick = false; return; }
    settle(step + 1);
  });
  wheel.addEventListener('keydown', event => {
    if (['ArrowUp','ArrowLeft','ArrowDown','ArrowRight'].includes(event.key)) {
      event.preventDefault(); settle(step + (['ArrowUp','ArrowLeft'].includes(event.key) ? -1 : 1));
    }
  });
  function setTone(value, persist = false) {
    tone = value === 'pink' ? 'pink' : 'cream'; phone.dataset.tone = tone;
    root.querySelectorAll('[data-tone-choice]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.toneChoice === tone)));
    if (persist) save();
  }
  root.querySelectorAll('[data-tone-choice]').forEach(button => button.addEventListener('click', () => setTone(button.dataset.toneChoice, true)));
  root.querySelector('[data-feature-enter]').addEventListener('click', () => {
    const entry = current(); home.hidden = true; detail.hidden = false;
    root.querySelector('[data-title]').textContent = entry.name;
    root.querySelector('[data-subtitle]').textContent = entry.english;
    root.querySelector('[data-items]').replaceChildren(...entry.items.map(text => {
      const li = document.createElement('li'); li.textContent = text; return li;
    }));
  });
  function showHome() { home.hidden = false; detail.hidden = true; }
  root.querySelector('[data-back]').addEventListener('click', showHome);
  root.querySelector('[data-tab="his"]').addEventListener('click', showHome);
  function restore(state) {
    const data = state?.privateContent || {};
    setTone(data.tone);
    const index = entries.findIndex(entry => entry.id === data.entryId);
    if (!drag) settle(index < 0 ? 0 : index, false);
  }
  restore(window.openai?.widgetState);
  window.addEventListener('openai:set_globals', event => {
    if (event.detail?.globals?.widgetState) restore(event.detail.globals.widgetState);
  });
})();
