# evgl-web-dioxus

Dioxus SSR operations surface for Evento Globolo. The server presents canonical
event and provider-job concepts without duplicating OAuth or provider secrets.

## Real-time channel

`GET /v1/ws` upgrades to a WebSocket used for provider-job acknowledgements and live event-publishing state. The reference server emits bounded control-plane JSON only.
