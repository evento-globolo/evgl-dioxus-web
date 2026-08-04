# evgl-dioxus-web

Dioxus SSR + Axum + WebSocket comparison server for Evento Globolo.

**Product:** Evento Globolo — A global event discovery and aggregation platform.

Aggregate, normalize, deduplicate, search, and follow events from sources such as Eventbrite, Meetup, LinkedIn, Facebook, and Craigslist through authorized APIs or permitted ingestion paths.

## Safety and production boundary

Provider names are integration targets, not claims of affiliation. Use official APIs and permitted data-access methods; do not bypass authentication, anti-bot, rate-limit, copyright, or platform-policy controls.

This repository is an executable bootstrap, not a production deployment. Before live
use, add authentication, tenant authorization, rate limits, durable migrations,
observability, backups, incident response, dependency review, and secret management.


This comparison surface preserves the same health and WebSocket behavior as the other web servers while exploring Dioxus SSR and a future multi-platform path.
