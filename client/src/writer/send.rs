use alloy::network::{Ethereum, Network, TransactionBuilder};
use alloy::primitives::{Address, TxHash};
use alloy::providers::Provider;

use super::connect::Writer;
use crate::error::{Error, Result};

const POLLS: usize = 60;

pub(super) type Request = <Ethereum as Network>::TransactionRequest;

impl Writer {
    /// Nothing is retried: the next pass reads the chain again and sends only what it still lacks.
    pub(super) async fn send(&self, method: &'static str, to: Address, input: Vec<u8>) -> Result<TxHash> {
        let cleared = self.clear().await?;
        let provider = self.suite.credits.provider();
        let tx = Request::default().with_from(self.signer).with_to(to).with_input(input);
        let nonce = provider.get_transaction_count(self.signer).pending().await?;
        let gas = provider.estimate_gas(tx.clone()).await?.saturating_mul(5) / 4;
        // Legacy: Arbitrum charges only the base fee, so a tip field would add nothing.
        let tx =
            tx.with_chain_id(cleared.chain_id).with_nonce(nonce).with_gas_price(cleared.gas_price).with_gas_limit(gas);
        let hash = *provider.send_transaction(tx).await?.tx_hash();
        for _ in 0..POLLS {
            tokio::time::sleep(self.poll).await;
            if let Some(receipt) = provider.get_transaction_receipt(hash).await? {
                return receipt.status().then_some(hash).ok_or(Error::Reverted { method, hash });
            }
        }
        Err(Error::NoReceipt { method, hash, polls: POLLS })
    }
}
