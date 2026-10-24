/// Robinhood Chain mainnet and testnet. A signature is bound to its chain id, so the writer signs
/// for no other chain, whatever the RPC is.
pub const CHAIN_IDS: [u64; 2] = [4663, 46630];
/// 1 gwei, in wei. The chain runs near 0.02 gwei, so a higher price is a wrong RPC, and signing it
/// could drain the writer.
pub const MAX_GAS_PRICE: u128 = 1_000_000_000;
/// (address, kind) pairs per `balanceOfBatch`: an `eth_call` this size stays under the RPC's limits.
pub const BALANCE_PAIRS: usize = 300;
