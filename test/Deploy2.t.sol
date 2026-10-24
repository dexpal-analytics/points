// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {DexPalPoints} from "../src/DexPalPoints2.sol";
import {DexPalCredits} from "../src/DexPalCredits.sol";
import {PointsConversion} from "../src/PointsConversion.sol";
import {Deploy2} from "../script/Deploy2.s.sol";

contract Deploy2Test is Test {
    address constant OWNER = address(0xA11CE);
    address constant WRITER = address(0xB0B);
    address constant NUMERAIRE = address(0x5D);

    function test_deploy() public {
        vm.setNonce(DEFAULT_SENDER, 7);
        (DexPalPoints points, DexPalCredits credits) = new Deploy2().deploy(NUMERAIRE, OWNER, WRITER, "uri", 1e6);
        check(points, credits, 1e6);
        assertEq(credits.uri(0), "uri");
    }

    function test_run() public {
        vm.setEnv("NUMERAIRE", vm.toString(NUMERAIRE));
        vm.setEnv("OWNER", vm.toString(OWNER));
        vm.setEnv("WRITER", vm.toString(WRITER));
        vm.setEnv("URI", "uri");
        vm.setEnv("UNITS_PER_POINT", "10000");
        (DexPalPoints points, DexPalCredits credits) = new Deploy2().run();
        check(points, credits, 1e4);
    }

    function check(DexPalPoints points, DexPalCredits credits, uint256 units) internal view {
        assertEq(credits.pointsContractAddress(), address(points));
        assertEq(points.creditsContractAddress(), address(credits));
        assertEq(points.numeraire(), NUMERAIRE);
        assertEq(points.owner(), OWNER);
        assertEq(credits.owner(), OWNER);
        assertEq(credits.writer(), WRITER);
        assertEq(PointsConversion(points.pointsConversion()).unitsPerPoint(), units);
    }
}
