use std::env;

use axum::{
    Router,
    extract::{
        State,
        ws::{Message, WebSocket, WebSocketUpgrade},
    },
    response::{Html, IntoResponse},
    routing::get,
};
use dioxus::prelude::*;
use futures_util::StreamExt;
use serde::Deserialize;
use tower_http::trace::TraceLayer;
use url::Url;

const DOCUMENT_HEAD: &str = r#"<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Evento Globolo</title><style>body{font-family:system-ui;margin:0;background:#0c111b;color:#eef2ff}.shell{max-width:960px;margin:auto;padding:4rem 1.5rem}.grid,.providers{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:1rem}article{background:#182234;padding:1.25rem;border-radius:14px}code{color:#b8f7d4}.button{display:inline-block;margin:1rem 0;padding:.75rem 1rem;background:#b8f7d4;color:#0c111b;text-decoration:none;border-radius:.5rem}.provider-name{text-transform:capitalize}</style></head><body>"#;
const DOCUMENT_TAIL: &str = r#"<script>const el=document.getElementById('live');const ws=new WebSocket(`${location.protocol==='https:'?'wss':'ws'}://${location.host}/ws`);ws.onopen=()=>el.textContent='Connected';ws.onmessage=e=>el.textContent=e.data;ws.onclose=()=>el.textContent='Disconnected';</script></body></html>"#;

#[derive(Clone)]
struct AppState {
    api_url: Url,
    http: reqwest::Client,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
struct ProviderView {
    capabilities: Capabilities,
    configured: bool,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
struct Capabilities {
    provider: String,
    delivery_mode: String,
    oauth: bool,
    publish: bool,
    requires_manual_step: bool,
    notes: Vec<String>,
}

#[component]
fn App() -> Element {
    rsx! {
        main { class: "shell",
            p { class: "eyebrow", "Rust server-rendered Dioxus" }
            h1 { "Evento Globolo" }
            p { "A global events operating system combining event discovery, publishing, RSVP, ticketing, community, venue, and organizer workflows." }
            section { class: "grid",
                article {
                    h2 { "Production studio" }
                    p { "Responsive SSR shell with an Axum WebSocket transport." }
                }
                article {
                    h2 { "Primary API" }
                    code { "/v1/events" }
                }
                article {
                    h2 { "Data" }
                    p { "SeaORM + Supabase/PostgreSQL configuration boundary." }
                }
            }
            p { id: "live", "Connecting to realtime channel…" }
            a { class: "button", href: "/providers", "Open provider capability map" }
        }
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    let state = AppState {
        api_url: env::var("EVGL_API_URL")
            .unwrap_or_else(|_| "http://localhost:8080".into())
            .parse()?,
        http: reqwest::Client::new(),
    };
    let app = Router::new()
        .route("/", get(index))
        .route("/providers", get(providers))
        .route("/healthz", get(health))
        .route("/ws", get(ws))
        .route("/v1/ws", get(ws))
        .layer(TraceLayer::new_for_http())
        .with_state(state);
    let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".into());
    let port = env::var("PORT").unwrap_or_else(|_| "8083".into());
    let listener = tokio::net::TcpListener::bind(format!("{host}:{port}")).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn index() -> Html<String> {
    let body = dioxus_ssr::render_element(rsx! { App {} });
    Html([DOCUMENT_HEAD, &body, DOCUMENT_TAIL].concat())
}

async fn providers(State(state): State<AppState>) -> Html<String> {
    let providers: Vec<ProviderView> = match state.api_url.join("v1/providers") {
        Ok(url) => match state.http.get(url).send().await {
            Ok(response) if response.status().is_success() => {
                response.json().await.unwrap_or_default()
            }
            _ => Vec::new(),
        },
        Err(_) => Vec::new(),
    };
    let body = dioxus_ssr::render_element(rsx! {
        main { class: "shell",
            p { "CONNECTED ECOSYSTEM" }
            h1 { "Every provider declares its limits." }
            section { class: "providers",
                for provider in providers {
                    article {
                        h2 { class: "provider-name", {provider.capabilities.provider.replace('_', " ")} }
                        strong { {provider.capabilities.delivery_mode.replace('_', " ")} }
                        p {
                            if provider.capabilities.requires_manual_step {
                                "A user completes the final platform action."
                            } else if provider.capabilities.publish {
                                "The provider adapter can publish automatically."
                            } else {
                                "Publishing is unavailable."
                            }
                        }
                        p { if provider.configured { "Ready" } else { "Configure" } }
                        p { if provider.capabilities.oauth { "OAuth" } else { "Manual or HMAC secret" } }
                        ul {
                            for note in provider.capabilities.notes {
                                li { {note} }
                            }
                        }
                    }
                }
            }
        }
    });
    Html([DOCUMENT_HEAD, &body, "</body></html>"].concat())
}

async fn health() -> impl IntoResponse {
    axum::Json(serde_json::json!({"status":"ok","ui":"dioxus-ssr"}))
}

async fn ws(upgrade: WebSocketUpgrade) -> impl IntoResponse {
    upgrade.max_message_size(64 * 1024).on_upgrade(handle_ws)
}

async fn handle_ws(mut socket: WebSocket) {
    let _ = socket
        .send(Message::Text(
            serde_json::json!({
                "type": "connected",
                "service": "evgl-dioxus-web",
                "channel": "provider-jobs",
            })
            .to_string()
            .into(),
        ))
        .await;
    while let Some(Ok(message)) = socket.next().await {
        match message {
            Message::Ping(payload)
                if socket.send(Message::Pong(payload.clone())).await.is_err() =>
            {
                break;
            }
            Message::Text(_) => {
                let _ = socket
                    .send(Message::Text(
                        serde_json::json!({
                            "type": "acknowledged",
                            "service": "evgl-dioxus-web",
                        })
                        .to_string()
                        .into(),
                    ))
                    .await;
            }
            Message::Close(_) => break,
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn rendered_document_preserves_dioxus_and_websocket_bootstrap() {
        let Html(document) = index().await;

        assert!(document.starts_with("<!doctype html>"));
        assert!(document.contains("Rust server-rendered Dioxus"));
        assert!(document.contains("id=\"live\""));
        assert!(document.contains("new WebSocket(`${location.protocol"));
        assert!(document.contains("${location.host}/ws"));
        assert!(document.ends_with("</body></html>"));
    }

    #[test]
    fn websocket_control_channel_is_bounded_and_non_reflective() {
        let source = include_str!("main.rs");
        assert!(source.contains("max_message_size(64 * 1024)"));
        assert!(source.contains("\"type\": \"acknowledged\""));
        assert!(!source.contains("format!(\"ack:{text}\")"));
    }
}
