use super::VelaNode;
use anyhow::Context;
use anyhow::{bail, Result};
use iroh::{RelayConfig, RelayUrl};
use std::str::FromStr;
use std::sync::Arc;

pub(super) fn relay_origin(url: &str) -> Result<RelayUrl> {
    let relay = RelayUrl::from_str(url.trim()).context("invalid relay URL")?;
    if relay.scheme() != "https"
        || relay.host_str().is_none()
        || !relay.username().is_empty()
        || relay.password().is_some()
        || relay.query().is_some()
        || relay.fragment().is_some()
        || relay.path() != "/"
    {
        bail!("relay must be an HTTPS origin")
    }
    Ok(relay)
}

impl VelaNode {
    pub async fn add_relay(&self, url: String, token: Option<String>) -> Result<String> {
        let relay = relay_origin(&url)?;
        if iroh::defaults::prod::default_relay_map().contains(&relay) {
            bail!("default relay already exists")
        }
        let mut config = RelayConfig::from(relay.clone());
        if let Some(token) = token.filter(|s| !s.is_empty()) {
            crate::diagnostics::register_secret(&token);
            config = config.with_auth_token(token);
        }
        self.endpoint
            .insert_relay(relay.clone(), Arc::new(config))
            .await;
        Ok(relay.to_string())
    }

    pub async fn remove_relay(&self, url: String) -> Result<()> {
        let relay = RelayUrl::from_str(&url).context("invalid relay URL")?;
        if iroh::defaults::prod::default_relay_map().contains(&relay) {
            bail!("cannot remove default relay")
        }
        self.endpoint.remove_relay(&relay).await;
        Ok(())
    }
}
