//! A mocked transport: each JSON-RPC request takes the next queued reply, so nothing leaves the
//! process, and a request the test did not expect fails on an empty queue.

use std::time::Duration;

use alloy::hex;
use alloy::primitives::{Address, TxHash};
use alloy::providers::{DynProvider, Provider};
use alloy::signers::local::PrivateKeySigner;
use alloy::sol_types::SolCall;
use alloy::transports::mock::Asserter;
use serde_json::{Value, json};

use crate::abi::{DexPalCredits, DexPalPoints};
use crate::suite::Suite;
use crate::writer::{Writer, signing};

pub const POINTS: Address = Address::repeat_byte(0x53);
pub const CREDITS: Address = Address::repeat_byte(0x52);

pub fn signer() -> PrivateKeySigner {
    PrivateKeySigner::from_slice(&[0x46; 32]).expect("a key")
}

pub fn provider(asserter: &Asserter) -> DynProvider {
    signing(signer()).connect_mocked_client(asserter.clone()).erased()
}

/// An `eth_call` reply: the call's return value, ABI-encoded.
pub fn reply<C: SolCall>(asserter: &Asserter, value: &C::Return) {
    asserter.push_success(&hex::encode_prefixed(C::abi_encode_returns(value)));
}

pub fn link(asserter: &Asserter, named: Address) {
    reply::<DexPalPoints::creditsContractAddressCall>(asserter, &CREDITS);
    reply::<DexPalCredits::pointsContractAddressCall>(asserter, &named);
}

pub async fn suite(asserter: &Asserter) -> Suite {
    link(asserter, POINTS);
    Suite::on(provider(asserter), POINTS).await.expect("a linked suite")
}

pub async fn writer(asserter: &Asserter) -> Writer {
    link(asserter, POINTS);
    let writer = Writer::on(provider(asserter), POINTS, signer().address(), Duration::ZERO).await;
    writer.expect("a linked suite")
}

pub fn receipt(hash: TxHash, status: bool) -> Value {
    json!({
        "type": "0x0",
        "status": if status { "0x1" } else { "0x0" },
        "cumulativeGasUsed": "0x5208",
        "logs": [],
        "logsBloom": format!("0x{}", "00".repeat(256)),
        "transactionHash": hash,
        "transactionIndex": "0x0",
        "blockHash": TxHash::repeat_byte(0xbb),
        "blockNumber": "0x1",
        "gasUsed": "0x5208",
        "effectiveGasPrice": "0x5f5e100",
        "from": signer().address(),
        "to": CREDITS,
        "contractAddress": null
    })
}
