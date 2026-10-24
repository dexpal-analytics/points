// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.37;

import {Test, stdError} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {DexPalPoints} from "../src/DexPalPoints.sol";
import {Deploy} from "../script/Deploy.s.sol";

contract Plain {}

contract DexPalPointsTest is Test {
    bytes16 constant R0 = bytes16(uint128(0xA0));
    bytes16 constant R1 = bytes16(uint128(0xA1));
    address constant OWNER = address(0xA11CE);
    address constant WRITER = address(0xB0B);
    address constant USER = address(0xCAFE);
    address constant OTHER = address(0xBEEF);
    address constant ATTACKER = address(0xBAD);
    uint256 constant TX_GAS_CAP = 32_000_000;

    DexPalPoints.Kind constant TRADING = DexPalPoints.Kind.Trading;
    DexPalPoints.Kind constant QUEST = DexPalPoints.Kind.Quest;
    DexPalPoints.Kind constant REFERRAL = DexPalPoints.Kind.Referral;

    DexPalPoints p;

    function setUp() public {
        p = DexPalPoints(address(new ERC1967Proxy(address(new DexPalPoints()), init(OWNER))));
        open(R0, [uint256(250_000), 100_000, 150_000]);
    }

    function test_setCredits() public {
        vm.expectEmit(address(p));
        emit DexPalPoints.CreditsSet(R0, USER, "arcus", TRADING, 100);
        write(R0, USER, TRADING, "arcus", 100);
        assertEq(p.credits(R0, USER, TRADING, "arcus"), 100);
        assertEq(p.getUserCredits(R0, USER, TRADING), 100);
        assertEq(p.dexCredits(R0, "arcus"), 100);
        assertEq(p.getRound(R0).total[0], 100);
    }

    function test_overwrite() public {
        write(R0, USER, TRADING, "arcus", 100);
        write(R0, USER, TRADING, "arcus", 100);
        assertEq(p.getRound(R0).total[0], 100);
        write(R0, USER, TRADING, "arcus", 30);
        assertEq(p.getUserCredits(R0, USER, TRADING), 30);
        write(R0, USER, TRADING, "arcus", 0);
        assertEq(p.getUserCredits(R0, USER, TRADING), 0);
        assertEq(p.dexCredits(R0, "arcus"), 0);
        assertEq(p.getRound(R0).total[0], 0);
    }

    function test_points() public {
        write(R0, USER, TRADING, "arcus", 30);
        write(R0, OTHER, TRADING, "aster", 10);
        write(R0, USER, QUEST, "arcus", 1);
        assertEq(p.points(R0, USER), 187_500 + 100_000);
        assertEq(p.points(R0, OTHER), 62_500);
        assertEq(p.dexCredits(R0, "arcus"), 30);
    }

    function test_rounding() public {
        open(R1, [uint256(100), 0, 0]);
        write(R1, USER, TRADING, "arcus", 1);
        write(R1, OTHER, TRADING, "arcus", 1);
        write(R1, ATTACKER, TRADING, "arcus", 1);
        assertEq(p.points(R1, USER), 33);
        assertEq(p.points(R1, USER) + p.points(R1, OTHER) + p.points(R1, ATTACKER), 99);
    }

    function testFuzz_split(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, 1e30);
        b = bound(b, 0, 1e30);
        c = bound(c, 0, 1e30);
        write(R0, USER, TRADING, "arcus", a);
        write(R0, OTHER, TRADING, "aster", b);
        write(R0, ATTACKER, REFERRAL, 0, c);
        uint256 sum = p.points(R0, USER) + p.points(R0, OTHER);
        assertLe(sum, 250_000);
        if (a + b > 0) assertGe(sum, 250_000 - 1);
        assertEq(p.points(R0, ATTACKER), c > 0 ? 150_000 : 0);
    }

    function test_lifetime() public {
        open(R1, [uint256(1000), 0, 0]);
        write(R0, USER, TRADING, "arcus", 1);
        write(R1, USER, TRADING, "arcus", 1);
        assertEq(p.lifetime(USER), 0);
        close(R0);
        assertEq(p.lifetime(USER), 250_000);
        close(R1);
        assertEq(p.lifetime(USER), 251_000);
    }

    function test_duplicate() public {
        DexPalPoints.Credit[] memory batch = new DexPalPoints.Credit[](2);
        batch[0] = DexPalPoints.Credit(USER, TRADING, "arcus", 5);
        batch[1] = DexPalPoints.Credit(USER, TRADING, "arcus", 9);
        vm.expectEmit(address(p));
        emit DexPalPoints.CreditsSet(R0, USER, "arcus", TRADING, 5);
        vm.expectEmit(address(p));
        emit DexPalPoints.CreditsSet(R0, USER, "arcus", TRADING, 9);
        vm.prank(WRITER);
        p.setCredits(R0, batch);
        assertEq(p.getUserCredits(R0, USER, TRADING), 9);
    }

    function test_empty() public {
        vm.prank(WRITER);
        p.setCredits(R0, new DexPalPoints.Credit[](0));
    }

    function test_badKind() public {
        bytes memory call = abi.encodeCall(p.setCredits, (R0, one(USER, TRADING, "arcus", 1)));
        call[4 + 32 * 4 + 31] = bytes1(uint8(3));
        vm.prank(WRITER);
        (bool ok, bytes memory reason) = address(p).call(call);
        assertFalse(ok);
        assertEq(reason.length, 0);
    }

    function test_overflow() public {
        uint256 max = type(uint256).max;
        write(R0, USER, TRADING, "arcus", max);
        write(R0, USER, TRADING, "arcus", max);
        assertEq(p.points(R0, USER), 250_000);

        DexPalPoints.Credit[] memory batch = new DexPalPoints.Credit[](2);
        batch[0] = DexPalPoints.Credit(OTHER, QUEST, 0, 5);
        batch[1] = DexPalPoints.Credit(OTHER, TRADING, "aster", 1);
        vm.prank(WRITER);
        vm.expectRevert(stdError.arithmeticError);
        p.setCredits(R0, batch);
        assertEq(p.getUserCredits(R0, OTHER, QUEST), 0);
    }

    function test_batch() public {
        DexPalPoints.Credit[] memory batch = new DexPalPoints.Credit[](200);
        for (uint256 i; i < batch.length; ++i) {
            batch[i] = DexPalPoints.Credit(address(uint160(i + 1)), TRADING, "arcus", i + 1);
        }
        vm.prank(WRITER);
        uint256 start = gasleft();
        p.setCredits(R0, batch);
        assertLt(start - gasleft(), TX_GAS_CAP / 2);
        assertEq(p.getUserCredits(R0, address(200), TRADING), 200);
    }

    function test_onlyWriter() public {
        vm.expectRevert("not writer");
        vm.prank(ATTACKER);
        p.setCredits(R0, one(USER, TRADING, "arcus", 1));
        vm.expectRevert("not writer");
        vm.prank(OWNER);
        p.setCredits(R0, one(USER, TRADING, "arcus", 1));
    }

    function test_roundNotOpen() public {
        vm.expectRevert("round not open");
        write(R1, USER, TRADING, "arcus", 1);
        close(R0);
        vm.expectRevert("round not open");
        write(R0, USER, TRADING, "arcus", 1);
    }

    function test_openRound() public {
        vm.expectRevert(unauthorized(WRITER));
        vm.prank(WRITER);
        p.openRound(R1, [uint256(1), 1, 1]);

        vm.expectEmit(address(p));
        emit DexPalPoints.RoundOpened(R1, [uint256(500), 0, 0]);
        open(R1, [uint256(500), 0, 0]);
        assertEq(p.getRound(R1).budget[0], 500);

        vm.expectRevert("round exists");
        open(R1, [uint256(1), 1, 1]);
        close(R1);
        vm.expectRevert("round exists");
        open(R1, [uint256(1), 1, 1]);
    }

    function test_disqualify() public {
        write(R0, USER, TRADING, "arcus", 30);
        write(R0, OTHER, TRADING, "aster", 10);

        vm.expectRevert("not allowed");
        vm.prank(ATTACKER);
        p.disqualify(R0, USER);

        vm.expectEmit(address(p));
        emit DexPalPoints.Disqualified(R0, USER, true);
        vm.prank(WRITER);
        p.disqualify(R0, USER);
        assertEq(p.points(R0, USER), 0);
        assertEq(p.points(R0, OTHER), 62_500);
        assertTrue(p.disqualified(R0, USER));
        assertEq(p.disqualifiedUsers(R0).length, 1);
        assertEq(p.disqualifiedUsers(R0)[0], USER);

        DexPalPoints.Credit[] memory batch = new DexPalPoints.Credit[](2);
        batch[0] = DexPalPoints.Credit(USER, TRADING, "arcus", 999);
        batch[1] = DexPalPoints.Credit(OTHER, TRADING, "aster", 20);
        vm.prank(WRITER);
        p.setCredits(R0, batch);
        assertEq(p.getUserCredits(R0, USER, TRADING), 30);
        assertEq(p.getUserCredits(R0, OTHER, TRADING), 20);

        vm.expectRevert(unauthorized(WRITER));
        vm.prank(WRITER);
        p.requalify(R0, USER);
        vm.prank(OWNER);
        p.requalify(R0, USER);
        assertEq(p.points(R0, USER), 150_000);
        assertFalse(p.disqualified(R0, USER));
        assertEq(p.disqualifiedUsers(R0).length, 0);
    }

    function test_disqualifyEndsWithRound() public {
        open(R1, [uint256(1000), 0, 0]);
        vm.prank(OWNER);
        p.disqualify(R0, USER);
        write(R1, USER, TRADING, "arcus", 1);
        assertEq(p.points(R1, USER), 1000);

        close(R0);
        close(R1);
        assertEq(p.lifetime(USER), 1000);
        vm.expectRevert("round not open");
        vm.prank(OWNER);
        p.requalify(R0, USER);
    }

    function test_closeRound() public {
        vm.expectRevert(unauthorized(WRITER));
        vm.prank(WRITER);
        p.closeRound(R0);

        vm.expectEmit(address(p));
        emit DexPalPoints.RoundClosed(R0);
        close(R0);
        assertEq(uint8(p.getRound(R0).state), uint8(DexPalPoints.State.Closed));
        vm.expectRevert("round not open");
        close(R0);
        vm.expectRevert("round not open");
        close(R1);
    }

    function test_setWriter() public {
        vm.expectRevert(unauthorized(WRITER));
        vm.prank(WRITER);
        p.setWriter(ATTACKER);

        vm.expectEmit(address(p));
        emit DexPalPoints.WriterSet(USER);
        vm.prank(OWNER);
        p.setWriter(USER);
        vm.expectRevert("not writer");
        write(R0, USER, TRADING, "arcus", 1);
        vm.prank(USER);
        p.setCredits(R0, one(USER, TRADING, "arcus", 1));
        assertEq(p.getUserCredits(R0, USER, TRADING), 1);

        vm.prank(OWNER);
        p.setWriter(address(0));
        vm.expectRevert("not writer");
        vm.prank(USER);
        p.setCredits(R0, one(USER, TRADING, "arcus", 1));
    }

    function test_noRenounce() public {
        vm.expectRevert("cannot renounce");
        vm.prank(OWNER);
        p.renounceOwnership();
        assertEq(p.owner(), OWNER);
    }

    function test_twoStepOwner() public {
        vm.expectRevert(unauthorized(ATTACKER));
        vm.prank(ATTACKER);
        p.transferOwnership(ATTACKER);

        vm.prank(OWNER);
        p.transferOwnership(USER);
        assertEq(p.owner(), OWNER);
        vm.expectRevert(unauthorized(ATTACKER));
        vm.prank(ATTACKER);
        p.acceptOwnership();
        vm.prank(USER);
        p.acceptOwnership();
        assertEq(p.owner(), USER);
        vm.expectRevert(unauthorized(OWNER));
        vm.prank(OWNER);
        p.setWriter(OWNER);
    }

    function test_initOnce() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        p.initialize(ATTACKER, ATTACKER);
    }

    function test_initZeroOwner() public {
        address impl = address(new DexPalPoints());
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        new ERC1967Proxy(impl, init(address(0)));
    }

    function test_implLocked() public {
        DexPalPoints impl = new DexPalPoints();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(ATTACKER, ATTACKER);
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        impl.upgradeToAndCall(address(impl), "");
    }

    function test_upgrade() public {
        write(R0, USER, TRADING, "arcus", 42);
        address next = address(new DexPalPoints());
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vm.prank(OWNER);
        p.upgradeToAndCall(next, init(ATTACKER));

        vm.prank(OWNER);
        p.upgradeToAndCall(next, "");
        assertEq(address(uint160(uint256(vm.load(address(p), ERC1967Utils.IMPLEMENTATION_SLOT)))), next);
        assertEq(p.getUserCredits(R0, USER, TRADING), 42);
        assertEq(p.writer(), WRITER);
        assertEq(p.owner(), OWNER);
    }

    function test_upgradeOnlyOwner() public {
        address next = address(new DexPalPoints());
        vm.expectRevert(unauthorized(WRITER));
        vm.prank(WRITER);
        p.upgradeToAndCall(next, "");
    }

    function test_upgradeNeedsUUPS() public {
        address plain = address(new Plain());
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, plain));
        vm.prank(OWNER);
        p.upgradeToAndCall(plain, "");
    }

    function test_layout() public {
        write(R0, USER, TRADING, "arcus", 7);
        assertEq(address(uint160(uint256(vm.load(address(p), 0)))), WRITER);
        assertEq(uint256(vm.load(address(p), bytes32(uint256(1)))), 1);
        assertEq(uint256(vm.load(address(p), keccak256(abi.encode(R0, uint256(2))))), 250_000);
        bytes32 user = keccak256(abi.encode(USER, keccak256(abi.encode(R0, uint256(3)))));
        assertEq(uint256(vm.load(address(p), user)), 7);
        bytes32 dex = keccak256(abi.encode(bytes32("arcus"), keccak256(abi.encode(R0, uint256(4)))));
        assertEq(uint256(vm.load(address(p), dex)), 7);
    }

    function test_deploy() public {
        vm.setEnv("OWNER", vm.toString(OWNER));
        vm.setEnv("WRITER", vm.toString(WRITER));
        Deploy script = new Deploy();
        vm.expectEmit();
        emit DexPalPoints.WriterSet(WRITER);
        DexPalPoints deployed = script.run();
        assertEq(deployed.owner(), OWNER);
        assertEq(deployed.writer(), WRITER);
    }

    function init(address owner) internal pure returns (bytes memory) {
        return abi.encodeCall(DexPalPoints.initialize, (owner, WRITER));
    }

    function open(bytes16 round, uint256[3] memory budget) internal {
        vm.prank(OWNER);
        p.openRound(round, budget);
    }

    function close(bytes16 round) internal {
        vm.prank(OWNER);
        p.closeRound(round);
    }

    function one(address user, DexPalPoints.Kind kind, bytes32 dex, uint256 amount)
        internal
        pure
        returns (DexPalPoints.Credit[] memory entries)
    {
        entries = new DexPalPoints.Credit[](1);
        entries[0] = DexPalPoints.Credit(user, kind, dex, amount);
    }

    function write(bytes16 round, address user, DexPalPoints.Kind kind, bytes32 dex, uint256 amount) internal {
        vm.prank(WRITER);
        p.setCredits(round, one(user, kind, dex, amount));
    }

    function unauthorized(address account) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, account);
    }
}
