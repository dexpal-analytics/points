# DexPal Points

DexPal Points distribution on [Robinhood Chain](https://docs.robinhood.com/chain).

## Credit types

A round has a Points budget for each source of Credit: trading, quest and referral.

Each budget is
shared among the wallets that hold that kind of Credit, in proportion to their Credits:

```
points(round, wallet) = Σ over kinds of  budget[kind] × credits(wallet, kind) / total credits(kind)
```

Points figures estimated until the round ends.

## Contract Addresses Robinhood Testnet

- Points Contract: 0xcbfb4f85eedcf32b94b2db6121588ac508d0ef05
- Credits Contract: 0x384d86a09fa21fd010223ceb8bf04b3025d86e92

## Rounds

| Call | Who | Does |
|---|---|---|
| `openRound(round, [trading, quest, referral])` | owner | Opens a round with its budgets |
| `setCredits(round, [(wallet, kind, dex, credits), ...])` | writer | Records Credits (while the round is open) |
| `disqualify(round, wallet)` | owner or writer | Voids the wallet's Points in an open round (+ban) |
| `requalify(round, wallet)` | owner | Undoes a disqualification |
| `closeRound(round)` | owner | Freezes the round. Its Points become final |

A disqualified wallet's share is not reallocated in the current round.

`setCredits` overwrites, so resending a batch changes nothing, and writing 0 takes Credits back.
Keep batches to 200 entries. A transaction is capped at 32M gas, and 200 new entries cost about
10.6M.

IDs are `0` trading, `1` quest,
`2` referral.

## Reading

| Call | Returns |
|---|---|
| `points(round, wallet)` | A wallet's Points in one round |
| `lifetime(wallet)` | A wallet's Points across all closed rounds |
| `getRound(round)` | The budgets, the total Credits per kind, and the state |
| `userCredits(round, wallet, kind)` | A wallet's Credits of one kind |
| `dexCredits(round, dex)` | All trading Credits earned through one dex, for statistics |
| `credits(round, wallet, kind, dex)` | One recorded entry |
| `disqualified(round, wallet)`, `disqualifiedUsers(round)` | Whether a wallet is banned for the round, and every banned wallet |

## Roles

- **Writer**: a hot key that calls `setCredits`.
- **Owner**: a cold key or a Safe. It configures and closes rounds, upgrades the contract (UUPS),
  and replaces the writer with `setWriter`. `setWriter(address(0))` pauses all writes. Ownership
  moves require two steps (`transferOwnership`, then `acceptOwnership`), and cannot be renounced.

## Build and test

Requires [Foundry](https://getfoundry.sh) 1.8.6.

```sh
forge soldeer install
forge test
forge coverage --no-match-coverage "dependencies|test"
```

## Deploy

```sh
OWNER=0x... WRITER=0x... forge script script/Deploy.s.sol --rpc-url robinhood_testnet \
  --broadcast --private-key $DEPLOYER_KEY --verify --verifier sourcify
```

## Deployments

| Network | Chain id | Proxy | Implementation |
|---|---|---|---|
| Robinhood Chain testnet | 46630 | `0x52cEca0a4d5Ac51c09dF3B46B55aF7d8F25241d1` | `0x91A549F50A03B352ff7b922bd34AbE3b78926dE3` |
