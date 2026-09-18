import { expect, test } from '@playwright/test';

const optedInSiteId = `srl_${'C'.repeat(32)}`;
const defaultOffSiteId = `srl_${'D'.repeat(32)}`;

const throwUncaughtError = async (page) => {
  const pageError = page.waitForEvent('pageerror');
  await page.evaluate(() => {
    globalThis.setTimeout(() => {
      throw new Error('Login for private@example.test at https://app.example.test/accounts/12345678?token=verysecretcredential');
    }, 0);
  });
  await pageError;
};

const listenForCollection = (page) => {
  const events = [];
  page.on('request', (request) => {
    if (request.method() !== 'POST' || new URL(request.url()).pathname !== '/api/v1/collect') return;
    const body = request.postData();
    if (body) events.push(...JSON.parse(body).events);
  });
  return events;
};

test('published tracker captures only consented opt-in browser crashes with redacted anonymous context', async ({ page }) => {
  const events = listenForCollection(page);
  await page.goto('/crash-fixture?auth=query-secret');

  await throwUncaughtError(page);
  await page.evaluate(() => window.SeeRay.flush());
  expect(events.filter((event) => event.type === 'client_error')).toHaveLength(0);

  await page.evaluate((siteId) => window.SeeRay.setConsent(true, siteId), optedInSiteId);
  await throwUncaughtError(page);
  await page.evaluate(() => window.SeeRay.flush());

  await expect.poll(() => events.filter((event) => event.type === 'client_error').length).toBe(1);
  const report = events.find((event) => event.type === 'client_error');
  expect(report).toMatchObject({
    action: 'javascript',
    category: 'error',
    name: 'Error',
    url: 'http://127.0.0.1:4173/crash-fixture',
    title: '',
    referrer: '',
    properties: { releaseId: 'web-e2e.1' },
  });
  expect(report).not.toHaveProperty('visitorId');
  expect(report).not.toHaveProperty('sessionId');
  expect(report).not.toHaveProperty('userId');
  expect(report.properties.message).toContain('<email>');
  expect(report.properties.message).toContain('<url>');
  expect(report.url).not.toContain('?');
  expect(JSON.stringify(report)).not.toContain('private@example.test');
  expect(JSON.stringify(report)).not.toContain('12345678');
  expect(JSON.stringify(report)).not.toContain('verysecretcredential');
});

test('published tracker keeps browser crash capture disabled without the explicit script flag', async ({ page }) => {
  const events = listenForCollection(page);
  await page.goto('/crash-default-off-fixture');
  await page.evaluate((siteId) => window.SeeRay.setConsent(true, siteId), defaultOffSiteId);
  await throwUncaughtError(page);
  await page.evaluate(() => window.SeeRay.flush());

  expect(events.filter((event) => event.type === 'client_error')).toHaveLength(0);
});
