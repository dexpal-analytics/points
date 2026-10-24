// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test, stdError} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DexPalPoints} from "../src/DexPalPoints2.sol";
import {DexPalCredits} from "../src/DexPalCredits.sol";
import {PointsConversion1} from "../src/PointsConversion.sol";

contract Plain {}

contract Token is ERC20 {
    constructor() ERC20("Numeraire", "NUM") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// USDT-style: transfer returns nothing
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

contract DexPalPointsTest is Test {
    bytes16 constant R0 = bytes16(uint128(0xA0));
    bytes16 constant R1 = bytes16(uint128(0xA1));
    address constant OWNER = address(0xA11CE);
    address constant WRITER = address(0xB0B);
    address constant USER = address(0xCAFE);
    address constant OTHER = address(0xBEEF);
    address constant ATTACKER = address(0xBAD);
    uint256 constant TX_GAS_CAP = 32_000_000;
    string constant SOULBOUND = "transferral is not permitted, wait until the credits become tokens";

    DexPalCredits.Kind constant TRADING = DexPalCredits.Kind.Trading;
    DexPalCredits.Kind constant QUEST = DexPalCredits.Kind.Quest;
    DexPalCredits.Kind constant REFERRAL = DexPalCredits.Kind.Referral;

    DexPalPoints points;
    DexPalCredits credits;
    PointsConversion1 conv;
    Token token;
    uint256 batchNonce;

    function setUp() public {
        token = new Token();
        conv = new PointsConversion1();
        credits = new DexPalCredits(OWNER, WRITER, "uri");
        points = new DexPalPoints(address(token), OWNER, address(conv), address(credits));
        vm.prank(OWNER);
        credits.setPointsContractAddress(address(points));
        token.mint(address(points), 1e30);
        open(R0, [uint256(250_000), 100_000, 150_000]);
    }

    // -------------------------------------------------------------------- e2e

    /// Full lifecycle across three rounds with four users:
    ///   alice - trader on two dexes
    ///   bob   - trader + quester, holds points across rounds before claiming
    ///   carol - quester + referrer, claims to a separate cold wallet
    ///   dave  - cheater, banned mid-round 0, stays banned forever
    ///
    /// All budgets and credit amounts are chosen so the pro-rata shares divide
    /// exactly, letting every assertion be an exact equality.
    function test_e2e_multiRound() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address carol = makeAddr("carol");
        address carolCold = makeAddr("carolCold");
        address dave = makeAddr("dave");
        bytes16 R2 = bytes16(uint128(0xA2));
        bytes16 R3 = bytes16(uint128(0xA3));
        DexPalCredits.Credit[] memory b;

        // =====================================================================
        // ROUND 0 - budgets: Trading 250k, Quest 100k, Referral 150k (opened in setUp)
        // =====================================================================

        // --- Batch r0:b1: first sync from the backend -------------------------
        b = new DexPalCredits.Credit[](4);
        b[0] = cr(alice, TRADING, "arcus", 300);
        b[1] = cr(bob, TRADING, "aster", 100);
        b[2] = cr(carol, QUEST, "arcus", 50);
        b[3] = cr(dave, TRADING, "arcus", 500);
        batch("r0:b1", b);

        // Carol is the only quester so far, so she'd take the entire quest budget.
        assertEq(pending(carol), 100_000);

        // --- Batch r0:b2: incremental deltas ---------------------------------
        b = new DexPalCredits.Credit[](4);
        b[0] = cr(alice, TRADING, "aster", 100); // second dex: adds to her arcus 300 -> 400
        b[1] = cr(bob, QUEST, "aster", 50);
        b[2] = cr(carol, REFERRAL, 0, 10);
        b[3] = cr(dave, REFERRAL, 0, 10);
        batch("r0:b2", b);
        assertEq(credits.balanceOf(alice, 0), 400);

        // Supplies now: Trading 1000 (a400 b100 d500), Quest 100 (c50 b50), Referral 20 (c10 d10).
        assertEq(pending(alice), 100_000); // 250k * 400/1000
        assertEq(pending(bob), 25_000 + 50_000); // trading 100/1000 + quest 50/100
        assertEq(pending(carol), 50_000 + 75_000); // quest 50/100 + referral 10/20
        assertEq(pending(dave), 125_000 + 75_000); // trading 500/1000 + referral 10/20

        // --- Backend retries r0:b2 (e.g. RPC timeout) -------------------------
        // The batch id was already consumed, so the retry is rejected and nobody
        // is double-credited.
        vm.expectRevert("bathc already processed");
        batch("r0:b2", b);
        assertEq(credits.balanceOf(alice, 0), 400);

        // --- Dave is caught wash trading and banned mid-round -----------------
        // His credits are burned, which shrinks the supplies, so his share is
        // redistributed pro-rata to everyone else rather than left unpaid.
        vm.prank(OWNER);
        points.banUser(dave);
        assertEq(pending(dave), 0);
        assertEq(credits.totalSupply(0), 500); // a400 b100
        assertEq(credits.totalSupply(2), 10); // c10
        assertEq(pending(alice), 200_000); // 250k * 400/500 (doubled)
        assertEq(pending(carol), 50_000 + 150_000); // now sole referrer

        // --- Backend keeps sending dave's activity; it's silently skipped ------
        b = new DexPalCredits.Credit[](1);
        b[0] = cr(dave, TRADING, "arcus", 1000);
        batch("r0:b3", b);
        assertEq(credits.balanceOf(dave, 0), 0);
        assertEq(credits.totalSupply(0), 500);

        // --- Correction: backend recomputes carol's quest total as 150 ---------
        // setCredits overwrites the per-kind balance, so it's the tool for fixes.
        write(carol, QUEST, "arcus", 150);
        // Quest supply: c150 b50 = 200.

        // Final round-0 entitlements (sum = full 500k budget):
        //   alice 200k = trading 400/500
        //   bob    75k = trading 100/500 (50k) + quest 50/200 (25k)
        //   carol 225k = quest 150/200 (75k) + referral 10/10 (150k)
        assertEq(pending(alice), 200_000);
        assertEq(pending(bob), 75_000);
        assertEq(pending(carol), 225_000);

        // --- Close round 0 ---------------------------------------------------
        close();

        // Credits are frozen: no more writes or bans.
        vm.expectRevert("state is not open");
        write(alice, TRADING, "arcus", 1);
        vm.expectRevert("cannot ban whilst closed");
        vm.prank(OWNER);
        points.banUser(alice);

        // Can't start round 1 while anyone still holds round-0 credits; that
        // would let them roll into the new budget.
        vm.expectRevert("remaining user credits left");
        open(R1, [uint256(100_000), 0, 50_000]);

        // --- Convert credits -> DPP for every holder -------------------------
        // Order doesn't matter: each withdrawal subtracts its payout from the
        // budget as it burns, so later users' shares are unchanged.
        issue(carol);
        issue(alice);
        issue(bob);
        // Dave holds no credits, so he doesn't need issuing.
        assertEq(points.balanceOf(alice), 200_000);
        assertEq(points.balanceOf(bob), 75_000);
        assertEq(points.balanceOf(carol), 225_000);
        assertEq(points.totalSupply(), 500_000);

        // Every credit burned and every budget paid out to the wei.
        for (uint256 id; id < 3; ++id) {
            assertEq(credits.totalSupply(id), 0);
            assertEq(credits.budget(DexPalCredits.Kind(id)), 0);
        }

        // --- Claims ----------------------------------------------------------
        // Alice claims straight away; carol sends to her cold wallet; bob waits.
        uint256 aliceExpected = conv.convertPoints(200_000);
        uint256 carolExpected = conv.convertPoints(225_000);
        vm.prank(alice);
        points.claimPoints(alice, alice);
        vm.prank(carol);
        points.claimPoints(carol, carolCold);
        assertEq(token.balanceOf(alice), aliceExpected);
        assertEq(token.balanceOf(carolCold), carolExpected);
        assertEq(points.balanceOf(alice), 0);
        assertEq(points.balanceOf(carol), 0);

        // =====================================================================
        // ROUND 1 - budgets: Trading 100k, Quest 0, Referral 50k
        // =====================================================================
        open(R1, [uint256(100_000), 0, 50_000]);
        assertEq(credits.roundName(), R1);

        // Batch ids are global, not per round, so the backend must namespace
        // them by round. Reusing a round-0 id is rejected.
        b = new DexPalCredits.Credit[](1);
        b[0] = cr(alice, TRADING, "arcus", 1);
        vm.expectRevert("bathc already processed");
        batch("r0:b1", b);

        b = new DexPalCredits.Credit[](4);
        b[0] = cr(alice, TRADING, "arcus", 1);
        b[1] = cr(bob, TRADING, "aster", 3);
        b[2] = cr(dave, TRADING, "arcus", 5); // still banned: skipped
        b[3] = cr(carol, REFERRAL, 0, 1);
        batch("r1:b1", b);
        assertEq(credits.balanceOf(dave, 0), 0);

        assertEq(pending(alice), 25_000); // 100k * 1/4
        assertEq(pending(bob), 75_000); // 100k * 3/4
        assertEq(pending(carol), 50_000); // sole referrer
        // Bob's prediction combines his unclaimed round-0 DPP with round-1 pending.
        assertEq(points.predictedBalanceOf(bob), 75_000 + 75_000);

        close();
        issue(alice);
        issue(bob);
        issue(carol);
        assertEq(points.balanceOf(bob), 150_000);

        // Bob claims both rounds in one go.
        uint256 bobExpected = conv.convertPoints(150_000);
        vm.prank(bob);
        points.claimPoints(bob, bob);
        assertEq(token.balanceOf(bob), bobExpected);

        aliceExpected += conv.convertPoints(25_000);
        carolExpected += conv.convertPoints(50_000);
        vm.prank(alice);
        points.claimPoints(alice, alice);
        vm.prank(carol);
        points.claimPoints(carol, carolCold);
        assertEq(token.balanceOf(alice), aliceExpected);
        assertEq(token.balanceOf(carolCold), carolExpected);

        // Everything issued has been claimed.
        assertEq(points.totalSupply(), 0);
        assertEq(token.balanceOf(address(points)), 1e30 - aliceExpected - bobExpected - carolExpected);
        assertEq(token.balanceOf(dave), 0);

        // =====================================================================
        // ROUNDS 2-3 - an empty round cycles cleanly
        // =====================================================================
        // No credits written, so supply stays 0 and the next round can open
        // immediately. R2's unspent budget is simply overwritten.
        open(R2, [uint256(1), 1, 1]);
        close();
        open(R3, [uint256(10), 10, 10]);
        assertEq(uint8(credits.state()), uint8(DexPalCredits.State.Open));
        assertEq(credits.roundName(), R3);
        assertEq(credits.budget(TRADING), 10);
    }

    // ---------------------------------------------------------------- helpers

    function cr(address user, DexPalCredits.Kind kind, bytes32 dex, uint256 amount)
        internal
        pure
        returns (DexPalCredits.Credit memory)
    {
        return DexPalCredits.Credit(user, kind, dex, amount);
    }

    function batch(string memory id, DexPalCredits.Credit[] memory entries) internal {
        vm.prank(WRITER);
        credits.increaseCredits(entries, keccak256(bytes(id)));
    }

    // ---------------------------------------------------------------- credits

    function test_setCredits() public {
        vm.expectEmit(address(credits));
        emit DexPalCredits.CreditsSet(R0, USER, "arcus", TRADING, 100);
        write(USER, TRADING, "arcus", 100);
        assertEq(credits.balanceOf(USER, 0), 100);
        assertEq(credits.totalSupply(0), 100);
    }

    function test_overwrite() public {
        write(USER, TRADING, "arcus", 100);
        write(USER, TRADING, "arcus", 100);
        assertEq(credits.totalSupply(0), 100);
        write(USER, TRADING, "arcus", 30);
        assertEq(credits.balanceOf(USER, 0), 30);
        write(USER, TRADING, "arcus", 0);
        assertEq(credits.balanceOf(USER, 0), 0);
        assertEq(credits.totalSupply(0), 0);
    }

    /// setCredits is per kind, not per dex: a second dex overwrites the first.
    function test_setCreditsIgnoresDex() public {
        write(USER, TRADING, "arcus", 30);
        write(USER, TRADING, "aster", 10);
        assertEq(credits.balanceOf(USER, 0), 10);
    }

    function test_increaseCredits() public {
        vm.expectEmit(address(credits));
        emit DexPalCredits.CreditsIncreased(R0, USER, "arcus", TRADING, 30);
        add(USER, TRADING, "arcus", 30);
        add(USER, TRADING, "aster", 10);
        assertEq(credits.balanceOf(USER, 0), 40);
        assertEq(credits.totalSupply(0), 40);
    }

    function test_batchReplay() public {
        bytes32 id = keccak256("round0:batch1");
        vm.prank(WRITER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 30), id);

        vm.expectRevert("bathc already processed");
        vm.prank(WRITER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 30), id);
        assertEq(credits.balanceOf(USER, 0), 30);

        vm.prank(WRITER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 30), keccak256("round0:batch2"));
        assertEq(credits.balanceOf(USER, 0), 60);
    }

    /// a reverted batch must not burn its id, so the backend can retry it
    function test_failedBatchRetryable() public {
        bytes32 id = keccak256("round0:batch1");
        write(OTHER, TRADING, "aster", type(uint256).max);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(WRITER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 1), id);

        write(OTHER, TRADING, "aster", 0);
        vm.prank(WRITER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 1), id);
        assertEq(credits.balanceOf(USER, 0), 1);
    }

    function test_duplicate() public {
        DexPalCredits.Credit[] memory batch = new DexPalCredits.Credit[](2);
        batch[0] = DexPalCredits.Credit(USER, TRADING, "arcus", 5);
        batch[1] = DexPalCredits.Credit(USER, TRADING, "arcus", 9);
        vm.expectEmit(address(credits));
        emit DexPalCredits.CreditsSet(R0, USER, "arcus", TRADING, 5);
        vm.expectEmit(address(credits));
        emit DexPalCredits.CreditsSet(R0, USER, "arcus", TRADING, 9);
        vm.prank(WRITER);
        credits.setCredits(batch);
        assertEq(credits.balanceOf(USER, 0), 9);
    }

    function test_empty() public {
        vm.prank(WRITER);
        credits.setCredits(new DexPalCredits.Credit[](0));
    }

    function test_badKind() public {
        bytes memory call = abi.encodeCall(credits.setCredits, (one(USER, TRADING, "arcus", 1)));
        // selector | offset | length | user | kind
        call[4 + 32 * 3 + 31] = bytes1(uint8(3));
        vm.prank(WRITER);
        (bool ok, bytes memory reason) = address(credits).call(call);
        assertFalse(ok);
        assertEq(reason.length, 0);
    }

    function test_overflow() public {
        uint256 max = type(uint256).max;
        write(USER, TRADING, "arcus", max);
        write(USER, TRADING, "arcus", max);
        assertEq(pending(USER), 250_000);

        DexPalCredits.Credit[] memory batch = new DexPalCredits.Credit[](2);
        batch[0] = DexPalCredits.Credit(OTHER, QUEST, 0, 5);
        batch[1] = DexPalCredits.Credit(OTHER, TRADING, "aster", 1);
        vm.prank(WRITER);
        vm.expectRevert(stdError.arithmeticError);
        credits.setCredits(batch);
        assertEq(credits.balanceOf(OTHER, 1), 0);
    }

    function test_batch() public {
        DexPalCredits.Credit[] memory batch = new DexPalCredits.Credit[](200);
        for (uint256 i; i < batch.length; ++i) {
            batch[i] = DexPalCredits.Credit(address(uint160(i + 1)), TRADING, "arcus", i + 1);
        }
        vm.prank(WRITER);
        uint256 start = gasleft();
        credits.setCredits(batch);
        assertLt(start - gasleft(), TX_GAS_CAP / 2);
        assertEq(credits.balanceOf(address(200), 0), 200);
    }

    function test_onlyWriter() public {
        vm.expectRevert("you are not the writer");
        vm.prank(ATTACKER);
        credits.setCredits(one(USER, TRADING, "arcus", 1));
        vm.expectRevert("you are not the writer");
        vm.prank(OWNER);
        credits.setCredits(one(USER, TRADING, "arcus", 1));
        vm.expectRevert("you are not the writer");
        vm.prank(ATTACKER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 1), bytes32(0));
    }

    function test_roundNotOpen() public {
        close();
        vm.expectRevert("state is not open");
        write(USER, TRADING, "arcus", 1);
        vm.expectRevert("state is not open");
        add(USER, TRADING, "arcus", 1);
    }

    function test_soulbound() public {
        write(USER, TRADING, "arcus", 10);
        vm.expectRevert(bytes(SOULBOUND));
        vm.prank(USER);
        credits.safeTransferFrom(USER, OTHER, 0, 1, "");

        uint256[] memory ids = new uint256[](1);
        uint256[] memory vals = new uint256[](1);
        vals[0] = 1;
        vm.expectRevert(bytes(SOULBOUND));
        vm.prank(USER);
        credits.safeBatchTransferFrom(USER, OTHER, ids, vals, "");
    }

    function test_contractRecipient() public {
        address c = address(new Plain());
        write(c, TRADING, "arcus", 5);
        assertEq(credits.balanceOf(c, 0), 5);
    }

    function test_onlyPointsContract() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        credits.openRound(R1, [uint256(1), 1, 1]);
        vm.expectRevert();
        credits.closeRound();
        vm.expectRevert();
        credits.banUser(USER);
        vm.expectRevert();
        credits.withdrawPoints(USER);
        vm.expectRevert();
        credits.pointsBalanceOf(USER);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------- points

    function test_points() public {
        write(USER, TRADING, "arcus", 30);
        write(OTHER, TRADING, "aster", 10);
        write(USER, QUEST, "arcus", 1);
        assertEq(pending(USER), 187_500 + 100_000);
        assertEq(pending(OTHER), 62_500);
    }

    /// last withdrawer sweeps the rounding dust, so the full budget is paid out
    function test_rounding() public {
        close();
        open(R1, [uint256(100), 0, 0]);
        write(USER, TRADING, "arcus", 1);
        write(OTHER, TRADING, "arcus", 1);
        write(ATTACKER, TRADING, "arcus", 1);
        assertEq(pending(USER), 33);
        assertEq(pending(USER) + pending(OTHER) + pending(ATTACKER), 99);

        close();
        issue(USER);
        issue(OTHER);
        issue(ATTACKER);
        assertEq(points.balanceOf(USER), 33);
        assertEq(points.balanceOf(OTHER), 33);
        assertEq(points.balanceOf(ATTACKER), 34);
        assertEq(points.totalSupply(), 100);
        assertEq(credits.budget(TRADING), 0);
    }

    function testFuzz_split(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, 1e30);
        b = bound(b, 0, 1e30);
        c = bound(c, 0, 1e30);
        write(USER, TRADING, "arcus", a);
        write(OTHER, TRADING, "aster", b);
        write(ATTACKER, REFERRAL, 0, c);

        uint256 pu = pending(USER);
        uint256 po = pending(OTHER);
        assertLe(pu + po, 250_000);
        if (a + b > 0) assertGe(pu + po, 250_000 - 1);
        assertEq(pending(ATTACKER), c > 0 ? 150_000 : 0);

        close();
        issue(OTHER);
        issue(USER);
        assertEq(points.balanceOf(OTHER), po);
        assertGe(points.balanceOf(USER), pu);
        if (a + b > 0) assertEq(points.balanceOf(USER) + points.balanceOf(OTHER), 250_000);
    }

    function test_issue() public {
        write(USER, TRADING, "arcus", 30);
        write(OTHER, TRADING, "aster", 10);
        close();
        issue(USER);
        assertEq(points.balanceOf(USER), 187_500);
        assertEq(points.predictedBalanceOf(USER), 187_500);
        assertEq(pending(USER), 0);
        assertEq(credits.balanceOf(USER, 0), 0);
        assertEq(credits.budget(TRADING), 62_500);
        assertEq(pending(OTHER), 62_500);
    }

    function test_issueNeedsClosed() public {
        write(USER, TRADING, "arcus", 1);
        vm.expectRevert("state needs to be closed");
        issue(USER);
    }

    function test_issueOnlyOwner() public {
        close();
        vm.expectRevert(unauthorized(WRITER));
        vm.prank(WRITER);
        points.issuePoints(USER);
    }

    function test_claim() public {
        write(USER, TRADING, "arcus", 30);
        write(OTHER, TRADING, "aster", 10);
        close();
        issue(USER);
        uint256 expected = conv.convertPoints(points.balanceOf(USER));

        vm.expectRevert("only the owner of the points can call this");
        vm.prank(ATTACKER);
        points.claimPoints(USER, ATTACKER);

        vm.prank(USER);
        points.claimPoints(USER, OTHER);
        assertEq(token.balanceOf(OTHER), expected);
        assertEq(points.balanceOf(USER), 0);

        vm.prank(USER);
        points.claimPoints(USER, OTHER);
        assertEq(token.balanceOf(OTHER), expected);
    }

    /// fails with a raw `transfer`, passes once claimPoints uses SafeERC20
    function test_claimNoReturnToken() public {
        NoReturnToken usdt = new NoReturnToken();
        usdt.mint(address(points), 1e30);
        vm.prank(OWNER);
        points.updateNumeraire(address(usdt));

        write(USER, TRADING, "arcus", 1);
        close();
        issue(USER);
        uint256 expected = conv.convertPoints(points.balanceOf(USER));
        vm.prank(USER);
        points.claimPoints(USER, USER);
        assertEq(usdt.balanceOf(USER), expected);
    }

    // ----------------------------------------------------------------- rounds

    function test_openRound() public {
        vm.expectRevert(unauthorized(WRITER));
        vm.prank(WRITER);
        points.openRound(R1, [uint256(1), 1, 1]);

        vm.expectRevert("call closeRound first");
        open(R1, [uint256(1), 1, 1]);

        close();
        vm.expectEmit(address(credits));
        emit DexPalCredits.RoundOpened(R1, [uint256(500), 0, 0]);
        open(R1, [uint256(500), 0, 0]);
        assertEq(credits.budget(TRADING), 500);
        assertEq(credits.roundName(), R1);
    }

    function test_rolloverGate() public {
        write(USER, TRADING, "arcus", 1);
        close();
        vm.expectRevert("remaining user credits left");
        open(R1, [uint256(1000), 0, 0]);

        issue(USER);
        open(R1, [uint256(1000), 0, 0]);
        assertEq(credits.budget(TRADING), 1000);
    }

    function test_closeRound() public {
        vm.expectRevert(unauthorized(WRITER));
        vm.prank(WRITER);
        points.closeRound();

        close();
        assertEq(uint8(credits.state()), uint8(DexPalCredits.State.Closed));
        vm.expectRevert("state needs to be open");
        close();
    }

    // ------------------------------------------------------------------- bans

    function test_ban() public {
        write(USER, TRADING, "arcus", 30);
        write(OTHER, TRADING, "aster", 10);

        vm.expectRevert(unauthorized(ATTACKER));
        vm.prank(ATTACKER);
        points.banUser(USER);

        vm.prank(OWNER);
        points.banUser(USER);
        assertEq(pending(USER), 0);
        assertEq(credits.balanceOf(USER, 0), 0);
        // banned share is redistributed, not withheld
        assertEq(pending(OTHER), 250_000);

        DexPalCredits.Credit[] memory batch = new DexPalCredits.Credit[](2);
        batch[0] = DexPalCredits.Credit(USER, TRADING, "arcus", 999);
        batch[1] = DexPalCredits.Credit(OTHER, TRADING, "aster", 20);
        vm.prank(WRITER);
        credits.setCredits(batch);
        add(USER, TRADING, "arcus", 5);
        assertEq(credits.balanceOf(USER, 0), 0);
        assertEq(credits.balanceOf(OTHER, 0), 20);

        close();
        vm.expectRevert("cannot ban whilst closed");
        vm.prank(OWNER);
        points.banUser(OTHER);
    }

    function test_banPersistsAcrossRounds() public {
        vm.prank(OWNER);
        points.banUser(USER);
        close();
        open(R1, [uint256(1000), 0, 0]);
        write(USER, TRADING, "arcus", 1);
        assertEq(credits.balanceOf(USER, 0), 0);
    }

    // ------------------------------------------------------------------ admin

    function test_setters() public {
        vm.startPrank(ATTACKER);
        vm.expectRevert(unauthorized(ATTACKER));
        points.updateNumeraire(ATTACKER);
        vm.expectRevert(unauthorized(ATTACKER));
        points.updatePointsConversion(ATTACKER);
        vm.expectRevert(unauthorized(ATTACKER));
        points.updateCreditsContractAddress(ATTACKER);
        vm.expectRevert(unauthorized(ATTACKER));
        credits.setPointsContractAddress(ATTACKER);
        vm.expectRevert(unauthorized(ATTACKER));
        credits.updateWriter(ATTACKER);
        vm.stopPrank();
    }

    function test_updateWriter() public {
        vm.expectEmit(address(credits));
        emit DexPalCredits.WriterSet(USER);
        vm.prank(OWNER);
        credits.updateWriter(USER);

        vm.expectRevert("you are not the writer");
        write(USER, TRADING, "arcus", 1);
        vm.prank(USER);
        credits.setCredits(one(USER, TRADING, "arcus", 1));
        assertEq(credits.balanceOf(USER, 0), 1);
    }

    function test_twoStepOwner() public {
        vm.expectRevert(unauthorized(ATTACKER));
        vm.prank(ATTACKER);
        points.transferOwnership(ATTACKER);

        vm.prank(OWNER);
        points.transferOwnership(USER);
        assertEq(points.owner(), OWNER);
        vm.expectRevert(unauthorized(ATTACKER));
        vm.prank(ATTACKER);
        points.acceptOwnership();
        vm.prank(USER);
        points.acceptOwnership();
        assertEq(points.owner(), USER);
        vm.expectRevert(unauthorized(OWNER));
        vm.prank(OWNER);
        points.closeRound();
    }

    // ---------------------------------------------------------------- helpers

    function open(bytes16 round, uint256[3] memory budget) internal {
        vm.prank(OWNER);
        points.openRound(round, budget);
    }

    function close() internal {
        vm.prank(OWNER);
        points.closeRound();
    }

    function issue(address user) internal {
        vm.prank(OWNER);
        points.issuePoints(user);
    }

    function pending(address user) internal view returns (uint256) {
        return points.predictedBalanceOf(user) - points.balanceOf(user);
    }

    function one(address user, DexPalCredits.Kind kind, bytes32 dex, uint256 amount)
        internal
        pure
        returns (DexPalCredits.Credit[] memory entries)
    {
        entries = new DexPalCredits.Credit[](1);
        entries[0] = DexPalCredits.Credit(user, kind, dex, amount);
    }

    function write(address user, DexPalCredits.Kind kind, bytes32 dex, uint256 amount) internal {
        vm.prank(WRITER);
        credits.setCredits(one(user, kind, dex, amount));
    }

    function add(address user, DexPalCredits.Kind kind, bytes32 dex, uint256 amount) internal {
        vm.prank(WRITER);
        credits.increaseCredits(one(user, kind, dex, amount), bytes32(++batchNonce));
    }

    function unauthorized(address account) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, account);
    }
}
