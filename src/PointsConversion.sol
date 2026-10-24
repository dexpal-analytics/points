// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPointsConversion} from "./DexPalPoints2.sol";

contract PointsConversion is IPointsConversion {
    uint256 public immutable unitsPerPoint;

    constructor(uint256 unitsPerPoint_) {
        require(unitsPerPoint_ != 0, "rate is zero");
        unitsPerPoint = unitsPerPoint_;
    }

    function convertPoints(uint256 points) external view returns (uint256) {
        return Math.mulDiv(points, unitsPerPoint, 1e18);
    }
}
