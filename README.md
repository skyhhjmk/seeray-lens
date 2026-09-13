# SeeRay Lens

Lightweight, self-hosted, privacy-first web analytics. See [architecture](docs/architecture/overview.md) and [ADRs](docs/adr/).

## Current scope

The control plane implements local authentication, Workspaces, Sites, allowed domains, and Workspace API tokens. The Flutter Web admin uses those real versioned REST endpoints. Tracking collection, event ingestion, analytics, aggregation, and dashboard metrics are deliberately not implemented yet.

For local Flutter Web development, use the backend's configured development origin:

```sh
(cd admin && flutter run -d chrome --web-port 3000)
```

With the Quarkus control plane and PostgreSQL running, the real Flutter REST
loop can be exercised with:

```sh
(cd admin && flutter test test/real_control_plane_integration_test.dart \
  --dart-define=SEERAY_RUN_REAL_API_TESTS=true)
```

The admin keeps its access and refresh credentials in memory for this release, so a browser reload requires login. See [ADR 0007](docs/adr/0007-admin-token-storage-and-refresh.md) for the security rationale.

## Local validation

```sh
./gradlew check
(cd admin && flutter pub get && flutter analyze && flutter test)
(cd tracker && npm ci && npm run lint && npm test && npm run build)
podman compose -f deploy/compose/docker-compose.yml config --quiet
```

Start development dependencies with `podman compose -f deploy/compose/docker-compose.yml up -d`. RabbitMQ Management is available at `http://localhost:15672` for development only.
