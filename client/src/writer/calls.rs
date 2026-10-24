use alloy::primitives::{Address, FixedBytes, U256};

use crate::abi::DexPalCredits::{Credit, Kind, setCreditsCall};
use crate::abi::DexPalPoints::issuePointsCall;

/// The suite keeps one amount per wallet and kind, so a row never names a dex.
const NO_DEX: FixedBytes<32> = FixedBytes::ZERO;

pub(crate) fn set_credits(rows: &[(Address, Kind, U256)]) -> setCreditsCall {
    let entries = rows.iter().map(|&(user, kind, amount)| Credit { user, kind, dex: NO_DEX, amount });
    setCreditsCall { entries: entries.collect() }
}

pub(crate) fn issue_points(wallets: &[Address]) -> issuePointsCall {
    issuePointsCall { users: wallets.to_vec() }
}
