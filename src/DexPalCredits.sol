// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.37;

import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IDexPalCredits {
    function pointsBalanceOf(address user) external view returns (uint256);
    function withdrawPoints(address user) external;
}

contract DexPalCredits is ERC1155Supply, IDexPalCredits, Ownable2Step, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    enum State {
        Open,
        Closed
    }

    enum Kind {
        //0
        Trading,
        //1
        Quest,
        // 10% referral share, no ladder
        //1
        Referral
    }

    mapping(Kind kind => uint256) public budget;

    struct Credit {
        address user;
        Kind kind;
        bytes32 dex;
        uint256 amount;
    }

    address public writer;
    address public pointsContractAddress;
    State public state;
    bytes16 public roundName;
    EnumerableSet.AddressSet private bans;

    event WriterSet(address writer);
    event PointsContractSet(address pointsContract);
    event RoundOpened(bytes16 indexed round, uint256[3] budget);
    event RoundClosed(bytes16 indexed round);
    event CreditsSet(bytes16 indexed round, address indexed user, bytes32 indexed dex, Kind kind, uint256 amount);
    event Disqualified(bytes16 indexed round, address indexed user, bool banned);

    constructor(address _owner, address _writer, string memory _uri) Ownable(_owner) ERC1155(_uri) {
        writer = _writer;
        emit WriterSet(writer);
    }

    modifier onlyWriter() {
        require(msg.sender == writer, "you are not the writer");
        _;
    }

    function setPointsContractAddress(address newPointsContractAddress) external onlyOwner {
        pointsContractAddress = newPointsContractAddress;
        emit PointsContractSet(newPointsContractAddress);
    }

    modifier onlyPointsContract() {
        require(msg.sender == pointsContractAddress);
        _;
    }

    function updateWriter(address newWriter) public onlyOwner {
        writer = newWriter;
        emit WriterSet(newWriter);
    }

    function openRound(bytes16 _roundName, uint256[3] calldata newBudget) external nonReentrant onlyOwner {
        require(state == State.Closed, "call closeRound first");
        roundName = _roundName;
        for (uint8 i; i < 3; ++i) {
            budget[Kind(i)] = newBudget[i];
        }
        emit RoundOpened(_roundName, newBudget);
        state = State.Open;
    }

    function setCredits(Credit[] calldata entries) external nonReentrant onlyWriter {
        for (uint256 i; i < entries.length; ++i) {
            Credit calldata c = entries[i];
            uint256 id = uint256(c.kind);
            uint256 oldBalance = balanceOf(c.user, id);
            _burn(c.user, id, oldBalance);
            _mint(c.user, id, c.amount, abi.encodePacked(c.dex));
            emit CreditsSet(roundName, c.user, c.dex, c.kind, c.amount);
        }
    }

    /// called by the points contract
    function pointsBalanceOf(address user) external view onlyPointsContract returns (uint256) {
        if (bans.contains(user)) return 0;

        uint256 pointsBalance = 0;
        for (uint256 id; id < 3; ++id) {
            uint256 userCredits = balanceOf(user, id);
            uint256 totalCredits = totalSupply(id);
            pointsBalance += Math.mulDiv(budget[Kind(id)], userCredits, totalCredits);
        }
        return pointsBalance;
    }

    /// called by the points contract before issuing the user's points
    function withdrawPoints(address user) public nonReentrant onlyPointsContract {
        require(state == State.Closed, "state needs to be closed");
        for (uint256 id; id < 3; ++id) {
            uint256 oldBalance = balanceOf(user, id);
            _burn(user, id, oldBalance);
        }
    }

    function closeRound() external nonReentrant onlyPointsContract {
        require(state == State.Open, "state needs to be open");
        state = State.Closed;
    }

    function banUser(address user) external nonReentrant onlyPointsContract {
        bans.add(user);
        withdrawPoints(user);
    }
}

