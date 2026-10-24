pragma solidity ^0.8.35;

import {IPointsConversion} from "./DexPalPoints2.sol";

contract PointsConversion1 is IPointsConversion {
    function convertPoints(uint256 points) external pure returns (uint256) {
        return points * 1e4;
    }
}
