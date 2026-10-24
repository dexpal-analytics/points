// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.37;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IDexPalCredits {}

contract DexPalCredits is ERC1155, IDexPalCredits, Ownable2Step, ReentrancyGuard {
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
    State public state;
    bytes16 public roundName;

    event WriterSet(address writer);
    event RoundOpened(bytes16 indexed round, uint256[3] budget);
    event RoundClosed(bytes16 indexed round);
    event CreditsSet(bytes16 indexed round, address indexed user, bytes32 indexed dex, Kind kind, uint256 amount);
    event Disqualified(bytes16 indexed round, address indexed user, bool banned);

    constructor(address _owner, address _writer, string memory _uri, address pointsContractAddress)
        Ownable(_owner)
        ERC1155(_uri)
    {
        writer = _writer;
        emit WriterSet(writer);
    }

    modifier onlyWriter() {
        require(msg.sender == writer, "you are not the writer");
        _;
    }

    function updateWriter(address newWriter) public onlyOwner {
        writer = newWriter;
        emit WriterSet(writer);
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

    function closeRound() external onlyOwner {}
}

