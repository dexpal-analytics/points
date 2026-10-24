// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IDexPalCredits {
    function pointsBalanceOf(address user) external view returns (uint256);
    function pointsContractAddress() external view returns (address);
    function owedPoints() external view returns (uint256);
    function withdrawPoints(address user) external returns (uint256);
    function openRound(bytes16 _roundName, uint256[3] calldata newBudget) external;
    function closeRound() external;
    function banUser(address user) external;
}

contract DexPalCredits is ERC1155Supply, IDexPalCredits, Ownable2Step, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    enum State {
        Closed,
        Open
    }

    enum Kind {
        Trading,
        Quest,
        // 10% referral share, no ladder
        Referral
    }

    mapping(Kind kind => uint256) public budget;
    mapping(bytes32 batchId => bool) public processed;

    struct Credit {
        address user;
        Kind kind;
        bytes32 dex;
        uint256 amount;
    }

    address public immutable pointsContractAddress;
    address public writer;
    State public state;
    bytes16 public roundName;
    EnumerableSet.AddressSet private bans;

    event WriterSet(address writer);
    event RoundOpened(bytes16 indexed round, uint256[3] budget);
    event RoundClosed(bytes16 indexed round);
    event CreditsSet(bytes16 indexed round, address indexed user, bytes32 indexed dex, Kind kind, uint256 amount);
    event CreditsIncreased(bytes16 indexed round, address indexed user, bytes32 indexed dex, Kind kind, uint256 amount);
    event Disqualified(bytes16 indexed round, address indexed user, bool banned);

    constructor(address _owner, address _writer, string memory _uri, address _pointsContract)
        Ownable(_owner)
        ERC1155(_uri)
    {
        writer = _writer;
        pointsContractAddress = _pointsContract;
        emit WriterSet(_writer);
    }

    modifier onlyWriter() {
        require(msg.sender == writer, "you are not the writer");
        _;
    }

    modifier onlyPointsContract() {
        require(msg.sender == pointsContractAddress, "you are not the points contract");
        _;
    }

    function renounceOwnership() public pure override {
        revert("cannot renounce");
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {
        // forge-lint: disable-start(require-revert-in-loop)
        require(from == address(0) || to == address(0), "credits are not transferable");
        // forge-lint: disable-end(require-revert-in-loop)
        super._update(from, to, ids, values);
    }

    /// allows any contract (i.e. don't need IERC1155Receiver implemented)
    function _updateWithAcceptanceCheck(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory,
        bool
    ) internal override {
        _update(from, to, ids, values);
    }

    function updateWriter(address newWriter) public onlyOwner {
        writer = newWriter;
        emit WriterSet(newWriter);
    }

    function isBanned(address user) external view returns (bool) {
        return bans.contains(user);
    }

    function bannedUsers() external view returns (address[] memory) {
        return bans.values();
    }

    function owedPoints() external view returns (uint256 owed) {
        for (uint256 id; id < 3; ++id) {
            if (state == State.Open || totalSupply(id) != 0) owed += budget[Kind(id)];
        }
    }

    function openRound(bytes16 _roundName, uint256[3] calldata newBudget) external nonReentrant onlyPointsContract {
        require(totalSupply(0) == 0, "remaining user credits left");
        require(totalSupply(1) == 0, "remaining user credits left");
        require(totalSupply(2) == 0, "remaining user credits left");

        require(state == State.Closed, "call closeRound first");
        roundName = _roundName;
        for (uint8 i; i < 3; ++i) {
            budget[Kind(i)] = newBudget[i];
        }
        emit RoundOpened(_roundName, newBudget);
        state = State.Open;
    }

    function setCredits(Credit[] calldata entries) external nonReentrant onlyWriter {
        require(state == State.Open, "state is not open");
        for (uint256 i; i < entries.length; ++i) {
            Credit calldata c = entries[i];
            if (bans.contains(c.user)) continue;
            uint256 id = uint256(c.kind);
            _burn(c.user, id, balanceOf(c.user, id));
            _mint(c.user, id, c.amount, "");
            emit CreditsSet(roundName, c.user, c.dex, c.kind, c.amount);
        }
    }

    function increaseCredits(Credit[] calldata entries, bytes32 batchId) external nonReentrant onlyWriter {
        require(state == State.Open, "state is not open");
        require(!processed[batchId], "batch already processed");
        for (uint256 i; i < entries.length; ++i) {
            Credit calldata c = entries[i];
            if (bans.contains(c.user)) continue;
            _mint(c.user, uint256(c.kind), c.amount, "");
            emit CreditsIncreased(roundName, c.user, c.dex, c.kind, c.amount);
        }
        processed[batchId] = true;
    }

    function pointsBalanceOf(address user) external view onlyPointsContract returns (uint256 points) {
        for (uint256 id; id < 3; ++id) {
            uint256 totalCredits = totalSupply(id);
            if (totalCredits == 0) continue;
            points += Math.mulDiv(budget[Kind(id)], balanceOf(user, id), totalCredits);
        }
    }

    function withdrawPoints(address user) external nonReentrant onlyPointsContract returns (uint256 points) {
        require(state == State.Closed, "state needs to be closed");
        for (uint256 id; id < 3; ++id) {
            uint256 totalCredits = totalSupply(id);
            if (totalCredits == 0) continue;
            uint256 credits = balanceOf(user, id);
            uint256 share = Math.mulDiv(budget[Kind(id)], credits, totalCredits);
            budget[Kind(id)] -= share;
            points += share;
            _burn(user, id, credits);
        }
    }

    function closeRound() external nonReentrant onlyPointsContract {
        require(state == State.Open, "state needs to be open");
        state = State.Closed;
        emit RoundClosed(roundName);
    }

    function banUser(address user) external nonReentrant onlyPointsContract {
        require(state == State.Open, "cannot ban whilst closed");
        if (!bans.add(user)) return;
        for (uint256 id; id < 3; ++id) {
            _burn(user, id, balanceOf(user, id));
        }
        emit Disqualified(roundName, user, true);
    }
}
