use axum::{
    extract::{State, WebSocketUpgrade, ws::{Message, WebSocket}},
    response::{Html, IntoResponse},
    routing::get,
    Json, Router,
};
use dioxus::prelude::*;
use serde::Deserialize;
use tower_http::trace::TraceLayer;
use url::Url;

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

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .json()
        .init();
    let state = AppState {
        api_url: std::env::var("EVGL_API_URL")
            .unwrap_or_else(|_| "http://localhost:8080".into()).parse()?,
        http: reqwest::Client::new(),
    };
    let app = Router::new()
        .route("/", get(index))
        .route("/providers", get(providers))
        .route("/v1/ws", get(websocket))
        .route("/healthz", get(|| async {
            Json(serde_json::json!({"status":"ok","service":"evgl-web-dioxus"}))
        }))
        .layer(TraceLayer::new_for_http())
        .with_state(state);
    let bind = std::env::var("APP_BIND").unwrap_or_else(|_| "0.0.0.0:3200".into());
    let listener = tokio::net::TcpListener::bind(&bind).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn websocket(upgrade: WebSocketUpgrade) -> impl IntoResponse {
    upgrade.on_upgrade(handle_socket)
}

async fn handle_socket(mut socket: WebSocket) {
    let connected = serde_json::json!({
        "type": "connected",
        "service": "evgl-web-dioxus",
        "channel": "provider-jobs",
    });
    if socket.send(Message::Text(connected.to_string().into())).await.is_err() {
        return;
    }

    while let Some(message) = socket.recv().await {
        match message {
            Ok(Message::Ping(payload)) => {
                if socket.send(Message::Pong(payload)).await.is_err() {
                    break;
                }
            }
            Ok(Message::Text(_)) => {
                let acknowledgement = serde_json::json!({
                    "type": "acknowledged",
                    "service": "evgl-web-dioxus",
                });
                if socket.send(Message::Text(acknowledgement.to_string().into())).await.is_err() {
                    break;
                }
            }
            Ok(Message::Close(_)) | Err(_) => break,
            _ => {}
        }
    }
}

async fn index() -> Html<String> {
    Html(document(rsx! {
        main { class: "shell",
            p { class: "eyebrow", "DIOXUS EVENT CONTROL" }
            h1 { "Operate one event across many systems." }
            p { class: "lede",
                "Canonical data, provider receipts, live jobs, and explicit human handoffs."
            }
            a { class: "button", href: "/providers", "Open provider map →" }
        }
    }))
}

async fn providers(State(state): State<AppState>) -> Html<String> {
    let providers: Vec<ProviderView> = match state.api_url.join("v1/providers") {
        Ok(url) => match state.http.get(url).send().await {
            Ok(response) if response.status().is_success() =>
                response.json().await.unwrap_or_default(),
            _ => vec![],
        },
        Err(_) => vec![],
    };
    Html(document(rsx! {
        main { class: "shell",
            p { class: "eyebrow", "CONNECTED ECOSYSTEM" }
            h1 { "Every provider declares its limits." }
            section { class: "providers",
                for provider in providers {
                    article {
                        div { class: "top",
                            h2 { provider.capabilities.provider.replace('_', " ") }
                            span {
                                if provider.configured { "Ready" } else { "Configure" }
                            }
                        }
                        strong { provider.capabilities.delivery_mode.replace('_', " ") }
                        p {
                            if provider.capabilities.requires_manual_step {
                                "A user completes the final platform action."
                            } else if provider.capabilities.publish {
                                "The provider adapter can publish automatically."
                            } else {
                                "Publishing is unavailable."
                            }
                        }
                        ul {
                            for note in provider.capabilities.notes {
                                li { note }
                            }
                        }
                        small {
                            if provider.capabilities.oauth { "OAuth" } else { "Manual or HMAC secret" }
                        }
                    }
                }
            }
        }
    }))
}

fn document(root: Element) -> String {
    format!(
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">\
         <meta name=\"viewport\" content=\"width=device-width\">\
         <title>Evento Globolo · Dioxus</title><style>{}</style></head><body>{}</body></html>",
        STYLES,
        dioxus_ssr::render_element(root)
    )
}

const STYLES: &str = r#"
  :root{--ink:#0e1010;--paper:#eef1ef;--blue:#8cafff;--line:#c9cecb;--muted:#626a66}
  *{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.5 system-ui,sans-serif}
  .shell{width:min(1140px,calc(100% - 40px));margin:auto;padding:90px 0}.eyebrow{font-size:12px;font-weight:800;letter-spacing:.18em}
  h1{font-size:clamp(54px,8vw,108px);line-height:.9;letter-spacing:-.07em;max-width:1000px;margin:24px 0}.lede{font-size:21px;color:var(--muted);max-width:690px}
  .button{display:inline-block;background:var(--ink);color:white;padding:15px 20px;text-decoration:none;font-weight:700;margin-top:30px}
  .providers{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:14px;margin-top:55px}.providers article{background:#fff;border:1px solid var(--line);padding:25px;min-height:280px}
  .top{display:flex;justify-content:space-between;gap:12px}.top h2{text-transform:capitalize;margin:0}.top span{background:var(--blue);padding:5px 9px;height:max-content;font-size:11px}
  article>strong{text-transform:uppercase;letter-spacing:.1em;color:var(--muted);font-size:11px}li{color:var(--muted);margin:7px 0}small{font-weight:700}
"#;
