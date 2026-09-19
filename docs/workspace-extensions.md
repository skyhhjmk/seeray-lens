# Workspace extensions

SeeRay Lens extensions are registered per workspace as outbound HTTPS webhooks. The control plane stores the extension manifest and an AES-GCM encrypted signing secret; it does not execute third-party code.

Owners and admins can create, edit, disable, archive, rotate the secret, send a signed manual test, and inspect delivery activity from **Workspace → Extensions**. The endpoint must use HTTPS and cannot include user information, fragments, localhost, loopback, or `.local` hosts.

Supported subscriptions are currently `analytics.event`, `analytics.page_view`, and `diagnostics.alert`. `analytics.event` and `analytics.page_view` are queued after the corresponding raw event is persisted. Delivery uses a durable outbox, idempotency by extension/event/type, five attempts with backoff, and a graphical delivered/waiting/failed history. Payloads contain the sanitized site/page/event data but remove visitor and session identifiers.

The manual test uses `POST` with `Content-Type: application/json`, `X-SeeRay-Extension-Event: extension.test`, and `X-SeeRay-Signature: sha256=<HMAC-SHA256 hex>`. Automatic deliveries use the subscription name in the event header. The signature covers the exact JSON request body and uses the current secret.

The secret is returned only in the create/rotate response and is not included in list or update responses. Configure `SEERAY_SECRET_ENCRYPTION_KEY` with a stable base64-encoded 32-byte key before creating extensions.

This is the lifecycle and analytics webhook layer for the future executable SDK/runtime hook layer. Full third-party runtime hooks, delivery metrics/alerting, and production-scale queue observability remain planned work.
