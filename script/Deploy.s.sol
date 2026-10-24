// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DexPalPoints} from "../src/DexPalPoints.sol";

contract Deploy is Script {
    function run() external returns (DexPalPoints points) {
        bytes memory init = abi.encodeCall(DexPalPoints.initialize, (vm.envAddress("OWNER"), vm.envAddress("WRITER")));
        vm.startBroadcast();
        points = DexPalPoints(address(new ERC1967Proxy(address(new DexPalPoints()), init)));
        vm.stopBroadcast();
    }
}
