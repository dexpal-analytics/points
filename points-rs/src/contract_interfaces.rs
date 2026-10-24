use alloy::sol;
sol! {
    #[sol(rpc)]
    interface IDexPalCredits {
        enum Kind { Trading, Quest, Referral }
        enum State { Closed, Open }

        struct Credit {
            address user;
            Kind kind;
            bytes32 dex;
            uint256 amount;
        }

        event WriterSet(address writer);
        event PointsContractSet(address pointsContract);
        event RoundOpened(bytes16 indexed round, uint256[3] budget);
        event RoundClosed(bytes16 indexed round);
        event CreditsSet(bytes16 indexed round, address indexed user, bytes32 indexed dex, Kind kind, uint256 amount);
        event CreditsIncreased(bytes16 indexed round, address indexed user, bytes32 indexed dex, Kind kind, uint256 amount);
        event Disqualified(bytes16 indexed round, address indexed user, bool banned);

        // writer
        function setCredits(Credit[] calldata entries) external;
        function increaseCredits(Credit[] calldata entries, bytes32 batchId) external;

        // owner
        function setPointsContractAddress(address newPointsContractAddress) external;
        function updateWriter(address newWriter) external;

        // views
        function owner() external view returns (address);
        function writer() external view returns (address);
        function pointsContractAddress() external view returns (address);
        function state() external view returns (State);
        function roundName() external view returns (bytes16);
        function budget(Kind kind) external view returns (uint256);
        function processed(bytes32 batchId) external view returns (bool);
        function balanceOf(address account, uint256 id) external view returns (uint256);
        function totalSupply(uint256 id) external view returns (uint256);
    }

    #[sol(rpc)]
    interface IDexPalPoints {
        event NumeraireChanged(address newNumeraire);
        event PointsConversionChanged(address newPointsConversion);
        event CreditsContractAddressChanged(address newCreditsContract);
        event Transfer(address indexed from, address indexed to, uint256 value);

        // user
        function claimPoints(address from, address to) external;

        // owner
        function openRound(bytes16 roundName, uint256[3] calldata newBudget) external;
        function closeRound() external;
        function banUser(address user) external;
        function issuePoints(address user) external;
        function updateNumeraire(address newNumeraire) external;
        function updatePointsConversion(address pointsConversion) external;
        function updateCreditsContractAddress(address newCreditsContractAddress) external;

        // views
        function owner() external view returns (address);
        function numeraire() external view returns (address);
        function pointsConversion() external view returns (address);
        function creditsContractAddress() external view returns (address);
        function balanceOf(address user) external view returns (uint256);
        function totalSupply() external view returns (uint256);
        function predictedBalanceOf(address user) external view returns (uint256);
        function predictedBalanceOfConverted(address user) external view returns (uint256);
        function balanceOfConverted(address user) external view returns (uint256);
    }
}
