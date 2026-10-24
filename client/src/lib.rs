//! DexPal's backend client for the points suite, DexPalPoints and DexPalCredits: writer and read
//! calls only. The owner's calls (openRound, closeRound, banUser, sweep) are left out on purpose:
//! the backend never holds the owner key.

mod abi;
mod error;
mod http;
mod limits;
mod reader;
mod suite;
mod writer;

#[cfg(test)]
mod abi_test;
#[cfg(test)]
mod error_test;
#[cfg(test)]
mod mock_test;
#[cfg(test)]
mod suite_test;

pub use abi::DexPalCredits::Kind;
pub use alloy::primitives::{Address, FixedBytes, TxHash, U256};
pub use alloy::signers::local::PrivateKeySigner;
pub use alloy::transports::http::reqwest::Url;
pub use error::{Error, Result};
pub use reader::{PointsOf, Reader};
pub use suite::Suite;
pub use writer::{Writer, parse_key};
