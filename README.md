# DexPal Points Contract Suite

DexPal Points distribution on [Robinhood Chain](https://docs.robinhood.com/chain).

## Preamble

As an improvement to our rewards system, we are moving the points accounting on chain. Our backend will still receive user activity from our partner DEXes, but the rounds, credit assignment and point calculations can all easily fit inside a few smart contracts, as can the USDG redemption of points.

## Credit types

A round has a Points budget for each source of Credit: trading, quest and referral.

Each budget is
shared among the wallets that hold that kind of Credit, in proportion to their Credits:

```
points(round, wallet) = Σ over kinds of  budget[kind] × credits(wallet, kind) / total credits(kind)
```

Points figures estimated until the round ends.

## Contract Addresses Robinhood Testnet

- DexPalPoints 0x236cB56b71942a78a93F1494a00E48C67b5CB4dC  
- DexPalCredits 0x41029D3DcA18827E80d726f5E6577e65B05df9Ea

## Rounds

| Call | Who | Does |
|---|---|---|
| `openRound([trading, quest, referral])` | owner | Opens a round with its budgets |
| `increaseCredits([(wallet, kind, dex, credits), ...])` | writer | updates Credits (while the round is open) |
| `ban(wallet)` | owner or writer | Voids the wallet's Points (+ban) |
| `closeRound(round)` | owner | Freezes the round. Its Points become final, and the credits are burned |

A disqualified wallet's share is not reallocated in the current round.

IDs are `0` trading, `1` quest,
`2` referral.

## Reading

**DexPalPoints**

| Call | Returns |
|---|---|
| `predictedBalanceOf(wallet)` | A wallet's issued Points plus its pending share of the current round |
| `predictedBalanceOfConverted(wallet)` | The same, converted to the numeraire |
| `balanceOf(wallet)` | Points already issued and claimable now |
| `balanceOfConverted(wallet)` | The numeraire a claim would pay out right now |
| `totalSupply()` | All issued, unclaimed Points |
| `numeraire()`, `pointsConversion()`, `creditsContractAddress()` | The payout token, the conversion contract and the linked Credits contract |

**DexPalCredits**

| Call | Returns |
|---|---|
| `roundName()`, `state()` | The current round and whether it's `Open` or `Closed` |
| `budget(kind)` | The kind's remaining budget for the current round (this falls as wallets are issued after close) |
| `balanceOf(wallet, kind)` | A wallet's Credits of one kind in the current round |
| `totalSupply(kind)` | All outstanding Credits of one kind |
| `processed(batchId)` | Whether a credit batch has already been applied |
| `writer()`, `pointsContractAddress()` | The backend writer and the linked Points contract |

Kinds are `0` = Trading, `1` = Quest, `2` = Referral.

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
