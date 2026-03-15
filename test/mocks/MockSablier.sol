// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ISablierLockupLinear {
    struct Durations {
        uint40 cliff;
        uint40 total;
    }

    struct CreateWithDurations {
        address sender;
        address recipient;
        uint128 totalAmount;
        address asset;
        bool cancelable;
        bool transferable;
        Durations durations;
        uint128 startAmount;
        address broker;
    }

    function createWithDurations(CreateWithDurations calldata params) external returns (uint256 streamId);
}

/// @title MockSablier
/// @notice A mock Sablier contract for testing. Pulls tokens from sender and holds them.
contract MockSablier is ISablierLockupLinear {
    using SafeERC20 for IERC20;

    uint256 private s_nextStreamId = 1;

    struct Stream {
        address sender;
        address recipient;
        uint128 totalAmount;
        address asset;
        uint128 startAmount;
        uint40 cliffDuration;
        uint40 totalDuration;
    }

    mapping(uint256 => Stream) public streams;

    event StreamCreated(
        uint256 indexed streamId, address indexed sender, address indexed recipient, uint128 totalAmount, address asset
    );

    function createWithDurations(CreateWithDurations calldata params) external override returns (uint256 streamId) {
        streamId = s_nextStreamId++;

        IERC20(params.asset).safeTransferFrom(params.sender, address(this), params.totalAmount);

        streams[streamId] = Stream({
            sender: params.sender,
            recipient: params.recipient,
            totalAmount: params.totalAmount,
            asset: params.asset,
            startAmount: params.startAmount,
            cliffDuration: params.durations.cliff,
            totalDuration: params.durations.total
        });

        emit StreamCreated(streamId, params.sender, params.recipient, params.totalAmount, params.asset);
    }

    function getStream(uint256 streamId) external view returns (Stream memory) {
        return streams[streamId];
    }

    function nextStreamId() external view returns (uint256) {
        return s_nextStreamId;
    }
}
