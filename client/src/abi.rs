use alloy::sol;

// Only what the backend calls, checked against the compiled suite in `abi_test.rs`.
sol! {
    #[sol(rpc, abi)]
    interface DexPalCredits {
        enum Kind { Trading, Quest, Referral }

        struct Credit {
            address user;
            Kind kind;
            bytes32 dex;
            uint256 amount;
        }

        function setCredits(Credit[] calldata entries) external;
        function state() external view returns (uint8);
        function roundName() external view returns (bytes16);
        function writer() external view returns (address);
        function pointsContractAddress() external view returns (address);
        function bannedUsers() external view returns (address[] memory);
        function balanceOfBatch(address[] memory accounts, uint256[] memory ids) external view returns (uint256[] memory);
        function totalSupply(uint256 id) external view returns (uint256);
    }

    #[sol(rpc, abi)]
    interface DexPalPoints {
        function creditsContractAddress() external view returns (address);
        function issuePoints(address[] calldata users) external;
        function balanceOf(address user) external view returns (uint256);
        function predictedBalanceOf(address user) external view returns (uint256);
    }
}
