use super::validation::{valid_device_name, valid_device_type};
use super::{DeviceInfo, PresenceSnapshot, VelaNode};
use crate::trust::TrustStatus;
use anyhow::{anyhow, bail, Result};
use std::collections::HashSet;

impl VelaNode {
    pub async fn replace_trusted_peers(&self, trusted: Vec<String>) -> Result<()> {
        let count = trusted.len();
        let desired: HashSet<_> = trusted.into_iter().collect();
        if desired.len() != count {
            bail!("duplicate device ID")
        }
        for id in &desired {
            id.parse::<iroh::EndpointId>()
                .map_err(|_| anyhow!("invalid device ID"))?;
        }
        self.trust.write().await.replace_trusted_peers(desired);
        self.presence.reconcile_trusted_peers().await;
        Ok(())
    }

    /// Isolate the old trusted session before creating or accepting a pairing request.
    /// This changes local trust state; it does not perform a network handshake.
    pub async fn begin_pairing(&self, peer_id: String) -> Result<()> {
        peer_id
            .parse::<iroh::EndpointId>()
            .map_err(|_| anyhow!("invalid device ID"))?;
        self.trust.write().await.begin_pairing(peer_id);
        self.presence.reconcile_trusted_peers().await;
        Ok(())
    }

    /// Leave isolation and cancel the request, on success or failure.
    /// A successful handshake must first be persisted and synced with `replace_trusted_peers`.
    pub async fn end_pairing(&self, peer_id: String) -> Result<()> {
        peer_id
            .parse::<iroh::EndpointId>()
            .map_err(|_| anyhow!("invalid device ID"))?;
        self.trust.write().await.end_pairing(&peer_id);
        self.presence.reconcile_trusted_peers().await;
        Ok(())
    }

    pub async fn revoke_if_unpaired(&self, peer_id: String) -> bool {
        self.presence.revoke_if_unpaired(&peer_id).await
    }

    pub async fn set_presence_monitoring(&self, enabled: bool) -> Result<()> {
        self.presence.set_monitoring(enabled).await
    }

    pub async fn wait_presence_snapshot(&self, after_revision: u64) -> Result<PresenceSnapshot> {
        self.presence.wait_snapshot(after_revision).await
    }

    pub async fn set_device_info(&self, name: String, device_type: String) -> Result<()> {
        if !valid_device_name(&name) || !valid_device_type(&device_type) {
            bail!("invalid device information")
        }
        *self.device_info.write().await = Some(DeviceInfo { name, device_type });
        Ok(())
    }

    pub async fn check_peer(&self, peer_id: String) -> Result<DeviceInfo> {
        self.check_presence_peer(&peer_id, false).await
    }

    pub async fn check_peer_fresh(&self, peer_id: String) -> Result<DeviceInfo> {
        self.check_presence_peer(&peer_id, true).await
    }

    async fn check_presence_peer(&self, peer_id: &str, fresh: bool) -> Result<DeviceInfo> {
        let session = {
            let state = self.trust.read().await;
            if state.status(peer_id) != TrustStatus::Paired {
                bail!("untrusted device")
            }
            state
                .sessions
                .get(peer_id)
                .cloned()
                .ok_or_else(|| anyhow!("untrusted device"))?
        };
        let info = self.presence.check(peer_id, fresh).await?;
        if !self.trust.read().await.is_current(peer_id, &session) {
            bail!("pairing changed")
        }
        Ok(info)
    }
}
