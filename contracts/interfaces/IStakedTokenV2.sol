// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IStakedTokenV2 {
    function stakeAndDelegate(address delegateTo, uint256 amount) external;
    function reduceLockDuration(uint256 newDuration) external;
    function unstake(address to, uint256 amount) external;
    function stakeableToken() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function updateMemberUnits(address memberAddr, uint128 newUnits) external;
    function tokensToUnits(uint256 amount) external view returns (uint128);
    function stake(address to, uint256 amount) external;
}

