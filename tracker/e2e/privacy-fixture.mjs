import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const repository = resolve(directory, '../..');
const trackingId = `srl_${'A'.repeat(32)}`;
const customerOrigin = 'http://127.0.0.1:4173';
const analyticsOrigin = 'http://127.0.0.1:4174';
const asset = async (path) => readFile(resolve(repository, path));
const tracker = await asset('server/src/main/resources/META-INF/resources/tracker.js');
const preferencesHtml = (await asset('server/src/main/resources/privacy/preferences.html')).toString('utf8');
const preferencesJs = await asset('server/src/main/resources/META-INF/resources/privacy/preferences.js');
const preferencesCss = await asset('server/src/main/resources/META-INF/resources/privacy/preferences.css');

const customerPage = `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Customer fixture</title></head>
<body>
  <main><h1>Customer site</h1><p>Privacy settings are supplied by SeeRay.</p></main>
  <script src="${analyticsOrigin}/tracker.js" data-site-id="${trackingId}" data-require-consent="true"></script>
  <iframe data-seeray-privacy title="Privacy preferences" src="${analyticsOrigin}/privacy/preferences?siteId=${trackingId}" width="100%" height="230"></iframe>
</body>
</html>`;

const customerServer = createServer((request, response) => {
  if (request.method === 'GET' && request.url === '/fixture') {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    response.end(customerPage);
    return;
  }
  response.writeHead(404).end();
});

const analyticsServer = createServer(async (request, response) => {
  response.setHeader('access-control-allow-origin', customerOrigin);
  response.setHeader('access-control-allow-methods', 'GET, POST, OPTIONS');
  response.setHeader('access-control-allow-headers', 'content-type');
  if (request.method === 'OPTIONS') {
    response.writeHead(204).end();
    return;
  }

  if (request.method === 'GET' && request.url === '/tracker.js') {
    response.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' }).end(tracker);
    return;
  }
  if (request.method === 'GET' && request.url === '/privacy/preferences.js') {
    response.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' }).end(preferencesJs);
    return;
  }
  if (request.method === 'GET' && request.url === '/privacy/preferences.css') {
    response.writeHead(200, { 'content-type': 'text/css; charset=utf-8' }).end(preferencesCss);
    return;
  }
  if (request.method === 'GET' && request.url?.startsWith('/privacy/preferences?')) {
    const url = new URL(request.url, analyticsOrigin);
    const requestedSite = url.searchParams.get('siteId');
    if (requestedSite !== trackingId) {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(200, {
      'content-type': 'text/html; charset=utf-8',
      'content-security-policy': "default-src 'none'; script-src 'self'; style-src 'self'; frame-ancestors *; base-uri 'none'; form-action 'none'",
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff',
      'cache-control': 'no-store',
    }).end(preferencesHtml.replace('__SEERAY_TRACKING_ID__', trackingId));
    return;
  }
  if (request.method === 'POST' && request.url === '/api/v1/collect') {
    request.resume();
    request.on('end', () => response.writeHead(202).end());
    return;
  }
  if (request.method === 'GET' && request.url?.startsWith('/api/v1/')) {
    response.writeHead(200, { 'content-type': 'application/json' }).end('[]');
    return;
  }
  response.writeHead(404).end();
});

await Promise.all([
  new Promise((resolveListen, reject) => {
    customerServer.once('error', reject);
    customerServer.listen(4173, '127.0.0.1', resolveListen);
  }),
  new Promise((resolveListen, reject) => {
    analyticsServer.once('error', reject);
    analyticsServer.listen(4174, '127.0.0.1', resolveListen);
  }),
]);

const close = () => {
  customerServer.close();
  analyticsServer.close();
};
process.once('SIGINT', close);
process.once('SIGTERM', close);
