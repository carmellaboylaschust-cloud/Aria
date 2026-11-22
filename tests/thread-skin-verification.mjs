import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {verifySession, SKIN_VERSION} from '../engine/scripts/injector.mjs';

const require = createRequire(import.meta.url);
const {chromium} = require(process.env.ARIA_PLAYWRIGHT_MODULE || 'playwright');
const browser = await chromium.launch({channel: 'msedge', headless: true});

try {
  const page = await browser.newPage({viewport: {width: 1200, height: 800}});
  await page.setContent(`
    <style>
      body { margin: 0; }
      aside { position: fixed; width: 200px; height: 800px; }
      main { margin-left: 200px; width: 1000px; height: 800px; }
      .composer-surface-chrome { position: fixed; bottom: 20px; width: 600px; height: 90px; }
      #dream-skin-window-background, #dream-skin-window-background img,
      #dream-skin-window-background video { position: fixed; inset: 0; width: 100%; height: 100%; }
    </style>
    <div id="dream-skin-window-background" aria-hidden="true">
      <img data-dream-media="content" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='5' height='5'%3E%3Crect width='5' height='5' fill='blue'/%3E%3C/svg%3E">
    </div>
    <aside class="app-shell-left-panel">Sidebar</aside>
    <main data-app-shell-main-surface data-ds-part="main">
      <div data-ds-part="composer" class="composer-surface-chrome">Composer</div>
      <div role="dialog">Overlay</div>
    </main>`);
  await page.locator('img').evaluate(img => img.decode());
  await page.evaluate(version => {
    document.documentElement.dataset.dreamSkin = 'active';
    const styleSheet = new CSSStyleSheet();
    document.adoptedStyleSheets = [styleSheet];
    window.__CODEX_DREAM_SKIN_STATE__ = {
      version, themeId: 'fixture', revision: 'revision-one', styleMode: 'adopted', styleSheet,
      scope: {state: 'overlay', baseState: 'thread', level: 'L0', missingL1: ['header-tint']},
    };
  }, SKIN_VERSION);

  let windowState = 'normal';
  const session = {
    async send(method) {
      assert.ok(['Browser.getWindowForTarget', 'Browser.getWindowBounds'].includes(method));
      return {windowId: 1, bounds: {width: 1200, height: 800, windowState}};
    },
    evaluate: expression => page.evaluate(expression),
  };
  const verify = (theme = 'fixture', revision = 'revision-one') =>
    verifySession(session, 'fixture-page', theme, revision);
  const expectPass = async (pass, label) => assert.equal((await verify()).pass, pass, label);

  await expectPass(true, 'thread overlay with decoded theme and missing decorative header');
  assert.equal((await verify('other-theme')).pass, false, 'wrong theme');
  assert.equal((await verify('fixture', 'stale-revision')).pass, false, 'stale revision');
  windowState = 'minimized';
  await expectPass(false, 'minimized window');
  windowState = 'normal';
  await page.evaluate(() => Object.defineProperty(document, 'hidden', {configurable:true, value:true}));
  await expectPass(false, 'hidden document');
  await page.evaluate(() => delete document.hidden);
  await page.locator('aside').evaluate(el => el.hidden = true);
  await expectPass(false, 'missing sidebar');
  await page.locator('aside').evaluate(el => el.hidden = false);
  await page.locator('.composer-surface-chrome').evaluate(el => el.style.bottom = '-2px');
  await expectPass(false, 'clipped composer');
  await page.locator('.composer-surface-chrome').evaluate(el => el.style.removeProperty('bottom'));
  await page.evaluate(() => window.__CODEX_DREAM_SKIN_STATE__.scope.missingL1.push('shell-main'));
  await expectPass(false, 'missing required shell landmark as well');
  await page.evaluate(() => window.__CODEX_DREAM_SKIN_STATE__.scope.missingL1.pop());
  await page.locator('[data-dream-media]').evaluate(el => el.remove());
  await expectPass(false, 'absent background');
  await page.locator('#dream-skin-window-background').evaluate(host => {
    const video = document.createElement('video');
    video.dataset.dreamMedia = 'content';
    host.append(video);
    window.__CODEX_DREAM_SKIN_STATE__.mediaDecoded = true;
    Object.defineProperty(video, 'readyState', {configurable:true, value:2});
  });
  await expectPass(true, 'decoded video backdrop');
  await page.evaluate(() => window.__CODEX_DREAM_SKIN_STATE__.mediaError = 'fixture decode error');
  await expectPass(false, 'failed video backdrop');
  console.log('Thread verification passed: matching image/video and strict checks for hidden, broken and stale renderers.');
} finally {
  await browser.close();
}
