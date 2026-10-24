use alloy::network::TransactionBuilder;
use alloy::primitives::{Address, TxHash, U256};
use alloy::transports::mock::Asserter;

use super::connect::signing;
use super::send::Request;
use crate::abi::DexPalCredits::{Kind, writerCall};
use crate::error::Error;
use crate::mock_test::{CREDITS, receipt, reply, signer, writer};

const HASH: TxHash = TxHash::repeat_byte(0xfe);

fn rows() -> [(Address, Kind, U256); 1] {
    [(Address::repeat_byte(0x61), Kind::Trading, U256::from(15_000))]
}

/// The replies up to the signature: chain id, writer, gas price.
fn cleared(asserter: &Asserter, chain_id: &str, gas_price: &str) {
    asserter.push_success(&chain_id);
    reply::<writerCall>(asserter, &signer().address());
    asserter.push_success(&gas_price);
}

/// Nonce, gas estimate, the node's hash, then the receipt.
fn sent(asserter: &Asserter, status: bool) {
    asserter.push_success(&"0x3");
    asserter.push_success(&"0x30d40");
    asserter.push_success(&HASH);
    asserter.push_success(&receipt(HASH, status));
}

#[tokio::test]
async fn a_success_receipt_returns_the_hash() {
    let asserter = Asserter::new();
    let writer = writer(&asserter).await;
    cleared(&asserter, "0xb626", "0x5f5e100");
    sent(&asserter, true);
    assert_eq!(writer.set_credits(&rows()).await.expect("sent"), HASH);
    assert!(asserter.read_q().is_empty());
}

#[tokio::test]
async fn a_reverted_receipt_is_an_error_carrying_the_hash() {
    let asserter = Asserter::new();
    let writer = writer(&asserter).await;
    cleared(&asserter, "0x1237", "0x5f5e100");
    sent(&asserter, false);
    let error = writer.issue_points(&[Address::repeat_byte(0x61)]).await.expect_err("reverted");
    assert!(matches!(error, Error::Reverted { method: "issuePoints", hash: HASH }), "{error}");
}

#[tokio::test]
async fn another_chain_is_refused_before_anything_is_signed() {
    let asserter = Asserter::new();
    let writer = writer(&asserter).await;
    asserter.push_success(&"0x1");
    let error = writer.set_credits(&rows()).await.expect_err("refused");
    assert!(matches!(error, Error::WrongChain(1)), "{error}");
}

#[tokio::test]
async fn a_gas_price_over_the_ceiling_is_refused_before_anything_is_signed() {
    let asserter = Asserter::new();
    let writer = writer(&asserter).await;
    cleared(&asserter, "0xb626", "0x1dcd6501");
    let error = writer.set_credits(&rows()).await.expect_err("refused");
    assert!(matches!(error, Error::GasPrice(1_000_000_002)), "{error}");
}

#[tokio::test]
async fn a_gas_price_at_the_ceiling_is_signed() {
    let asserter = Asserter::new();
    let writer = writer(&asserter).await;
    cleared(&asserter, "0xb626", "0x1dcd6500");
    sent(&asserter, true);
    assert_eq!(writer.set_credits(&rows()).await.expect("sent"), HASH);
}

#[tokio::test]
async fn another_writer_is_refused_before_anything_is_signed() {
    let asserter = Asserter::new();
    let writer = writer(&asserter).await;
    asserter.push_success(&"0xb626");
    let other = Address::repeat_byte(0x77);
    reply::<writerCall>(&asserter, &other);
    let error = writer.set_credits(&rows()).await.expect_err("refused");
    assert!(matches!(error, Error::NotWriter { writer, .. } if writer == other), "{error}");
}

/// The request carries every field `send` sets. The queue is empty, so signing asked the RPC nothing.
#[tokio::test]
async fn the_writer_key_signs_the_transaction_here() {
    let provider = signing(signer()).connect_mocked_client(Asserter::new());
    let tx = Request::default().with_from(signer().address()).with_to(CREDITS).with_input(vec![0x26]);
    let tx = tx.with_chain_id(4663).with_nonce(3).with_gas_price(100_000_000).with_gas_limit(200_000);
    let filled = provider.fill(tx).await.expect("filled");
    let envelope = filled.as_envelope().expect("an envelope, which goes out as eth_sendRawTransaction");
    assert!(envelope.is_legacy(), "{envelope:?}");
}
