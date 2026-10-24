use std::time::Duration;

use alloy::transports::http::reqwest::Client;
use alloy::transports::http::reqwest::redirect::Policy;

use crate::error::{Error, Result};

/// A JSON-RPC endpoint does not redirect, and following one would send the calls to a host nobody
/// configured.
pub(crate) fn client(timeout: Duration) -> Result<Client> {
    Client::builder().timeout(timeout).redirect(Policy::none()).build().map_err(Error::Client)
}
