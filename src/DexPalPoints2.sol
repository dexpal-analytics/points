pragma solidity ^0.8.37;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDexPalCredits} from "./DexPalCredits.sol";

interface IPointsConversion {
    function convertPoints(uint256 points) external pure returns (uint256);
}

contract DexPalPoints is ERC20, Ownable2Step, ReentrancyGuard {
    address public numeraire;
    address public pointsConversion;
    address public creditsContractAddress;

    event NumeraireChanged(address newNumeraire);
    event PointsConversionChanged(address newPointsConversion);
    event CreditsContractAddressChanged(address newCreditsContract);

    constructor(address numeraire_, address _owner, address pointsConversion_, address creditsContractAddress_)
        Ownable(_owner)
        ERC20("DexPalPoints", "DPP")
    {
        numeraire = numeraire_;
        pointsConversion = pointsConversion_;
        creditsContractAddress = creditsContractAddress_;
    }

    function updateNumeraire(address newNumeraire) external onlyOwner {
        numeraire = newNumeraire;
        emit NumeraireChanged(newNumeraire);
    }

    function updatePointsConversion(address pointsConversion_) external onlyOwner {
        pointsConversion = pointsConversion_;
        emit PointsConversionChanged(pointsConversion_);
    }

    function updateCreditsContractAddress(address newCreditsContractAddress) external onlyOwner {
        creditsContractAddress = newCreditsContractAddress;
        emit CreditsContractAddressChanged(newCreditsContractAddress);
    }

    function claimPoints(address from, address to) public nonReentrant {
        uint256 numeraireToTransfer = balanceOfConverted(from);
        bool success = IERC20(numeraire).transfer(to, numeraireToTransfer);
        require(success, "Points Claim Failed");
    }

    function issuePoints(address user) external nonReentrant onlyOwner {
        uint256 points = IDexPalCredits(creditsContractAddress).pointsBalanceOf(user);
        IDexPalCredits(creditsContractAddress).withdrawPoints(user);
        _mint(user, points);
    }

    function balanceOf(address user) public view override returns (uint256) {
        uint256 balanceHere = IERC20(address(this)).balanceOf(user);
        uint256 balanceInCredits = IDexPalCredits(creditsContractAddress).pointsBalanceOf(user);
        return balanceHere + balanceInCredits;
    }

    function balanceOfConverted(address user) public view returns (uint256) {
        uint256 userPoints = balanceOf(user);
        return IPointsConversion(pointsConversion).convertPoints(userPoints);
    }
}

