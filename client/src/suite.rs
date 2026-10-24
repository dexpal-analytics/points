use alloy::primitives::{Address, FixedBytes, U256};
use alloy::providers::DynProvider;

use crate::abi::{DexPalCredits, DexPalPoints};
use crate::error::{Error, Result};
use crate::limits::BALANCE_PAIRS;

const OPEN: u8 = 1;
const KINDS: [u8; 3] = [0, 1, 2];

/// Both contracts of one deployment. Only the Points address is configured: the Credits address
/// is read from it, so an owner's re-deploy is followed, and a Credits that does not name these
/// Points back is refused.
#[derive(Clone)]
pub struct Suite {
    pub(crate) points: DexPalPoints::DexPalPointsInstance<DynProvider>,
    pub(crate) credits: DexPalCredits::DexPalCreditsInstance<DynProvider>,
}

impl Suite {
    pub(crate) async fn on(provider: DynProvider, points: Address) -> Result<Self> {
        let points = DexPalPoints::new(points, provider.clone());
        let credits = DexPalCredits::new(points.creditsContractAddress().call().await?, provider);
        let named = credits.pointsContractAddress().call().await?;
        if named != *points.address() {
            return Err(Error::Unlinked { credits: *credits.address(), named, points: *points.address() });
        }
        Ok(Self { points, credits })
    }

    pub fn points_address(&self) -> Address {
        *self.points.address()
    }

    pub fn credits_address(&self) -> Address {
        *self.credits.address()
    }

    pub async fn open(&self) -> Result<bool> {
        Ok(self.credits.state().call().await? == OPEN)
    }

    pub async fn round_name(&self) -> Result<FixedBytes<16>> {
        Ok(self.credits.roundName().call().await?)
    }

    pub async fn writer(&self) -> Result<Address> {
        Ok(self.credits.writer().call().await?)
    }

    pub async fn banned(&self) -> Result<Vec<Address>> {
        Ok(self.credits.bannedUsers().call().await?)
    }

    /// Trading, quest and referral, indexed by kind.
    pub async fn supplies(&self) -> Result<[U256; 3]> {
        let mut supplies = [U256::ZERO; 3];
        for (supply, kind) in supplies.iter_mut().zip(KINDS) {
            *supply = self.credits.totalSupply(U256::from(kind)).call().await?;
        }
        Ok(supplies)
    }

    /// Each wallet's three balances, indexed by kind, in the order given.
    pub async fn balances(&self, wallets: &[Address]) -> Result<Vec<[U256; 3]>> {
        let mut balances = Vec::with_capacity(wallets.len());
        for chunk in wallets.chunks(BALANCE_PAIRS / KINDS.len()) {
            let accounts: Vec<Address> = chunk.iter().flat_map(|wallet| [*wallet; KINDS.len()]).collect();
            let ids: Vec<U256> = chunk.iter().flat_map(|_| KINDS.map(U256::from)).collect();
            let got = self.credits.balanceOfBatch(accounts, ids).call().await?;
            if got.len() != chunk.len() * KINDS.len() {
                return Err(Error::Balances { asked: chunk.len() * KINDS.len(), got: got.len() });
            }
            balances.extend(got.as_chunks::<{ KINDS.len() }>().0.iter().copied());
        }
        Ok(balances)
    }
}
