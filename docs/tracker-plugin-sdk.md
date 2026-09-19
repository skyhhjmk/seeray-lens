# Tracker client plugin SDK

The browser tracker exposes a small, local plugin API for product teams that need to react to measurement lifecycle events. Plugins are supplied by the site application through `TrackerOptions.plugins` or `tracker.use(plugin)`; SeeRay Lens never downloads or executes plugin code.

```ts
import { init } from '@seeray/lens-tracker';

const tracker = init({ siteId: 'YOUR_SITE_ID' });
tracker.use({
  name: 'checkout.audit',
  version: '1.0.0',
  setup(context) {
    return context.on('track', event => {
      if (event.type === 'purchase') {
        console.info('Purchase observed', event.name);
      }
    });
  },
});
```

Supported hooks are `track`, `consent`, and `navigation`. Track hook payloads contain the event type, event ID, timestamp, page metadata, category/action/name, duration and explicitly supplied properties. Visitor IDs, session IDs, user IDs and device context are intentionally excluded from plugin payloads. A plugin can call `context.track()` to emit a normal event and can return a cleanup function from `setup()`.

Plugin names use lowercase characters, digits, dots, underscores and hyphens. A throwing plugin is isolated so it cannot interrupt analytics collection. The tracker package currently exposes this API as version `0.9.0`; the generated browser asset is published from the same source.
