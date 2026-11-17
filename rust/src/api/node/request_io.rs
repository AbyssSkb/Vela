use anyhow::{bail, Result};
use iroh::endpoint::{StoppedError, VarInt};

pub(super) async fn check_response_end(recv: &mut iroh::endpoint::RecvStream) -> Result<()> {
    let mut extra = [0u8; 1];
    match tokio::time::timeout(std::time::Duration::from_secs(2), recv.read(&mut extra)).await {
        Ok(Ok(Some(_))) => bail!("unexpected data after response"),
        Ok(Err(error)) => return Err(error.into()),
        Ok(Ok(None)) => {}
        // shortcut: late extra bytes are unchecked; use framed responses if strict validation is needed.
        Err(_) => {}
    }
    Ok(())
}

pub(super) fn response_acknowledged(
    result: std::result::Result<Option<VarInt>, StoppedError>,
) -> Result<()> {
    match result {
        Ok(None) => Ok(()),
        Ok(Some(code)) => bail!("response stopped: {}", code.into_inner()),
        Err(error) => Err(error.into()),
    }
}
