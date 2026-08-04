        use axum::{
            extract::{State, WebSocketUpgrade, ws::{Message, WebSocket}},
            response::{Html, Response},
            routing::get,
            Json, Router,
        };
        use futures_util::{SinkExt, StreamExt};
        use dioxus::prelude::*;
        use std::{env, net::SocketAddr};
        use tokio::sync::broadcast;
        use tower_http::trace::TraceLayer;
        use tracing::info;

        #[derive(Clone)]
        struct AppState { events: broadcast::Sender<String> }

        #[tokio::main]
        async fn main() -> Result<(), Box<dyn std::error::Error>> {
            tracing_subscriber::fmt().with_env_filter(
                tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,tower_http=info".into())
            ).init();
            let (events, _) = broadcast::channel(128);
            let state = AppState { events };
            let app = Router::new()
                .route("/", get(index))
                .route("/healthz", get(health))
                .route("/readyz", get(health))
                .route("/ws", get(ws_upgrade))
                .route("/api/demo-event", get(demo_event))
                .layer(TraceLayer::new_for_http())
                .with_state(state);
            let addr: SocketAddr = env::var("BIND_ADDR").unwrap_or_else(|_| "127.0.0.1:8080".into()).parse()?;
            let listener = tokio::net::TcpListener::bind(addr).await?;
            info!(%addr, "Evento Globolo Dioxus web listening");
            axum::serve(listener, app).await?;
            Ok(())
        }

        async fn index() -> Html<String> {
            let body = dioxus_ssr::render_element(rsx! {
        main {
            h1 { "Evento Globolo" }
            p { "A global event discovery and aggregation platform." }
            button { id: "emit", "Emit demo WebSocket event" }
            pre { id: "events", "waiting for events" }
        }
    });
    let script = r#"<script>
      const out=document.getElementById('events');
      const ws=new WebSocket(`${location.protocol==='https:'?'wss':'ws'}://${location.host}/ws`);
      ws.onmessage=(event)=>{out.textContent=event.data};
      document.getElementById('emit').onclick=()=>fetch('/api/demo-event');
    </script>"#;
    Html(format!("<!doctype html><html><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>Evento Globolo</title><style>body{{font-family:system-ui;max-width:64rem;margin:auto;padding:2rem}}main{{padding:2rem;border:1px solid #ddd;border-radius:1rem}}</style></head><body>{body}{script}</body></html>"))
        }

        async fn health() -> Json<serde_json::Value> {
            Json(serde_json::json!({"status":"ok","service":"evgl-dioxus-web","framework":"Dioxus"}))
        }

        async fn demo_event(State(state): State<AppState>) -> Json<serde_json::Value> {
            let payload = serde_json::json!({"event_type":"demo.changed","product":"Evento Globolo"});
            let _ = state.events.send(payload.to_string());
            Json(payload)
        }

        async fn ws_upgrade(ws: WebSocketUpgrade, State(state): State<AppState>) -> Response {
    ws.on_upgrade(move |socket| ws_loop(socket, state.events.subscribe()))
}

async fn ws_loop(socket: WebSocket, mut events: broadcast::Receiver<String>) {
    let (mut sender, mut receiver) = socket.split();
    loop {
        tokio::select! {
            event = events.recv() => match event {
                Ok(text) => {
                    if sender.send(Message::Text(text.into())).await.is_err() { break; }
                },
                Err(broadcast::error::RecvError::Closed) => break,
                _ => {},
            },
            incoming = receiver.next() => match incoming {
                Some(Ok(Message::Ping(data))) => {
                    if sender.send(Message::Pong(data)).await.is_err() { break; }
                },
                Some(Ok(Message::Close(_))) | None | Some(Err(_)) => break,
                _ => {},
            }
        }
    }
}
