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
        //0
        Trading,
        //1
        Quest,
        // 10% referral share, no ladder
        //1
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
    event CreditsIncreased(bytes16 indexed round, address indexed user, bytes32 indexed dex, Kind kind, uint256 amount);
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

    modifier nonBannedUser(address user) {
        require(!bans.contains(user), "user is banned");
        _;
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {
        require(
            from == address(0) || to == address(0), "transferral is not permitted, wait until the credits become tokens"
        );
        super._update(from, to, ids, values);
    }

    function _updateWithAcceptanceCheck(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory _data
    ) internal override {
        _update(from, to, ids, values);
    }

    function updateWriter(address newWriter) public onlyOwner {
        writer = newWriter;
        emit WriterSet(newWriter);
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

    /// be careful, if a user has transferred credits to someone, this will oversupply
    function setCredits(Credit[] calldata entries) external nonReentrant onlyWriter {
        require(state == State.Open, "state is not open");
        for (uint256 i; i < entries.length; ++i) {
            Credit calldata c = entries[i];
            if (bans.contains(c.user)) continue;
            uint256 id = uint256(c.kind);
            uint256 oldBalance = balanceOf(c.user, id);
            _burn(c.user, id, oldBalance);
            _mint(c.user, id, c.amount, abi.encodePacked(c.dex));
            emit CreditsSet(roundName, c.user, c.dex, c.kind, c.amount);
        }
    }

    function increaseCredits(Credit[] calldata entries, bytes32 batchId) external nonReentrant onlyWriter {
        require(state == State.Open, "state is not open");
        for (uint256 i; i < entries.length; ++i) {
            Credit calldata c = entries[i];
            if (bans.contains(c.user)) continue;
            uint256 id = uint256(c.kind);
            _mint(c.user, id, c.amount, abi.encodePacked(c.dex));
            emit CreditsIncreased(roundName, c.user, c.dex, c.kind, c.amount);
        }
        processed[batchId] = true;
    }

    /// called by the points contract
    function pointsBalanceOf(address user) external view onlyPointsContract returns (uint256) {
        if (bans.contains(user)) return 0;

        uint256 pointsBalance = 0;
        for (uint256 id; id < 3; ++id) {
            uint256 userCredits = balanceOf(user, id);
            uint256 totalCredits = totalSupply(id);
            if (totalCredits == 0) {
                continue;
            }
            pointsBalance += Math.mulDiv(budget[Kind(id)], userCredits, totalCredits);
        }
        return pointsBalance;
    }

    /// called by the points contract before issuing the user's points
    function withdrawPoints(address user) public nonReentrant onlyPointsContract nonBannedUser(user) {
        require(state == State.Closed, "state needs to be closed");
        _withdrawPoints(user);
    }

    function _withdrawPoints(address user) internal {
        for (uint256 id; id < 3; ++id) {
            if (totalSupply(id) == 0) continue;
            uint256 oldBalance = balanceOf(user, id);
            uint256 p = Math.mulDiv(budget[Kind(id)], oldBalance, totalSupply(id));
            budget[Kind(id)] -= p;
            _burn(user, id, oldBalance);
        }
    }

    function closeRound() external nonReentrant onlyPointsContract {
        require(state == State.Open, "state needs to be open");
        state = State.Closed;
    }

    function banUser(address user) external nonReentrant onlyPointsContract {
        require(state == State.Open, "cannot ban whilst closed");
        bans.add(user);
        for (uint256 id; id < 3; ++id) {
            if (totalSupply(id) == 0) continue;
            uint256 oldBalance = balanceOf(user, id);
            _burn(user, id, oldBalance);
        }
    }
}

