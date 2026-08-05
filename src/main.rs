use std::env;
use axum::{extract::ws::{Message, WebSocket, WebSocketUpgrade}, response::{Html, IntoResponse}, routing::get, Router};
use dioxus::prelude::*;
use futures_util::{SinkExt, StreamExt};
use tower_http::trace::TraceLayer;

#[component]
fn App() -> Element {
    rsx! {
        main { class: "shell",
            p { class: "eyebrow", "Rust server-rendered Dioxus" }
            h1 { "Evento Globolo" }
            p { "A global events operating system combining event discovery, publishing, RSVP, ticketing, community, venue, and organizer workflows." }
            section { class: "grid",
                article { h2 { "Production studio" } p { "Responsive SSR shell with an Axum WebSocket transport." } }
                article { h2 { "Primary API" } code { "/v1/events" } }
                article { h2 { "Data" } p { "SeaORM + Supabase/PostgreSQL configuration boundary." } }
            }
            p { id: "live", "Connecting to realtime channel…" }
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::from_default_env()).init();
    let app = Router::new().route("/", get(index)).route("/healthz", get(health)).route("/ws", get(ws)).layer(TraceLayer::new_for_http());
    let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".into());
    let port = env::var("PORT").unwrap_or_else(|_| "8083".into());
    let listener = tokio::net::TcpListener::bind(format!("{host}:{port}")).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn index() -> Html<String> {
    let body = dioxus_ssr::render_element(rsx! { App {} });
    Html(format!(r#"<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Evento Globolo</title><style>body{{font-family:system-ui;margin:0;background:#0c111b;color:#eef2ff}}.shell{{max-width:960px;margin:auto;padding:4rem 1.5rem}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:1rem}}article{{background:#182234;padding:1.25rem;border-radius:14px}}code{{color:#b8f7d4}}</style></head><body>{body}<script>const el=document.getElementById('live');const ws=new WebSocket(`${location.protocol==='https:'?'wss':'ws'}://${location.host}/ws`);ws.onopen=()=>el.textContent='Connected';ws.onmessage=e=>el.textContent=e.data;ws.onclose=()=>el.textContent='Disconnected';</script></body></html>"#))
}

async fn health() -> impl IntoResponse { axum::Json(serde_json::json!({"status":"ok","ui":"dioxus-ssr"})) }
async fn ws(upgrade: WebSocketUpgrade) -> impl IntoResponse { upgrade.on_upgrade(handle_ws) }
async fn handle_ws(mut socket: WebSocket) {
    let _ = socket.send(Message::Text("Evento Globolo realtime channel ready".into())).await;
    while let Some(Ok(message)) = socket.next().await {
        match message { Message::Text(text) => { let _ = socket.send(Message::Text(format!("ack:{text}").into())).await; }, Message::Close(_) => break, _ => {} }
    }
}
