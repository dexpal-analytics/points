use alloy::providers::Provider;

use super::connect::Writer;
use crate::error::{Error, Result};
use crate::limits::{CHAIN_IDS, MAX_GAS_PRICE};

pub(super) struct Cleared {
    pub chain_id: u64,
    pub gas_price: u128,
}

impl Writer {
    /// Every check runs before anything is signed, so a refusal spends no gas.
    pub(super) async fn clear(&self) -> Result<Cleared> {
        let provider = self.suite.credits.provider();
        let chain_id = provider.get_chain_id().await?;
        if !CHAIN_IDS.contains(&chain_id) {
            return Err(Error::WrongChain(chain_id));
        }
        let writer = self.suite.writer().await?;
        if writer != self.signer {
            return Err(Error::NotWriter { writer, signer: self.signer });
        }
        // Twice the quoted price, so a rise between quote and inclusion does not strand the send.
        let gas_price = provider.get_gas_price().await?.saturating_mul(2);
        if gas_price > MAX_GAS_PRICE {
            return Err(Error::GasPrice(gas_price));
        }
        Ok(Cleared { chain_id, gas_price })
    }
}
