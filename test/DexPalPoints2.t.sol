// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.37;

import {Test, stdError} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {DexPalPoints} from "../src/DexPalPoints2.sol";
import {DexPalCredits} from "../src/DexPalCredits.sol";
import {PointsConversion1} from "../src/PointsConversion.sol";
import {Deploy} from "../script/Deploy2.s.sol";

contract Plain {}

contract DexPalPointsTest is Test {
    function deploy() public returns (DexPalPoints, DexPalCredits) {
        address numeraire = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
        address owner = OWNER;
        address writer = WRITER;
        vm.startBroadcast();
        PointsConversion1 pointsConversion = new PointsConversion1();
        string memory uri = vm.envString("uri");
        DexPalCredits dexPalCredits = new DexPalCredits(owner, writer, uri);
        DexPalPoints dexPalPoints =
            new DexPalPoints(numeraire, owner, address(pointsConversion), address(dexPalCredits));
        dexPalCredits.setPointsContractAddress(address(dexPalPoints));
        vm.stopBroadcast();
        return (dexPalPoints, dexPalCredits);
    }

    bytes16 constant R0 = bytes16(uint128(0xA0));
    bytes16 constant R1 = bytes16(uint128(0xA1));
    address constant OWNER = address(0xA11CE);
    address constant WRITER = address(0xB0B);
    address constant USER = address(0xCAFE);
    address constant OTHER = address(0xBEEF);
    address constant ATTACKER = address(0xBAD);
    uint256 constant TX_GAS_CAP = 32_000_000;
    DexPalPoints dexPalPoints;
    DexPalCredits dexPalCredits;

    function setUp() public {
        (dexPalPoints, dexPalCredits) = deploy();
    }
}
