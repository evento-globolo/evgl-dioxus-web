# Cross-surface delivery

Verified **2026-08-06**.

## Surfaces

- Rust Dioxus web server: `evento-globolo/evgl-dioxus-web`
- Flutter Android/iOS, Flutter Web, and Flutter desktop: `evento-globolo/evgl-flutter` — planned
- Rust desktop: `evento-globolo/evgl-desktop.rs` — planned Tauri 2 app
- Shared contracts: `evgl-interfaces`, generated clients, event/venue/attendee/ticket schemas, routes, offline-sync fixtures, and conformance tests

## Judgment-based propagation

Evaluate mobile, Flutter Web, Flutter desktop, Rust desktop, and shared contracts for every user-visible or contract-changing web change. SEO and public discovery may remain web-only. Check-in hardware, printing, local files, secure storage, offline operation, and native notifications may be native-specific. Event/venue identity, tickets, RSVPs, attendees/check-in, publication status, permissions, errors, notifications, and navigation normally propagate or require an explicit rationale and parity issue.

## Deep links

```text
https://<verified-evento-globolo-owned-host>/open/<route>?<bounded-query>
evgl://<route>?<bounded-query>
```

The HTTPS host must be verified. All surfaces share versioned routes and fixtures and support cold start, already-running delivery, authentication resume, replay/expiry rejection, browser fallback, and explicit confirmation before ticket, RSVP, check-in, invitation, import, payment-adjacent, or destructive actions.

Never put payment credentials, ticket secrets, attendee private data, check-in tokens, provider credentials, or bearer/refresh tokens in URLs. Use bounded identifiers or short-lived, single-use, audience-bound codes and validate route version, event/venue/ticket/attendee IDs, action, authorization, limits, and user intent.

## Review checklist

- [ ] Flutter Android/iOS impact evaluated.
- [ ] Flutter Web/mobile-web impact evaluated.
- [ ] Flutter desktop impact evaluated.
- [ ] Tauri Rust desktop impact evaluated.
- [ ] Shared event/client/route/fixture impact evaluated.
- [ ] Deep-link and offline-sync compatibility tested where relevant.
- [ ] Omitted surfaces have a rationale and follow-up when needed.

## Routing

- GitHub Project: [`evento-globolo-project` — Project 1](https://github.com/orgs/evento-globolo/projects/1)
- Linear project: [`github.com/evento-globolo`](https://linear.app/denman/project/githubcomevento-globolo-4daaf1952e29)
- Central policy: [`cross-surface-delivery.md`](https://github.com/ORESoftware/project-registry/blob/main/docs/cross-surface-delivery.md)
- Desktop registry: [`desktop-applications.json`](https://github.com/ORESoftware/project-registry/blob/main/registry/desktop-applications.json)
