# Workspace extensions

SeeRay Lens extensions are registered per workspace as outbound HTTPS webhooks. The control plane stores the extension manifest and an AES-GCM encrypted signing secret; it does not execute third-party code.

Owners and admins can create, edit, disable, archive, rotate the secret, and send a signed manual test from **Workspace → Extensions**. The endpoint must use HTTPS and cannot include user information, fragments, localhost, loopback, or `.local` hosts.

Supported subscriptions are currently `analytics.event`, `analytics.page_view`, and `diagnostics.alert`. The manual test uses `POST` with `Content-Type: application/json`, `X-SeeRay-Extension-Event: extension.test`, and `X-SeeRay-Signature: sha256=<HMAC-SHA256 hex>`. The signature covers the exact JSON request body and uses the current secret.

The secret is returned only in the create/rotate response and is not included in list or update responses. Configure `SEERAY_SECRET_ENCRYPTION_KEY` with a stable base64-encoded 32-byte key before creating extensions.

This is the lifecycle and delivery foundation for the future executable SDK/runtime hook layer. Automatic event fan-out, retries/queues, delivery history, and production observability remain planned work.
