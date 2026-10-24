use std::error::Error;
mod contract_interfaces;
use anyhow::Result;
use contract_interfaces::*;

use alloy::{
    primitives::Address,
    providers::{DynProvider, Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
    transports::http::reqwest::Url,
};

pub struct PointsGoverner {
    credits: IDexPalCredits::IDexPalCreditsInstance<DynProvider>,
    points: IDexPalPoints::IDexPalPointsInstance<DynProvider>,
}

impl PointsGoverner {
    pub fn new(
        points_contract_address: Address,
        signer: PrivateKeySigner,
        rpc: String,
    ) -> Result<Self> {
        let provider = ProviderBuilder::new()
            .wallet(signer)
            .connect_http(rpc.parse::<Url>()?)
            .erased();
        let points = 
        Ok(Self {})
    }
}
