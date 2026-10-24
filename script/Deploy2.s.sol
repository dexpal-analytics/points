// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";
import {DexPalPoints} from "../src/DexPalPoints2.sol";
import {DexPalCredits} from "../src/DexPalCredits.sol";
import {PointsConversion} from "../src/PointsConversion.sol";

contract Deploy2 is Script {
    function run() external returns (DexPalPoints, DexPalCredits) {
        return deploy(
            vm.envAddress("NUMERAIRE"),
            vm.envAddress("OWNER"),
            vm.envAddress("WRITER"),
            vm.envString("URI"),
            vm.envUint("UNITS_PER_POINT")
        );
    }

    /// Credits and Points each hold the other as immutable, so Credits is built with the address
    /// Points will get two creations later.
    function deploy(address numeraire, address owner, address writer, string memory uri, uint256 unitsPerPoint)
        public
        returns (DexPalPoints points, DexPalCredits credits)
    {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        address predicted = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 2);
        PointsConversion conversion = new PointsConversion(unitsPerPoint);
        credits = new DexPalCredits(owner, writer, uri, predicted);
        points = new DexPalPoints(numeraire, owner, address(conversion), address(credits));
        vm.stopBroadcast();
    }
}
