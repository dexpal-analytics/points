use std::time::Duration;

use alloy::primitives::{Address, U256};
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy::transports::http::reqwest::Url;

use crate::abi::DexPalPoints;
use crate::error::Result;
use crate::http;

const TIMEOUT: Duration = Duration::from_secs(10);

/// One wallet's Points: `issued` is minted and claimable now; `predicted` adds the share of the
/// round not yet issued. A banned wallet's share is 0, and its issued Points remain.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PointsOf {
    pub issued: U256,
    pub predicted: U256,
}

/// Reads for the Points route. It holds no key and sends nothing.
#[derive(Clone)]
pub struct Reader {
    points: DexPalPoints::DexPalPointsInstance<DynProvider>,
}

impl Reader {
    pub fn new(rpc: Url, points: Address) -> Result<Self> {
        let client = http::client(TIMEOUT)?;
        let provider = ProviderBuilder::new().disable_recommended_fillers().connect_reqwest(client, rpc);
        Ok(Self::on(provider.erased(), points))
    }

    pub(crate) fn on(provider: DynProvider, points: Address) -> Self {
        Self { points: DexPalPoints::new(points, provider) }
    }

    pub async fn points_of(&self, wallet: Address) -> Result<PointsOf> {
        let issued = self.points.balanceOf(wallet).call().await?;
        let predicted = self.points.predictedBalanceOf(wallet).call().await?;
        Ok(PointsOf { issued, predicted })
    }
}
