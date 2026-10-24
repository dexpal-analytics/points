use std::error::Error;
mod contract_interfaces;
use anyhow::Result;
use contract_interfaces::*;

pub mod prelude;
pub use prelude::*;

use alloy::{
    primitives::Address,
    providers::{DynProvider, Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
    transports::http::reqwest::Url,
};

#[derive(Clone)]
pub struct PointsGoverner {
    credits: IDexPalCredits::IDexPalCreditsInstance<DynProvider>,
    points: IDexPalPoints::IDexPalPointsInstance<DynProvider>,
}

impl PointsGoverner {
    /// this is async because it gets the credits address from the points contract
    pub async fn new(
        points_contract_address: Address,
        signer: PrivateKeySigner,
        rpc: String,
    ) -> Result<Self> {
        let provider = ProviderBuilder::new()
            .wallet(signer)
            .connect_http(rpc.parse::<Url>()?)
            .erased();

        let points = IDexPalPoints::new(points_contract_address, provider.clone());

        let credits_contract_address = points.creditsContractAddress().call().await?;
        let credits = IDexPalCredits::new(credits_contract_address, provider);

        Ok(Self { points, credits })
    }

    pub async fn ban(&self, user: Address) -> Result<()> {
        self.points.banUser(user).call().await?;
        Ok(())
    }

    pub async fn 
}
