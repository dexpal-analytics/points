use alloy::primitives::{Address, FixedBytes, U256};
use alloy::transports::mock::Asserter;

use crate::abi::DexPalCredits::{balanceOfBatchCall, roundNameCall, stateCall};
use crate::error::Error;
use crate::mock_test::{POINTS, link, provider, reply, suite};
use crate::suite::Suite;

#[tokio::test]
async fn credits_that_name_other_points_are_refused() {
    let asserter = Asserter::new();
    link(&asserter, Address::repeat_byte(0x99));
    let error = Suite::on(provider(&asserter), POINTS).await.err().expect("refused");
    assert!(matches!(error, Error::Unlinked { .. }), "{error}");
}

#[tokio::test]
async fn open_is_state_one_and_the_round_is_its_sixteen_bytes() {
    let asserter = Asserter::new();
    let suite = suite(&asserter).await;
    reply::<stateCall>(&asserter, &1);
    reply::<roundNameCall>(&asserter, &FixedBytes::repeat_byte(0x0a));
    assert!(suite.open().await.expect("a state"));
    assert_eq!(suite.round_name().await.expect("a name"), FixedBytes::repeat_byte(0x0a));
}

#[tokio::test]
async fn balances_ask_three_hundred_pairs_a_call_and_come_back_per_wallet() {
    let asserter = Asserter::new();
    let suite = suite(&asserter).await;
    let wallets: Vec<Address> = (0..101u8).map(Address::repeat_byte).collect();
    let first: Vec<U256> = (0..300u64).map(U256::from).collect();
    reply::<balanceOfBatchCall>(&asserter, &first);
    reply::<balanceOfBatchCall>(&asserter, &vec![U256::from(7), U256::from(8), U256::from(9)]);
    let balances = suite.balances(&wallets).await.expect("balances");
    assert_eq!(balances.len(), 101);
    assert_eq!(balances[1], [U256::from(3), U256::from(4), U256::from(5)]);
    assert_eq!(balances[100], [U256::from(7), U256::from(8), U256::from(9)]);
    assert!(asserter.read_q().is_empty());
}

#[tokio::test]
async fn a_short_balance_reply_is_an_error() {
    let asserter = Asserter::new();
    let suite = suite(&asserter).await;
    reply::<balanceOfBatchCall>(&asserter, &vec![U256::from(1)]);
    let error = suite.balances(&[Address::repeat_byte(1)]).await.expect_err("short");
    assert!(matches!(error, Error::Balances { asked: 3, got: 1 }), "{error}");
}
