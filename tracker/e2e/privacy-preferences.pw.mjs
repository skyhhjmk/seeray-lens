import { expect, test } from '@playwright/test';

const siteId = `srl_${'A'.repeat(32)}`;

test('hosted preferences control consent across origins and persist allow/withdraw choices', async ({ page }) => {
  const collectorRequests = [];
  page.on('request', (request) => {
    if (new URL(request.url()).pathname === '/api/v1/collect') collectorRequests.push(request);
  });

  const frameResponsePromise = page.waitForResponse((response) => response.url().includes('/privacy/preferences?siteId='));
  await page.goto('/fixture');
  const frameResponse = await frameResponsePromise;
  const frame = page.frameLocator('iframe[data-seeray-privacy]');
  expect(frameResponse.status()).toBe(200);
  expect(frameResponse.headers()['content-security-policy']).toContain('frame-ancestors *');
  expect(new URL(page.url()).origin).not.toBe(new URL(frameResponse.url()).origin);

  const status = frame.getByRole('status');
  await expect(status).toHaveText('尚未记录选择。分析数据会等待你的决定。');
  await expect(frame.getByRole('button', { name: '允许分析' })).toBeEnabled();
  await expect(frame.getByRole('button', { name: '退出统计' })).toBeEnabled();
  await expect.poll(() => page.evaluate((id) => localStorage.getItem(`seeray:${id}:visitor_id`), siteId)).toBeNull();
  expect(collectorRequests).toHaveLength(0);

  await frame.getByRole('button', { name: '允许分析' }).click();
  await expect(status).toHaveText('此浏览器已允许匿名分析。');
  await expect.poll(() => page.evaluate((id) => localStorage.getItem(`seeray:${id}:consent`), siteId)).toBe('granted');
  await expect.poll(() => page.evaluate((id) => localStorage.getItem(`seeray:${id}:visitor_id`), siteId)).not.toBeNull();

  await page.evaluate(() => window.SeeRay.track('privacy_e2e_after_grant'));
  await expect.poll(() => collectorRequests.length, { timeout: 5_000 }).toBeGreaterThan(0);
  const allowedBatch = JSON.parse(collectorRequests[0].postData());
  expect(allowedBatch.siteId).toBe(siteId);
  expect(allowedBatch.events.some((event) => event.type === 'privacy_e2e_after_grant')).toBe(true);

  await page.reload();
  const reloadedFrame = page.frameLocator('iframe[data-seeray-privacy]');
  await expect(reloadedFrame.getByRole('status')).toHaveText('此浏览器已允许匿名分析。');
  await expect.poll(() => page.evaluate((id) => localStorage.getItem(`seeray:${id}:visitor_id`), siteId)).not.toBeNull();

  await reloadedFrame.getByRole('button', { name: '退出统计' }).click();
  await expect(reloadedFrame.getByRole('status')).toHaveText('此浏览器已退出匿名分析。');
  await expect.poll(() => page.evaluate((id) => localStorage.getItem(`seeray:${id}:consent`), siteId)).toBe('denied');
  await expect.poll(() => page.evaluate((id) => localStorage.getItem(`seeray:${id}:visitor_id`), siteId)).toBeNull();
  expect(await page.evaluate((id) => sessionStorage.getItem(`seeray:${id}:session_id`), siteId)).toBeNull();

  const collectedBeforeDeniedAction = collectorRequests.length;
  await page.evaluate(() => window.SeeRay.track('privacy_e2e_after_withdrawal'));
  await page.waitForTimeout(2_300);
  expect(collectorRequests).toHaveLength(collectedBeforeDeniedAction);

  await page.reload();
  await expect(page.frameLocator('iframe[data-seeray-privacy]').getByRole('status')).toHaveText('此浏览器已退出匿名分析。');
  await expect.poll(() => page.evaluate((id) => localStorage.getItem(`seeray:${id}:visitor_id`), siteId)).toBeNull();
});
