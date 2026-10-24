// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.37;

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
