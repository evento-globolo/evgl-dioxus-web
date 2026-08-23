# evgl-dioxus-web

**Evento Globolo — Dioxus server-rendered Rust web server with Axum WebSockets**

A global events operating system combining event discovery, publishing, RSVP, ticketing, community, venue, and organizer workflows.

This repository was bootstrapped on 2026-08-04. It is designed as an independently deployable component and as a member of the `evgl-monorepo` workspace.

## GitHub target

`evento-globolo/evgl-dioxus-web`

## Baseline

- Rust 2024 edition for backend and native components.
- Axum HTTP/WebSocket transport.
- Supabase/PostgreSQL configuration through `DATABASE_URL`, `SUPABASE_URL`, and environment-only secrets.
- OpenTelemetry-compatible tracing hooks.
- Docker, Nix, and GitHub Actions entry points.
- Contracts live in `evgl-interfaces`; shared behavior lives in `evgl-libs`.

## Development

```bash
cp .env.example .env 2>/dev/null || true
nix develop  # optional
cargo fmt --check 2>/dev/null || true
cargo test 2>/dev/null || true
```

## Status

Foundation scaffold. Domain behavior, persistence migrations, authentication policy, and production secrets must be reviewed before deployment.

## Cross-surface delivery

User-visible, event, venue, attendee, ticket, RSVP, publication, check-in,
notification, permission, navigation, or deep-link changes in this Rust web
server must be evaluated for:

- `evento-globolo/evgl-flutter` on Android, iOS, Flutter Web/mobile web, and
  Flutter desktop;
- `evento-globolo/evgl-desktop.rs`, the planned Tauri 2 desktop app; and
- `evgl-interfaces`, generated clients, event/venue/attendee/ticket schemas,
  route types, offline-sync fixtures, and conformance tests.

This is judgment-based coordination. SEO, public discovery, and
server-rendered web presentation may remain web-only. Native check-in hardware,
printing, local files, secure storage, offline operation, and desktop
notifications may be native-specific. Event/venue identity, ticket and RSVP
state, attendee/check-in semantics, publication status, permissions, errors,
and navigation normally require coordinated updates or an explicit no-change
rationale and parity follow-up.

Deep links are HTTPS-first:

```text
https://<verified-evento-globolo-owned-host>/open/<route>?<bounded-query>
```

with `evgl://` fallback. Dioxus web, Flutter, and Tauri desktop must share
versioned route types and fixtures and support cold start, already-running
delivery, authentication resume, replay/expiry rejection, and browser fallback.
Payment credentials, ticket secrets, attendee private data, check-in tokens,
provider credentials, and bearer/refresh tokens are prohibited in URLs.
Ticket, RSVP, check-in, invitation, and import handoffs use bounded identifiers
or short-lived, single-use, audience-bound codes and explicit confirmation.

See [`docs/CROSS_SURFACE_DELIVERY.md`](docs/CROSS_SURFACE_DELIVERY.md) and the
[portfolio policy](https://github.com/ORESoftware/project-registry/blob/main/docs/cross-surface-delivery.md).

## Environment secrets

Secrets live in this repo **encrypted** with [sops](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age):
`env/enc/<dev|prod>.env.enc` is committed; `just env-use <name>` decrypts it to
`env/dec/<name>.env` (gitignored, mode 0600) and symlinks `./.env` to it. The
Nix dev shell provides the tooling, `just env-audit` runs keyless in CI, and
containers decrypt at `docker run` — never at build. See [`env/README.md`](env/README.md).
