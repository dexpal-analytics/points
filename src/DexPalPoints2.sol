// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDexPalCredits} from "./DexPalCredits.sol";

interface IPointsConversion {
    function convertPoints(uint256 points) external view returns (uint256);
}

contract DexPalPoints is ERC20, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable numeraire;
    address public immutable pointsConversion;
    address public immutable creditsContractAddress;

    constructor(address numeraire_, address _owner, address pointsConversion_, address creditsContractAddress_)
        Ownable(_owner)
        ERC20("DexPalPoints", "DPP")
    {
        require(IDexPalCredits(creditsContractAddress_).pointsContractAddress() == address(this), "credits not linked");
        numeraire = numeraire_;
        pointsConversion = pointsConversion_;
        creditsContractAddress = creditsContractAddress_;
    }

    function renounceOwnership() public pure override {
        revert("cannot renounce");
    }

    function claimPoints(address from, address to) public nonReentrant {
        require(msg.sender == from, "only the owner of the points can call this");
        uint256 numeraireToTransfer = balanceOfConverted(from);
        require(numeraireToTransfer != 0, "nothing to pay");
        _burn(from, balanceOf(from));
        IERC20(numeraire).safeTransfer(to, numeraireToTransfer);
    }

    function issuePoints(address[] calldata users) external nonReentrant {
        IDexPalCredits credits = IDexPalCredits(creditsContractAddress);
        for (uint256 i; i < users.length; ++i) {
            // forge-lint: disable-next-line(calls-loop)
            uint256 points = credits.withdrawPoints(users[i]);
            if (points != 0) _mint(users[i], points);
        }
    }

    /// Checks the numeraire balance whatever the token, so a token with a second address for the
    /// same balance cannot take what is owed.
    function sweep(address token, address to, uint256 amount) external nonReentrant onlyOwner {
        uint256 before = IERC20(numeraire).balanceOf(address(this));
        IERC20(token).safeTransfer(to, amount);
        uint256 left = IERC20(numeraire).balanceOf(address(this));
        require(left >= before || left >= owed(), "sweep would take what is owed");
    }

    function owed() internal view returns (uint256) {
        uint256 pending = IDexPalCredits(creditsContractAddress).owedPoints();
        return IPointsConversion(pointsConversion).convertPoints(totalSupply() + pending);
    }

    function predictedBalanceOf(address user) public view returns (uint256) {
        return balanceOf(user) + IDexPalCredits(creditsContractAddress).pointsBalanceOf(user);
    }

    function predictedBalanceOfConverted(address user) public view returns (uint256) {
        return IPointsConversion(pointsConversion).convertPoints(predictedBalanceOf(user));
    }

    function balanceOfConverted(address user) public view returns (uint256) {
        return IPointsConversion(pointsConversion).convertPoints(balanceOf(user));
    }

    function banUser(address user) external nonReentrant onlyOwner {
        IDexPalCredits(creditsContractAddress).banUser(user);
    }

    function closeRound() external nonReentrant onlyOwner {
        IDexPalCredits(creditsContractAddress).closeRound();
    }

    function openRound(bytes16 _roundName, uint256[3] calldata newBudget) external nonReentrant onlyOwner {
        IDexPalCredits(creditsContractAddress).openRound(_roundName, newBudget);
    }
}
