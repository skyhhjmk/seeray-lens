import { expect, test } from '@playwright/test';

const siteId = `srl_${'B'.repeat(32)}`;

test('published tracker uploads heatmap clicks at document coordinates before and after scrolling', async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 400 });
  await page.addInitScript((id) => localStorage.setItem(`seeray:${id}:consent`, 'granted'), siteId);

  const heatmapBatches = [];
  page.on('request', (request) => {
    if (new URL(request.url()).pathname === '/api/v1/collect/heatmaps' && request.postData()) {
      heatmapBatches.push(JSON.parse(request.postData()));
    }
  });

  await page.goto('/heatmap-fixture');
  await page.evaluate(() => window.SeeRay.ready());

  await page.locator('#heatmap-top').click();
  await page.evaluate(() => window.scrollTo(0, 650));
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(650);
  await page.locator('#heatmap-bottom').click();

  const expectedCoordinates = await page.evaluate(() => ['heatmap-top', 'heatmap-bottom'].map((id) => {
    const rect = globalThis.document.getElementById(id).getBoundingClientRect();
    return {
      x: rect.left + window.scrollX + rect.width / 2,
      y: rect.top + window.scrollY + rect.height / 2,
    };
  }));

  await expect.poll(
    () => heatmapBatches.flatMap((batch) => batch.events).filter((event) => event.type === 'click').length,
    { timeout: 5_000 },
  ).toBe(2);

  const clicks = heatmapBatches.flatMap((batch) => batch.events).filter((event) => event.type === 'click');
  expect(clicks.map(({ x, y }) => ({ x, y }))).toEqual(expectedCoordinates.map(({ x, y }) => ({
    x: expect.closeTo(x, 0),
    y: expect.closeTo(y, 0),
  })));
  expect(clicks[0].viewportHeight).toBe(400);
  expect(clicks[0].contentHeight).toBeGreaterThan(clicks[0].viewportHeight);
  expect(clicks[0].url).toBe('http://127.0.0.1:4173/heatmap-fixture');
  expect(clicks[0].instanceId).toBe(clicks[1].instanceId);
});
