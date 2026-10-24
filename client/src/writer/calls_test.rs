use alloy::hex;
use alloy::primitives::{Address, U256};
use alloy::sol_types::SolCall;

use super::calls::{issue_points, set_credits};
use crate::abi::DexPalCredits::Kind;

fn word(value: u64) -> String {
    format!("{value:064x}")
}

fn address(byte: u8) -> String {
    format!("{}{}", "00".repeat(12), hex::encode([byte; 20]))
}

#[test]
fn set_credits_is_the_selector_an_offset_the_length_and_four_words_a_row_with_no_dex() {
    let rows = [
        (Address::repeat_byte(0x61), Kind::Trading, U256::from(15_000)),
        (Address::repeat_byte(0x71), Kind::Referral, U256::from(7)),
    ];
    let first = [address(0x61), word(0), word(0), word(15_000)].concat();
    let second = [address(0x71), word(2), word(0), word(7)].concat();
    let want = ["2695ee11".into(), word(0x20), word(2), first, second].concat();
    assert_eq!(hex::encode(set_credits(&rows).abi_encode()), want);
}

#[test]
fn issue_points_is_the_selector_an_offset_the_length_and_one_word_a_wallet() {
    let wallets = [Address::repeat_byte(0x61), Address::repeat_byte(0x71)];
    let want = ["809967d3".into(), word(0x20), word(2), address(0x61), address(0x71)].concat();
    assert_eq!(hex::encode(issue_points(&wallets).abi_encode()), want);
}
