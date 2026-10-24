use alloy::contract;
use alloy::primitives::{Address, TxHash};
use alloy::transports::TransportError;
use alloy::transports::http::reqwest;

use crate::limits::MAX_GAS_PRICE;

pub type Result<T> = std::result::Result<T, Error>;

/// No variant carries a key: a key is never formatted.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("the writer key is not a hex private key")]
    Key,
    #[error("the HTTP client could not be built: {0}")]
    Client(reqwest::Error),
    #[error("the RPC serves chain {0}, not Robinhood Chain")]
    WrongChain(u64),
    #[error("the RPC asks {0} wei of gas, over {MAX_GAS_PRICE}")]
    GasPrice(u128),
    #[error("Credits at {credits} names Points {named}, not {points}")]
    Unlinked { credits: Address, named: Address, points: Address },
    #[error("Credits' writer is {writer}, not this signer {signer}")]
    NotWriter { writer: Address, signer: Address },
    #[error("{method} {hash} reverted")]
    Reverted { method: &'static str, hash: TxHash },
    #[error("{method} {hash}: no receipt after {polls} polls")]
    NoReceipt { method: &'static str, hash: TxHash, polls: usize },
    #[error("balanceOfBatch answered {got} balances for {asked} pairs")]
    Balances { asked: usize, got: usize },
    /// The transport's own text is dropped: reqwest's ends with the URL, which may hold a key.
    #[error("rpc: transport failed")]
    Transport,
    /// Never a transport failure, so its text is the node's: a revert reason, or a decode error.
    #[error("contract call: {0}")]
    Call(contract::Error),
    /// Never a transport failure, as for `Call`.
    #[error("rpc: {0}")]
    Rpc(TransportError),
}

impl From<TransportError> for Error {
    fn from(error: TransportError) -> Self {
        if error.is_transport_error() { Self::Transport } else { Self::Rpc(error) }
    }
}

impl From<contract::Error> for Error {
    fn from(error: contract::Error) -> Self {
        match error {
            contract::Error::TransportError(error) if error.is_transport_error() => Self::Transport,
            error => Self::Call(error),
        }
    }
}
