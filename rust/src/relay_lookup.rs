use iroh::address_lookup::{AddressLookup, Error, Item};
use iroh::{EndpointAddr, EndpointId, RelayMap};
use n0_future::{boxed::BoxStream, stream};

#[derive(Debug)]
pub(crate) struct RelayLookup(pub(crate) RelayMap);

impl AddressLookup for RelayLookup {
    fn resolve(&self, id: EndpointId) -> Option<BoxStream<Result<Item, Error>>> {
        let address = self
            .0
            .urls::<Vec<_>>()
            .into_iter()
            .fold(EndpointAddr::new(id), |address, relay| {
                address.with_relay_url(relay)
            });
        Some(Box::pin(stream::once(Ok(Item::new(
            address.into(),
            "custom relay",
            None,
        )))))
    }
}
