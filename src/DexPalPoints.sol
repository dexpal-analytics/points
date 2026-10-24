// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.38;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract DexPalPoints is Ownable2StepUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    enum Kind {
        Trading,
        Quest,
        // 10% referral share, no ladder
        Referral
    }

    enum State {
        None,
        Open,
        Closed
    }

    struct Round {
        uint256[3] budget;
        uint256[3] total;
        State state;
    }

    struct Credit {
        address user;
        Kind kind;
        bytes32 dex;
        uint256 amount;
    }

    address public writer;
    bytes16[] internal roundIds;
    mapping(bytes16 round => Round) internal rounds;
    mapping(bytes16 round => mapping(address user => uint256[3])) public userCredits;
    mapping(bytes16 round => mapping(bytes32 dex => uint256)) public dexCredits;
    mapping(bytes16 round => mapping(address user => mapping(Kind kind => mapping(bytes32 dex => uint256)))) public
        credits;
    mapping(bytes16 round => EnumerableSet.AddressSet) internal bans;

    event WriterSet(address writer);
    event RoundOpened(bytes16 indexed round, uint256[3] budget);
    event RoundClosed(bytes16 indexed round);
    event CreditsSet(bytes16 indexed round, address indexed user, bytes32 indexed dex, Kind kind, uint256 amount);
    event Disqualified(bytes16 indexed round, address indexed user, bool banned);

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address initialWriter) external initializer {
        __Ownable_init(initialOwner);
        writer = initialWriter;
        emit WriterSet(initialWriter);
    }

    function setWriter(address newWriter) external onlyOwner {
        writer = newWriter;
        emit WriterSet(newWriter);
    }

    function openRound(bytes16 round, uint256[3] calldata budget) external onlyOwner {
        Round storage r = rounds[round];
        require(r.state == State.None, "round exists");
        r.state = State.Open;
        r.budget = budget;
        roundIds.push(round);
        emit RoundOpened(round, budget);
    }

    function closeRound(bytes16 round) external onlyOwner {
        _open(round).state = State.Closed;
        emit RoundClosed(round);
    }

    function disqualify(bytes16 round, address user) external {
        require(msg.sender == writer || msg.sender == owner(), "not allowed");
        _setDisqualified(round, user, true);
    }

    function requalify(bytes16 round, address user) external onlyOwner {
        _setDisqualified(round, user, false);
    }

    function setCredits(bytes16 round, Credit[] calldata entries) external {
        require(msg.sender == writer, "not writer");
        Round storage r = _open(round);
        for (uint256 i; i < entries.length; ++i) {
            Credit calldata c = entries[i];
            if (bans[round].contains(c.user)) continue;
            uint256 k = uint256(c.kind);
            uint256 old = credits[round][c.user][c.kind][c.dex];
            credits[round][c.user][c.kind][c.dex] = c.amount;
            // Overwrites, so every total moves by the difference and a resent batch changes nothing.
            userCredits[round][c.user][k] = userCredits[round][c.user][k] - old + c.amount;
            r.total[k] = r.total[k] - old + c.amount;
            if (c.kind == Kind.Trading) dexCredits[round][c.dex] = dexCredits[round][c.dex] - old + c.amount;
            emit CreditsSet(round, c.user, c.dex, c.kind, c.amount);
        }
    }

    /// points estimation, pre- round close
    function points(bytes16 round, address user) public view returns (uint256 sum) {
        if (bans[round].contains(user)) return 0;
        Round storage r = rounds[round];
        for (uint256 k; k < 3; ++k) {
            if (r.total[k] > 0) sum += Math.mulDiv(r.budget[k], userCredits[round][user][k], r.total[k]);
        }
    }

    function lifetime(address user) external view returns (uint256 sum) {
        for (uint256 i; i < roundIds.length; ++i) {
            if (rounds[roundIds[i]].state == State.Closed) sum += points(roundIds[i], user);
        }
    }

    function getRound(bytes16 round) external view returns (Round memory) {
        return rounds[round];
    }

    function disqualified(bytes16 round, address user) external view returns (bool) {
        return bans[round].contains(user);
    }

    function disqualifiedUsers(bytes16 round) external view returns (address[] memory) {
        return bans[round].values();
    }

    function renounceOwnership() public pure override {
        revert("cannot renounce");
    }

    function _setDisqualified(bytes16 round, address user, bool banned) private {
        _open(round);
        if (banned) bans[round].add(user);
        else bans[round].remove(user);
        emit Disqualified(round, user, banned);
    }

    function _open(bytes16 round) private view returns (Round storage r) {
        r = rounds[round];
        require(r.state == State.Open, "round not open");
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
