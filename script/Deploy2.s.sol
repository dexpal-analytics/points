// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.37;

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DexPalPoints} from "../src/DexPalPoints2.sol";
import {DexPalCredits} from "../src/DexPalCredits.sol";
import {PointsConversion1} from "../src/PointsConversion.sol";

contract Deploy is Script {
    function run() external returns (DexPalPoints, DexPalCredits) {
        address numeraire = vm.envAddress("numeraire");
        address owner = vm.envAddress("OWNER");
        address writer = vm.envAddress("WRITER");
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
}

