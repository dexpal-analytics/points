# DexPal Points Contract Suite

DexPal Points distribution on [Robinhood Chain](https://docs.robinhood.com/chain).

## Preamble

As an improvement to our rewards system, we are moving the points accounting on chain. Our backend will still receive user activity from our partner DEXes, but the rounds, credit assignment and point calculations can all easily fit inside a few smart contracts, as can the USDG redemption of points.

## Credit types

A round has a Points budget for each source of Credit: trading, quest and referral.

Each budget is shared among the wallets that hold that kind of Credit, in proportion to their
Credits:

```
points(round, wallet) = Σ over kinds of budget[kind] × credits(wallet, kind) / total credits(kind)
```

Points figures are estimates until the round closes.

Kinds are `0` = Trading, `1` = Quest, `2` = Referral.

## Deployments

Robinhood Chain testnet (chain id 46630). Each contract is an exact match on Sourcify.

| Contract | Address |
|---|---|
| DexPalPoints | [`0x83bF918864bc1342c71f240f531b30AE557B15D4`](https://explorer.testnet.chain.robinhood.com/address/0x83bF918864bc1342c71f240f531b30AE557B15D4) |
| DexPalCredits | [`0x0Bbbb0B97F168cD9188Fe2Be242557c6D69D82B9`](https://explorer.testnet.chain.robinhood.com/address/0x0Bbbb0B97F168cD9188Fe2Be242557c6D69D82B9) |
| PointsConversion | [`0x4Bd95ba7197C8e7189c56F8dD040818f873098A6`](https://explorer.testnet.chain.robinhood.com/address/0x4Bd95ba7197C8e7189c56F8dD040818f873098A6) |
| Test numeraire (NUM, public mint) | [`0x276a9590b865307BF0e6b1571B9b702F27C8e620`](https://explorer.testnet.chain.robinhood.com/address/0x276a9590b865307BF0e6b1571B9b702F27C8e620) |

The testnet rate is a placeholder: `UNITS_PER_POINT` is 1e16, so one Point pays 0.01 NUM.

## Rounds

| Call | Who | Does |
|---|---|---|
| `openRound(name, [trading, quest, referral])` | owner | Opens a round with its budgets |
| `setCredits([(wallet, kind, dex, credits), ...])` | writer | Sets each wallet's Credits of a kind (while the round is open) |
| `increaseCredits([(wallet, kind, dex, credits), ...], batchId)` | writer | Adds Credits once per batch id (while the round is open) |
| `banUser(wallet)` | owner | Burns the wallet's Credits and bans it for good (while the round is open) |
| `closeRound()` | owner | Freezes the round. Its Points become final |
| `issuePoints([wallet, ...])` | anyone | After the close, burns each wallet's Credits and mints its Points; a banned wallet gets 0. At most 400 wallets per transaction under a 32M gas cap |
| `claimPoints(from, to)` | the wallet `from` | Burns all of `from`'s Points and pays `to` their value in the numeraire |
| `sweep(token, to, amount)` | owner | Moves a token out; for the numeraire, only the surplus above what is issued and owed |

A banned wallet's share goes to the rest of the round.

## Reading

**DexPalPoints**

| Call | Returns |
|---|---|
| `predictedBalanceOf(wallet)` | A wallet's issued Points plus its pending share of the current round |
| `predictedBalanceOfConverted(wallet)` | The same, converted to the numeraire |
| `balanceOf(wallet)` | Points already issued and claimable now |
| `balanceOfConverted(wallet)` | The numeraire a claim would pay out right now |
| `totalSupply()` | All issued, unclaimed Points |
| `numeraire()`, `pointsConversion()`, `creditsContractAddress()` | The payout token, the conversion contract and the linked Credits contract, fixed at deploy |

**DexPalCredits**

| Call | Returns |
|---|---|
| `roundName()`, `state()` | The current round and whether it's `Open` or `Closed` |
| `budget(kind)` | The kind's remaining budget for the current round (this falls as wallets are issued after close) |
| `balanceOf(wallet, kind)` | A wallet's Credits of one kind in the current round |
| `totalSupply(kind)` | All outstanding Credits of one kind |
| `processed(batchId)` | Whether a credit batch has already been applied |
| `writer()`, `pointsContractAddress()` | The backend writer and the linked Points contract, fixed at deploy |
| `isBanned(wallet)`, `bannedUsers()` | Whether a wallet is banned, and every banned wallet |
| `owedPoints()` | The Points still pending: the budgets of the kinds that have Credits |

## Roles

- **Writer**: a hot key that calls `setCredits` and `increaseCredits`.
- **Owner**: a cold key or a Safe. It configures and closes rounds, sweeps the surplus, and
  replaces the writer with `updateWriter`. The payout token, the rate and the linked contracts
  cannot be changed. `updateWriter(address(0))` pauses all writes. Ownership
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
NUMERAIRE=0x... OWNER=0x... WRITER=0x... URI=... UNITS_PER_POINT=... \
  forge script script/Deploy2.s.sol --rpc-url robinhood_testnet \
  --broadcast --private-key $DEPLOYER_KEY --verify --verifier sourcify
```

`UNITS_PER_POINT` is the numeraire's base units paid per whole Point (Points have 18 decimals).
The deployer need not be the owner.
