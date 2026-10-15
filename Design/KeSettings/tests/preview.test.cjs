const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const json = name => JSON.parse(fs.readFileSync(path.join(root, 'spec', name + '.json')));
const motion = require('../motion.js');
const cfg = json('motion').drawer;

test('8 distinct routes have sample data and normalized placement', () => {
  const data = json('sample-data'), layout = json('layout');
  const ids = ['chat','visits','reminders','palette','notifications','privacy','updates','about'];
  assert.deepEqual(data.entries.map(e => e.id), ids);
  assert.deepEqual(layout.entries.map(e => e.id), ids);
  assert.equal(layout.drawer.widthRatio, .75);
  for (const e of layout.entries) {
    assert.ok(e.left >= 0 && e.left < 1 && e.top >= 0 && e.top < 1);
    assert.equal(data.entries.find(x => x.id === e.id).title.length, 2);
  }
});
test('four approved light papers and local decorative font', () => {
  const t = json('tokens');
  assert.deepEqual(Object.keys(t.palettes), ['mist','white','ivory','cream']);
  assert.equal(t.palettes.white.dayPaper, '#FAFCFD');
  assert.ok(fs.statSync(path.join(root,'assets/PinyonScript-Regular.ttf')).size > 10000);
  assert.ok(fs.existsSync(path.join(root,'assets/PinyonScript-Regular-OFL.txt')));
});
test('six alpha PNGs match actual manifest dimensions, contain provenance', () => {
  const assets = json('asset-provenance').assets;
  assert.equal(assets.length, 6);
  for (const asset of assets) {
    const b = fs.readFileSync(path.join(root,'assets',asset.file));
    assert.equal(b.readUInt32BE(0), 0x89504e47);
    assert.equal(b.readUInt32BE(16), asset.width);
    assert.equal(b.readUInt32BE(20), asset.height);
    assert.equal(b[25], 6, asset.file + ' must be RGBA');
    assert.ok(b.includes(Buffer.from('impeccable:prompt')));
    assert.equal(asset.scale, 3);
  }
});
test('drawer converges in both directions and remains finite at frame stalls', () => {
  for (const target of [0,1]) for (const dt of [1/120,1/60,.032,.2]) {
    let s = {position:1-target, velocity:0};
    for(let i=0;i<1200;i++) {
      s = motion.step(s.position,s.velocity,target,dt,cfg);
      assert.ok(Number.isFinite(s.position) && Number.isFinite(s.velocity));
    }
    assert.ok(Math.abs(s.position-target) < cfg.positionEpsilon);
    assert.ok(Math.abs(s.velocity) < cfg.velocityEpsilon);
  }
});
test('interrupted spring retains momentum and can reverse', () => {
  let s={position:0,velocity:0};
  for(let i=0;i<10;i++)s=motion.step(s.position,s.velocity,1,1/60,cfg);
  assert.ok(s.position>0 && s.velocity>0);
  for(let i=0;i<240;i++)s=motion.step(s.position,s.velocity,0,1/60,cfg);
  assert.ok(Math.abs(s.position)<cfg.positionEpsilon);
});
test('release projects direction, with static distance threshold', () => {
  assert.equal(motion.release(.2,0,cfg),0);
  assert.equal(motion.release(.8,0,cfg),1);
  assert.equal(motion.release(.3,2,cfg),1);
  assert.equal(motion.release(.7,-2,cfg),0);
  assert.equal(motion.clamp(-1),0);assert.equal(motion.clamp(2),1);
});
test('preview has no storage, service calls, permissions or external dependencies', () => {
  const js=fs.readFileSync(path.join(root,'app.js'),'utf8');
  assert.doesNotMatch(js,/localStorage|sessionStorage|indexedDB|Notification\.|requestPermission|navigator\.credentials|sendBeacon|WebSocket/);
  assert.doesNotMatch(js.replaceAll('http://www.w3.org/2000/svg',''),/https?:\/\//);
  assert.match(js,/base\.inert=true/);
  assert.match(js,/prefers-reduced-motion/);
  assert.match(js,/directoryScrollTop=scroll.scrollTop/);
  assert.match(js,/scrollIntoView\(\{block:'nearest'/);
});
