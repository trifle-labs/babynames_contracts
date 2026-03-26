// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IBetSlipRenderer
 * @notice Interface for the external SVG renderer contract
 */
interface IBetSlipRenderer {
    struct SlipData {
        uint256 tokenId;
        string  poolName;
        uint256 year;
        uint8   categoryType;
        uint8   gender;
        uint256 position;
        uint256 amount;
        uint8   tokenDecimals;
        uint256 purchasedAt;
        uint256 deadline;
        uint256 currentTime;
        uint256 poolCollateral;
        uint256 categoryCollateral;
        bool    resolved;
        bool    won;
    }

    function renderTokenURI(SlipData calldata d) external view returns (string memory);
}
