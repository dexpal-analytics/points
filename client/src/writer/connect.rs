use std::time::Duration;

use alloy::network::EthereumWallet;
use alloy::primitives::{Address, TxHash, U256};
use alloy::providers::fillers::{JoinFill, WalletFiller};
use alloy::providers::{DynProvider, Identity, Provider, ProviderBuilder};
use alloy::signers::local::PrivateKeySigner;
use alloy::sol_types::SolCall;
use alloy::transports::http::reqwest::Url;

use super::calls;
use crate::abi::DexPalCredits::Kind;
use crate::error::{Error, Result};
use crate::http;
use crate::suite::Suite;

const POLL: Duration = Duration::from_secs(2);
/// Each request's limit, not the send's: `POLLS` bounds the wait for a receipt.
const TIMEOUT: Duration = Duration::from_secs(30);

type Signing = ProviderBuilder<Identity, JoinFill<Identity, WalletFiller<EthereumWallet>>>;

/// Sends `setCredits` and `issuePoints` with the writer key. Each send waits for its receipt.
pub struct Writer {
    pub(super) suite: Suite,
    pub(super) signer: Address,
    pub(super) poll: Duration,
}

/// The error names no part of the key.
pub fn parse_key(hex: &str) -> Result<PrivateKeySigner> {
    hex.trim().parse().map_err(|_| Error::Key)
}

/// The wallet filler signs each transaction here, so it is sent with `eth_sendRawTransaction` and
/// the node never holds the key.
pub(crate) fn signing(signer: PrivateKeySigner) -> Signing {
    ProviderBuilder::new().disable_recommended_fillers().wallet(signer)
}

impl Writer {
    pub async fn connect(rpc: Url, points: Address, signer: PrivateKeySigner) -> Result<Self> {
        let address = signer.address();
        let provider = signing(signer).connect_reqwest(http::client(TIMEOUT)?, rpc);
        Self::on(provider.erased(), points, address, POLL).await
    }

    pub(crate) async fn on(provider: DynProvider, points: Address, signer: Address, poll: Duration) -> Result<Self> {
        Ok(Self { suite: Suite::on(provider, points).await?, signer, poll })
    }

    /// The reads the worker needs, through the same RPC.
    pub fn suite(&self) -> &Suite {
        &self.suite
    }

    /// One transaction: the caller sizes the batch to stay under the block's gas cap.
    pub async fn set_credits(&self, rows: &[(Address, Kind, U256)]) -> Result<TxHash> {
        let input = calls::set_credits(rows).abi_encode();
        self.send("setCredits", self.suite.credits_address(), input).await
    }

    /// One transaction: the caller sizes the batch to stay under the block's gas cap.
    pub async fn issue_points(&self, wallets: &[Address]) -> Result<TxHash> {
        let input = calls::issue_points(wallets).abi_encode();
        self.send("issuePoints", self.suite.points_address(), input).await
    }
}
