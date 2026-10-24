use alloy::primitives::Address;
use alloy::transports::http::reqwest::Url;
use alloy::transports::mock::Asserter;

use crate::error::Error;
use crate::mock_test::{POINTS, provider};
use crate::reader::Reader;

const KEY: &str = "0123456789abcdef";

/// reqwest refuses an `ftp` URL before it connects, and its error ends with the URL, as a timeout's
/// or a refused connection's does.
#[tokio::test]
async fn a_transport_failure_names_no_url() {
    let rpc = Url::parse(&format!("ftp://127.0.0.1/v2/{KEY}")).expect("a URL");
    let reader = Reader::new(rpc, POINTS).expect("a reader");
    let error = reader.points_of(Address::ZERO).await.expect_err("refused");
    assert!(matches!(error, Error::Transport), "{error}");
    assert!(!format!("{error} {error:?}").contains(KEY), "{error:?}");
}

#[tokio::test]
async fn an_error_response_keeps_the_node_text() {
    let asserter = Asserter::new();
    asserter.push_failure_msg("execution reverted: not the writer");
    let error = Reader::on(provider(&asserter), POINTS).points_of(Address::ZERO).await.expect_err("reverted");
    assert!(error.to_string().contains("execution reverted: not the writer"), "{error}");
}
