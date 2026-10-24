// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test, Vm, stdError} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DexPalPoints} from "../src/DexPalPoints2.sol";
import {DexPalCredits} from "../src/DexPalCredits.sol";
import {PointsConversion} from "../src/PointsConversion.sol";

contract Plain {}

contract Token is ERC20 {
    constructor() ERC20("Numeraire", "NUM") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function move(address from, address to, uint256 amount) external {
        _transfer(from, to, amount);
    }
}

contract Alias {
    Token immutable token;

    constructor(Token token_) {
        token = token_;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        token.move(msg.sender, to, amount);
        return true;
    }
}

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

contract SuiteTest is Test {
    bytes16 constant R0 = bytes16(uint128(0xA0));
    bytes16 constant R1 = bytes16(uint128(0xA1));
    address constant OWNER = address(0xA11CE);
    address constant WRITER = address(0xB0B);
    address constant USER = address(0xCAFE);
    address constant OTHER = address(0xBEEF);
    address constant ATTACKER = address(0xBAD);
    uint256 constant E = 1e18;
    uint256 constant UNITS = 1e6;
    uint256 constant TX_GAS_CAP = 32_000_000;
    uint256 constant ISSUE_BATCH = 400;
    string constant SOULBOUND = "credits are not transferable";
    string constant OWED = "sweep would take what is owed";

    DexPalCredits.Kind constant TRADING = DexPalCredits.Kind.Trading;
    DexPalCredits.Kind constant QUEST = DexPalCredits.Kind.Quest;
    DexPalCredits.Kind constant REFERRAL = DexPalCredits.Kind.Referral;

    DexPalPoints points;
    DexPalCredits credits;
    PointsConversion conv;
    Token token;
    uint256 batchNonce;

    function setUp() public {
        token = new Token();
        (points, credits) = build(address(token));
        conv = PointsConversion(points.pointsConversion());
        token.mint(address(points), 1e30);
        open(R0, [250_000 * E, 100_000 * E, 150_000 * E]);
    }

    function test_e2e() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address carol = makeAddr("carol");
        address cold = makeAddr("cold");
        address dave = makeAddr("dave");
        DexPalCredits.Credit[] memory b = new DexPalCredits.Credit[](4);
        b[0] = cr(alice, TRADING, "arcus", 300);
        b[1] = cr(bob, TRADING, "aster", 100);
        b[2] = cr(carol, QUEST, "arcus", 50);
        b[3] = cr(dave, TRADING, "arcus", 500);
        batch("r0:b1", b);
        assertEq(pending(carol), 100_000 * E);

        b[0] = cr(alice, TRADING, "aster", 100);
        b[1] = cr(bob, QUEST, "aster", 50);
        b[2] = cr(carol, REFERRAL, 0, 10);
        b[3] = cr(dave, REFERRAL, 0, 10);
        batch("r0:b2", b);
        assertEq(pending(alice), 100_000 * E);
        assertEq(pending(bob), 75_000 * E);
        assertEq(pending(dave), 200_000 * E);

        vm.expectRevert("batch already processed");
        batch("r0:b2", b);

        ban(dave);
        assertEq(pending(dave), 0);
        assertEq(pending(alice), 200_000 * E);
        assertEq(pending(carol), 200_000 * E);

        write(carol, QUEST, "arcus", 150);
        close();
        assertEq(credits.owedPoints(), 500_000 * E);

        vm.expectRevert("remaining user credits left");
        open(R1, [uint256(1), 0, 0]);

        address[] memory list = new address[](4);
        list[0] = carol;
        list[1] = dave;
        list[2] = alice;
        list[3] = bob;
        vm.prank(ATTACKER);
        points.issuePoints(list);
        assertEq(points.balanceOf(alice), 200_000 * E);
        assertEq(points.balanceOf(bob), 75_000 * E);
        assertEq(points.balanceOf(carol), 225_000 * E);
        assertEq(points.balanceOf(dave), 0);
        assertEq(credits.owedPoints(), 0);
        for (uint256 id; id < 3; ++id) {
            assertEq(credits.totalSupply(id), 0);
            assertEq(credits.budget(DexPalCredits.Kind(id)), 0);
        }

        vm.prank(carol);
        points.claimPoints(carol, cold);
        assertEq(token.balanceOf(cold), 225_000 * UNITS);

        open(R1, [100_000 * E, 0, 0]);
        b = new DexPalCredits.Credit[](2);
        b[0] = cr(bob, TRADING, "aster", 3);
        b[1] = cr(dave, TRADING, "arcus", 5);
        batch("r1:b1", b);
        assertEq(points.predictedBalanceOf(bob), 175_000 * E);
        close();
        issue(bob);
        vm.prank(bob);
        points.claimPoints(bob, bob);
        assertEq(token.balanceOf(bob), 175_000 * UNITS);
        assertEq(token.balanceOf(dave), 0);
    }

    function test_setCredits() public {
        vm.expectEmit(address(credits));
        emit DexPalCredits.CreditsSet(R0, USER, "arcus", TRADING, 100);
        write(USER, TRADING, "arcus", 100);
        write(USER, TRADING, "aster", 30);
        assertEq(credits.balanceOf(USER, 0), 30);
        assertEq(credits.totalSupply(0), 30);
        write(USER, TRADING, "arcus", 0);
        assertEq(credits.totalSupply(), 0);
    }

    function test_increaseCredits() public {
        vm.expectEmit(address(credits));
        emit DexPalCredits.CreditsIncreased(R0, USER, "arcus", TRADING, 30);
        add(USER, TRADING, "arcus", 30);
        add(USER, TRADING, "aster", 10);
        assertEq(credits.balanceOf(USER, 0), 40);
    }

    function test_replay() public {
        bytes32 id = keccak256("r0:b1");
        vm.startPrank(WRITER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 30), id);
        assertTrue(credits.processed(id));
        vm.expectRevert("batch already processed");
        credits.increaseCredits(one(USER, TRADING, "arcus", 30), id);
        vm.stopPrank();
        close();
        issue(USER);
        open(R1, [uint256(1), 1, 1]);
        vm.expectRevert("batch already processed");
        vm.prank(WRITER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 30), id);
    }

    function test_retry() public {
        bytes32 id = keccak256("r0:b1");
        write(OTHER, TRADING, "aster", type(uint256).max);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(WRITER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 1), id);
        assertFalse(credits.processed(id));
        write(OTHER, TRADING, "aster", 0);
        vm.prank(WRITER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 1), id);
        assertEq(credits.balanceOf(USER, 0), 1);
    }

    function test_badKind() public {
        bytes memory call = abi.encodeCall(credits.setCredits, (one(USER, TRADING, "arcus", 1)));
        call[4 + 32 * 3 + 31] = bytes1(uint8(3));
        vm.prank(WRITER);
        (bool ok, bytes memory reason) = address(credits).call(call);
        assertFalse(ok);
        assertEq(reason.length, 0);
    }

    function test_writeBatch() public {
        DexPalCredits.Credit[] memory b = new DexPalCredits.Credit[](200);
        for (uint256 i; i < b.length; ++i) {
            b[i] = cr(address(uint160(i + 1)), TRADING, "arcus", i + 1);
        }
        vm.prank(WRITER);
        uint256 start = gasleft();
        credits.setCredits(b);
        assertLt(start - gasleft(), TX_GAS_CAP / 2);
    }

    function test_onlyWriter() public {
        vm.expectRevert("you are not the writer");
        vm.prank(OWNER);
        credits.setCredits(one(USER, TRADING, "arcus", 1));
        vm.expectRevert("you are not the writer");
        vm.prank(ATTACKER);
        credits.increaseCredits(one(USER, TRADING, "arcus", 1), bytes32(0));
    }

    function test_notOpen() public {
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
    }

    function test_contractHolder() public {
        address c = address(new Plain());
        write(c, TRADING, "arcus", 5);
        assertEq(credits.balanceOf(c, 0), 5);
    }

    function test_onlyPoints() public {
        vm.startPrank(OWNER);
        vm.expectRevert("you are not the points contract");
        credits.openRound(R1, [uint256(1), 1, 1]);
        vm.expectRevert("you are not the points contract");
        credits.closeRound();
        vm.expectRevert("you are not the points contract");
        credits.banUser(USER);
        vm.expectRevert("you are not the points contract");
        credits.withdrawPoints(USER);
        vm.expectRevert("you are not the points contract");
        credits.pointsBalanceOf(USER);
        vm.stopPrank();
    }

    function test_share() public {
        write(USER, TRADING, "arcus", 30);
        write(OTHER, TRADING, "aster", 10);
        write(USER, QUEST, "arcus", 1);
        assertEq(pending(USER), 287_500 * E);
        assertEq(pending(OTHER), 62_500 * E);
        assertEq(points.predictedBalanceOfConverted(USER), 287_500 * UNITS);
    }

    function test_dust() public {
        close();
        open(R1, [uint256(100), 0, 0]);
        write(USER, TRADING, "arcus", 1);
        write(OTHER, TRADING, "arcus", 1);
        write(ATTACKER, TRADING, "arcus", 1);
        close();
        issue(USER);
        issue(OTHER);
        issue(ATTACKER);
        assertEq(points.balanceOf(USER), 33);
        assertEq(points.balanceOf(ATTACKER), 34);
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
        assertLe(pu + po, 250_000 * E);
        assertEq(pending(ATTACKER), c > 0 ? 150_000 * E : 0);
        close();
        issue(OTHER);
        issue(USER);
        assertEq(points.balanceOf(OTHER), po);
        assertGe(points.balanceOf(USER), pu);
        if (a + b > 0) assertEq(points.balanceOf(USER) + points.balanceOf(OTHER), 250_000 * E);
    }

    function test_issue() public {
        write(USER, TRADING, "arcus", 30);
        write(OTHER, TRADING, "aster", 10);
        close();
        issue(USER);
        assertEq(points.balanceOf(USER), 187_500 * E);
        assertEq(points.predictedBalanceOf(USER), 187_500 * E);
        assertEq(credits.budget(TRADING), 62_500 * E);
        assertEq(pending(OTHER), 62_500 * E);
        issue(USER);
        assertEq(points.balanceOf(USER), 187_500 * E);
    }

    function test_issueOpen() public {
        write(USER, TRADING, "arcus", 1);
        vm.expectRevert("state needs to be closed");
        issue(USER);
    }

    function test_issueStranger() public {
        write(USER, TRADING, "arcus", 1);
        close();
        vm.prank(ATTACKER);
        points.issuePoints(users(USER));
        assertEq(points.balanceOf(USER), 250_000 * E);
        assertEq(points.balanceOf(ATTACKER), 0);
    }

    function test_issueBanned() public {
        write(USER, TRADING, "arcus", 1);
        write(OTHER, TRADING, "aster", 1);
        ban(ATTACKER);
        write(ATTACKER, TRADING, "arcus", 1);
        close();
        address[] memory list = new address[](3);
        list[0] = USER;
        list[1] = ATTACKER;
        list[2] = OTHER;
        vm.recordLogs();
        points.issuePoints(list);
        uint256 mints;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(points)) ++mints;
        }
        assertEq(mints, 2);
        assertEq(points.balanceOf(ATTACKER), 0);
        assertEq(points.totalSupply(), 250_000 * E);
    }

    function test_issueGas() public {
        close();
        open(R1, [100_000 * E, 100_000 * E, 100_000 * E]);
        address[] memory list = new address[](ISSUE_BATCH);
        DexPalCredits.Credit[] memory b = new DexPalCredits.Credit[](3 * ISSUE_BATCH);
        for (uint256 i; i < ISSUE_BATCH; ++i) {
            list[i] = address(uint160(0x1000 + i));
            for (uint256 k; k < 3; ++k) {
                b[3 * i + k] = cr(list[i], DexPalCredits.Kind(k), "arcus", i + 1);
            }
        }
        vm.prank(WRITER);
        credits.setCredits(b);
        close();
        vm.cool(address(points));
        vm.cool(address(credits));
        uint256 start = gasleft();
        points.issuePoints(list);
        uint256 used = start - gasleft();
        emit log_named_uint("issue gas per wallet", used / ISSUE_BATCH);
        assertLt(used, TX_GAS_CAP * 9 / 10);
        assertEq(credits.totalSupply(), 0);
    }

    function test_claim() public {
        write(USER, TRADING, "arcus", 30);
        write(OTHER, TRADING, "aster", 10);
        close();
        issue(USER);
        assertEq(points.balanceOfConverted(USER), 187_500 * UNITS);
        vm.expectRevert("only the owner of the points can call this");
        vm.prank(ATTACKER);
        points.claimPoints(USER, ATTACKER);
        vm.startPrank(USER);
        points.claimPoints(USER, OTHER);
        vm.expectRevert("nothing to pay");
        points.claimPoints(USER, OTHER);
        vm.stopPrank();
        assertEq(token.balanceOf(OTHER), 187_500 * UNITS);
        assertEq(points.balanceOf(USER), 0);
    }

    function test_underfunded() public {
        Token t = new Token();
        (DexPalPoints p, DexPalCredits c) = build(address(t));
        t.mint(address(p), 1);
        vm.startPrank(OWNER);
        p.openRound(R0, [E, 0, 0]);
        vm.stopPrank();
        vm.prank(WRITER);
        c.setCredits(one(USER, TRADING, "arcus", 1));
        vm.prank(OWNER);
        p.closeRound();
        p.issuePoints(users(USER));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(p), 1, UNITS));
        vm.prank(USER);
        p.claimPoints(USER, USER);
    }

    function test_noReturnToken() public {
        NoReturnToken usdt = new NoReturnToken();
        (DexPalPoints p, DexPalCredits c) = build(address(usdt));
        usdt.mint(address(p), 1e30);
        vm.prank(OWNER);
        p.openRound(R0, [E, 0, 0]);
        vm.prank(WRITER);
        c.setCredits(one(USER, TRADING, "arcus", 1));
        vm.prank(OWNER);
        p.closeRound();
        p.issuePoints(users(USER));
        vm.prank(USER);
        p.claimPoints(USER, USER);
        assertEq(usdt.balanceOf(USER), UNITS);
    }

    function test_convert() public {
        assertEq(conv.unitsPerPoint(), UNITS);
        assertEq(conv.convertPoints(E), UNITS);
        assertEq(conv.convertPoints(E / 2), UNITS / 2);
        assertEq(conv.convertPoints(E / UNITS - 1), 0);
        assertEq(new PointsConversion(3e18).convertPoints(7), 21);
        vm.expectRevert("rate is zero");
        new PointsConversion(0);
    }

    function test_sweepOwed() public {
        write(USER, TRADING, "arcus", 1);
        uint256 surplus = 1e30 - 250_000 * UNITS;
        vm.startPrank(OWNER);
        vm.expectRevert(bytes(OWED));
        points.sweep(address(token), OWNER, surplus + 1);
        points.closeRound();
        vm.expectRevert(bytes(OWED));
        points.sweep(address(token), OWNER, surplus + 1);
        vm.stopPrank();
        issue(USER);
        vm.startPrank(OWNER);
        vm.expectRevert(bytes(OWED));
        points.sweep(address(token), OWNER, surplus + 1);
        points.sweep(address(token), OWNER, surplus);
        vm.stopPrank();
        assertEq(token.balanceOf(OWNER), surplus);
        vm.prank(USER);
        points.claimPoints(USER, USER);
        assertEq(token.balanceOf(USER), 250_000 * UNITS);
    }

    function test_sweepOpenKinds() public {
        assertEq(credits.owedPoints(), 500_000 * E);
        write(USER, TRADING, "arcus", 1);
        write(OTHER, REFERRAL, 0, 1);
        close();
        assertEq(credits.owedPoints(), 400_000 * E);
    }

    function test_sweepAlias() public {
        write(USER, TRADING, "arcus", 1);
        Alias a = new Alias(token);
        vm.expectRevert(bytes(OWED));
        vm.prank(OWNER);
        points.sweep(address(a), OWNER, 1e30);
    }

    function test_sweepStray() public {
        (DexPalPoints p, DexPalCredits c) = build(address(token));
        vm.prank(OWNER);
        p.openRound(R0, [E, 0, 0]);
        vm.prank(WRITER);
        c.setCredits(one(USER, TRADING, "arcus", 1));
        Token stray = new Token();
        stray.mint(address(p), 5);
        vm.prank(OWNER);
        p.sweep(address(stray), OTHER, 5);
        assertEq(stray.balanceOf(OTHER), 5);
    }

    function test_sweepOwner() public {
        vm.expectRevert(unauthorized(ATTACKER));
        vm.prank(ATTACKER);
        points.sweep(address(token), ATTACKER, 1);
    }

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
        assertEq(uint8(credits.state()), uint8(DexPalCredits.State.Open));
    }

    function test_rollover() public {
        for (uint256 k; k < 3; ++k) {
            write(USER, DexPalCredits.Kind(k), "arcus", 1);
            close();
            vm.expectRevert("remaining user credits left");
            open(R1, [uint256(1), 1, 1]);
            issue(USER);
            open(R1, [uint256(1), 1, 1]);
        }
    }

    function test_closeRound() public {
        vm.expectRevert(unauthorized(WRITER));
        vm.prank(WRITER);
        points.closeRound();
        vm.expectEmit(address(credits));
        emit DexPalCredits.RoundClosed(R0);
        close();
        assertEq(uint8(credits.state()), uint8(DexPalCredits.State.Closed));
        vm.expectRevert("state needs to be open");
        close();
    }

    function test_ban() public {
        write(USER, TRADING, "arcus", 30);
        write(USER, QUEST, "arcus", 1);
        write(OTHER, TRADING, "aster", 10);
        vm.expectRevert(unauthorized(ATTACKER));
        vm.prank(ATTACKER);
        points.banUser(USER);
        vm.expectEmit(address(credits));
        emit DexPalCredits.Disqualified(R0, USER, true);
        ban(USER);
        assertTrue(credits.isBanned(USER));
        assertFalse(credits.isBanned(OTHER));
        assertEq(credits.bannedUsers().length, 1);
        assertEq(credits.bannedUsers()[0], USER);
        vm.recordLogs();
        ban(USER);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(credits.balanceOf(USER, 1), 0);
        assertEq(pending(USER), 0);
        assertEq(pending(OTHER), 250_000 * E);
        write(USER, TRADING, "arcus", 999);
        add(USER, TRADING, "arcus", 5);
        assertEq(credits.balanceOf(USER, 0), 0);
        close();
        vm.expectRevert("cannot ban whilst closed");
        ban(OTHER);
        issue(OTHER);
        open(R1, [uint256(1), 0, 0]);
        write(USER, TRADING, "arcus", 1);
        assertEq(credits.balanceOf(USER, 0), 0);
    }

    function test_settersGone() public {
        vm.startPrank(OWNER);
        bytes[4] memory calls = [
            abi.encodeWithSignature("updateNumeraire(address)", ATTACKER),
            abi.encodeWithSignature("updatePointsConversion(address)", ATTACKER),
            abi.encodeWithSignature("updateCreditsContractAddress(address)", ATTACKER),
            abi.encodeWithSignature("setPointsContractAddress(address)", ATTACKER)
        ];
        for (uint256 i; i < 3; ++i) {
            (bool ok,) = address(points).call(calls[i]);
            assertFalse(ok);
        }
        (bool okCredits,) = address(credits).call(calls[3]);
        assertFalse(okCredits);
        vm.stopPrank();
        assertEq(points.numeraire(), address(token));
        assertEq(points.creditsContractAddress(), address(credits));
        assertEq(credits.pointsContractAddress(), address(points));
    }

    function test_updateWriter() public {
        vm.expectRevert(unauthorized(ATTACKER));
        vm.prank(ATTACKER);
        credits.updateWriter(ATTACKER);
        vm.expectEmit(address(credits));
        emit DexPalCredits.WriterSet(USER);
        vm.prank(OWNER);
        credits.updateWriter(USER);
        vm.expectRevert("you are not the writer");
        write(USER, TRADING, "arcus", 1);
        vm.prank(USER);
        credits.setCredits(one(USER, TRADING, "arcus", 1));
        assertEq(credits.writer(), USER);
    }

    function test_noRenounce() public {
        vm.startPrank(OWNER);
        vm.expectRevert("cannot renounce");
        points.renounceOwnership();
        vm.expectRevert("cannot renounce");
        credits.renounceOwnership();
        vm.stopPrank();
    }

    function test_twoStepOwner() public {
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

    function test_unlinked() public {
        DexPalCredits c = new DexPalCredits(OWNER, WRITER, "uri", address(1));
        vm.expectRevert("credits not linked");
        new DexPalPoints(address(token), OWNER, address(conv), address(c));
    }

    function test_metadata() public view {
        assertEq(points.name(), "DexPalPoints");
        assertEq(points.symbol(), "DPP");
        assertEq(points.decimals(), 18);
    }

    function build(address numeraire) internal returns (DexPalPoints p, DexPalCredits c) {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 2);
        PointsConversion pc = new PointsConversion(UNITS);
        c = new DexPalCredits(OWNER, WRITER, "uri", predicted);
        p = new DexPalPoints(numeraire, OWNER, address(pc), address(c));
        assertEq(address(p), predicted);
    }

    function cr(address user, DexPalCredits.Kind kind, bytes32 dex, uint256 amount)
        internal
        pure
        returns (DexPalCredits.Credit memory)
    {
        return DexPalCredits.Credit(user, kind, dex, amount);
    }

    function one(address user, DexPalCredits.Kind kind, bytes32 dex, uint256 amount)
        internal
        pure
        returns (DexPalCredits.Credit[] memory entries)
    {
        entries = new DexPalCredits.Credit[](1);
        entries[0] = cr(user, kind, dex, amount);
    }

    function users(address user) internal pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = user;
    }

    function batch(string memory id, DexPalCredits.Credit[] memory entries) internal {
        vm.prank(WRITER);
        credits.increaseCredits(entries, keccak256(bytes(id)));
    }

    function write(address user, DexPalCredits.Kind kind, bytes32 dex, uint256 amount) internal {
        vm.prank(WRITER);
        credits.setCredits(one(user, kind, dex, amount));
    }

    function add(address user, DexPalCredits.Kind kind, bytes32 dex, uint256 amount) internal {
        vm.prank(WRITER);
        credits.increaseCredits(one(user, kind, dex, amount), bytes32(++batchNonce));
    }

    function open(bytes16 round, uint256[3] memory budget) internal {
        vm.prank(OWNER);
        points.openRound(round, budget);
    }

    function close() internal {
        vm.prank(OWNER);
        points.closeRound();
    }

    function ban(address user) internal {
        vm.prank(OWNER);
        points.banUser(user);
    }

    function issue(address user) internal {
        points.issuePoints(users(user));
    }

    function pending(address user) internal view returns (uint256) {
        return points.predictedBalanceOf(user) - points.balanceOf(user);
    }

    function unauthorized(address account) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, account);
    }
}
