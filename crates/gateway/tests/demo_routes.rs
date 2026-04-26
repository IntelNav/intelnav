//! Smoke tests for the demo SPA routes.
//!
//! Builds the gateway router in-process and hits the demo endpoints
//! through tower's `oneshot` so no socket / port allocation needed.
//! Verifies:
//!   * `GET /` returns the HTML SPA with the elements the JS depends on
//!   * `GET /v1/swarm/topology` returns the expected JSON shape
//!   * `GET /banner` still serves the plain-text banner

use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use tower::ServiceExt;

use intelnav_core::Config;
use intelnav_gateway::server::router;
use intelnav_gateway::GatewayState;
use intelnav_net::{DhtDirectory, StaticDirectory};

fn test_state() -> GatewayState {
    GatewayState {
        config:     Arc::new(Config::default()),
        http:       reqwest::Client::new(),
        static_dir: Arc::new(StaticDirectory::new()),
        dht_dir:    Arc::new(DhtDirectory::new()),
        mdns_dir:   None,
        registry_dir: None,
        started_at: std::time::Instant::now(),
    }
}

async fn get(path: &str) -> (StatusCode, String, Option<String>) {
    let app = router(test_state());
    let resp = app
        .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = resp.status();
    let ctype = resp.headers().get("content-type")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());
    let bytes = resp.into_body().collect().await.unwrap().to_bytes();
    let body = String::from_utf8_lossy(&bytes).to_string();
    (status, body, ctype)
}

#[tokio::test]
async fn index_serves_demo_spa() {
    let (status, body, ctype) = get("/").await;
    assert_eq!(status, StatusCode::OK);
    assert!(ctype.unwrap_or_default().contains("text/html"),
            "expected HTML content-type");
    // Sanity-check that the SPA actually shipped, not a stub.
    assert!(body.contains("<title>IntelNav · swarm demo</title>"),
            "SPA title missing — embedded HTML stale?");
    assert!(body.contains("/v1/swarm/topology"),
            "SPA must reference the topology endpoint");
    assert!(body.contains("/v1/chat/completions"),
            "SPA must reference the chat endpoint");
}

#[tokio::test]
async fn topology_endpoint_returns_expected_shape() {
    let (status, body, _ctype) = get("/v1/swarm/topology").await;
    assert_eq!(status, StatusCode::OK);
    let v: serde_json::Value = serde_json::from_str(&body)
        .expect("topology must be valid JSON");
    assert_eq!(v["gateway"]["kind"], "gateway");
    assert!(v["gateway"]["id"].is_string());
    assert!(v["peers"].is_array());
    assert!(v["models"].is_array());
    assert!(v["uptime_sec"].is_number());
    assert!(v["upstream"].is_string());
}

#[tokio::test]
async fn banner_still_works() {
    let (status, body, _ctype) = get("/banner").await;
    assert_eq!(status, StatusCode::OK);
    assert!(body.contains("IntelNav gateway"));
}
