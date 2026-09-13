# ADR 0006: RabbitMQ at-least-once topology

**Status:** Accepted

Publish persistent messages with confirms to exchange `seeray.tracking` / routing key `event.v1`. Consume from durable quorum queue `seeray.tracking.ingest.v1` using manual ACK. Use bounded application retry through `seeray.tracking.retry.v1` and dead-letter exhausted messages to `seeray.tracking.dlq.v1`. Set broker delivery-limit above the application retry limit so delivery-limit does not conflict with the application retry policy.
