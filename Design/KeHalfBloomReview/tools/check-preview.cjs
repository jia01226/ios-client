const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require('playwright');

(async () => {
  const root = path.resolve(__dirname, '..');
  const source = fs.readFileSync(path.join(root, 'source-fragment.html'), 'utf8');
  const script = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
  assert(source.includes(script), 'Source and app.js must agree');
  assert(Buffer.byteLength(source) < 1000000);
  const browser = await chromium.launch({headless:true, channel:'chrome'});
  try {
    const page = await browser.newPage({viewport:{width:736,height:1100}, deviceScaleFactor:1});
    const errors = [], requests = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('request', r => { if (/^https?:/.test(r.url())) requests.push(r.url()); });
    await page.setContent(fs.readFileSync(path.join(root, 'preview-standalone.html'), 'utf8'));
    const ui = page.frameLocator('iframe');
    await ui.locator('.single-camellia').evaluate(img => img.decode());
    const ids = ['diary','dream','moments','memory','drawer','tarot'];
    const names = ['日记','梦','朋友圈','记忆','抽屉','塔罗'];
    for (let i = 0; i < ids.length; i++) {
      await ui.locator(`[data-flower-index="${i}"]`).click();
      assert.equal(await ui.locator('[data-feature-enter]').getAttribute('data-open'), ids[i]);
      assert.equal(await ui.locator('[data-flower-index][aria-pressed="true"]').count(), 1);
      const menu = await ui.locator('.petal-menu').boundingBox();
      const summary = await ui.locator('.petal-selected').boundingBox();
      assert(menu.y + menu.height <= summary.y, 'Menu and selected summary must not overlap');
      await page.waitForTimeout(700);
      await ui.locator('.moon-phone').screenshot({path:path.join(root,'screenshots',`${i+1}-${ids[i]}.png`)});
      await ui.locator('[data-feature-enter]').click();
      assert.equal(await ui.locator('[data-title]').textContent(), names[i]);
      assert(await ui.locator('.detail').isVisible());
      await ui.locator('[data-back]').click();
      assert.equal(await ui.locator('[data-feature-enter]').getAttribute('data-open'), ids[i]);
    }
    await ui.locator('[data-flower-index="0"]').click();
    await page.waitForTimeout(700);
    const box = await ui.locator('[data-rotator]').boundingBox();
    const cx = box.x + box.width / 2, cy = box.y + box.height / 2;
    await page.mouse.move(cx-150, cy-130); await page.mouse.down();
    await page.mouse.move(cx-150, cy+130, {steps:14}); await page.mouse.up();
    assert.equal(await ui.locator('[data-feature-enter]').getAttribute('data-open'), 'tarot');
    await ui.locator('[data-rotator]').press('ArrowDown');
    assert.equal(await ui.locator('[data-feature-enter]').getAttribute('data-open'), 'diary');
    for(let i=0;i<12;i++) await ui.locator('[data-rotator]').press('ArrowDown');
    assert.equal(await ui.locator('[data-feature-enter]').getAttribute('data-open'), 'diary');
    for(let i=0;i<12;i++) await ui.locator('[data-rotator]').press('ArrowUp');
    assert.equal(await ui.locator('[data-feature-enter]').getAttribute('data-open'), 'diary');
    for(const width of [320,390,430]) {
      await page.setViewportSize({width,height:1100});
      const phone = await ui.locator('.moon-phone').boundingBox();
      const buttons = await ui.locator('[data-flower-index]').all();
      let previousBottom = 0;
      for(const button of buttons) {
        const rect = await button.boundingBox();
        assert(rect.width >= 44 && rect.height >= 44);
        assert(rect.x >= phone.x && rect.x + rect.width <= phone.x + phone.width + 1);
        assert(rect.y >= previousBottom); previousBottom = rect.y + rect.height;
      }
      assert(await ui.locator('body').evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      await page.waitForTimeout(700);
      await ui.locator('.moon-phone').screenshot({path:path.join(root,'screenshots',`width-${width}.png`)});
    }
    await ui.locator('[data-tone-choice="pink"]').click();
    assert.equal(await ui.locator('.moon-phone').getAttribute('data-tone'), 'pink');
    await ui.locator('.moon-phone').screenshot({path:path.join(root,'screenshots','pink.png')});
    await page.emulateMedia({reducedMotion:'reduce'});
    assert.equal(await ui.locator('.single-camellia').evaluate(el => getComputedStyle(el).transitionDuration), '0s');
    assert.equal(errors.length, 0, errors.join('\n'));
    assert.equal(requests.length, 0, 'Preview should not request external network resources');
    const result = {
      checkedAt:new Date().toISOString(), environment:'Desktop Chrome / Playwright, headless',
      passed:['six menu-to-route mappings','detail and return preserve selection','drag snaps to tarot without extra click','keyboard wraps in both directions for two revolutions','320/390/430 viewport widths without document overflow','44px menu targets without overlap','pink theme','reduced motion','no JavaScript errors','no external requests'],
      notVerified:['native SwiftUI implementation','iPhone touch feel and performance','VoiceOver on iOS','native Dynamic Type','real APIs, authentication, locked content and tarot handoff'],
      errors
    };
    fs.writeFileSync(path.join(root,'verification.json'), JSON.stringify(result,null,2)+'\n');
    console.log(JSON.stringify(result));
  } finally { await browser.close(); }
})().catch(e => {console.error(e);process.exitCode=1;});
