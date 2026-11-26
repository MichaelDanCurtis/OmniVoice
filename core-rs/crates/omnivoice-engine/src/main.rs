use std::path::PathBuf;
use std::sync::Arc;

use omnivoice_core::store::RuntimeStore;
use omnivoice_engine::{build_router, AppState};
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("info".parse().unwrap()))
        .init();

    let port: u16 = std::env::var("OMNIVOICE_ENGINE_PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(8765);

    let data_dir = std::env::var("OMNIVOICE_ENGINE_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("./engine-data"));
    let db_path = data_dir.join("omnivoice.db");
    let model_root = std::env::var_os("OMNIVOICE_MODEL_ROOT")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from);

    let store = RuntimeStore::open(&db_path).expect("failed to open RuntimeStore SQLite DB");
    let auth_token = std::env::var("OMNIVOICE_ENGINE_TOKEN").ok();
    let state = Arc::new(AppState::with_model_root(store, auth_token, model_root));
    let app = build_router(state);

    let addr = format!("127.0.0.1:{port}");
    let listener = TcpListener::bind(&addr)
        .await
        .unwrap_or_else(|err| panic!("failed to bind {addr}: {err}"));
    tracing::info!("omnivoice-engine (Rust) listening on http://{addr}");
    axum::serve(listener, app).await.expect("server error");
}
