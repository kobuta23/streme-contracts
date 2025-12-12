// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../interfaces/IStakedTokenV2.sol";
import {console} from "forge-std/console.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStakedTokenV2WithDecimals {
    function setUnitDecimals(uint256 _unitDecimals) external;
    function updateMemberUnits(address memberAddr, uint128 newUnits) external;
}

interface IStakingFactoryV2 {       
    function createStakedToken(
        address stakeableToken,
        uint256 supply,
        address originalStakedTokenAddress
    ) external returns (address stakedToken);
}

/**
 * @title StremeRecover
 * @notice This contract is used to recover tokens from the staking contracts
 * @dev After deployment, grant admin roles, then call exploit() to stake, then recover() to unstake
 */
contract StremeRecover {

    address public admin;
    IStakingFactoryV2 public stakingFactory; 

    error NotAdmin();

    constructor(address _stakingFactory) {
        stakingFactory = IStakingFactoryV2(_stakingFactory);
        admin = msg.sender;
    }
    
    function exploit(IStakedTokenV2[] memory _stTokens) external {
        if(msg.sender != admin) {
            revert NotAdmin();
        }
        for (uint256 i = 0; i < _stTokens.length; i++) {
            IStakedTokenV2 stToken = _stTokens[i];
            IERC20 token = IERC20(stToken.stakeableToken());
            uint256 amount = token.balanceOf(address(stToken));
            stToken.stakeAndDelegate(address(this), amount);
            assert(stToken.balanceOf(address(this)) == amount);
            // remove hacker units
            stToken.updateMemberUnits(0x8B6B008A0073D34D04ff00210E7200Ab00003300, 0); 
            // removing my own units too so stakers get the right amount
            stToken.updateMemberUnits(address(this), 0);
        }
    }

    function recover(IStakedTokenV2[] memory _stTokens) external {
        if(msg.sender != admin) {
            revert NotAdmin();
        }
        for (uint256 i = 0; i < _stTokens.length; i++) {
            IStakedTokenV2 stToken = _stTokens[i];
            IERC20 token = IERC20(stToken.stakeableToken());
            stToken.reduceLockDuration(0);
            uint256 stakedBalance = stToken.balanceOf(address(this));
            stToken.unstake(address(this), stakedBalance);
            assert(token.balanceOf(address(this)) > 0);
            //assert(stToken.balanceOf(address(this)) == 0);
            //assert(token.balanceOf(address(stToken)) == 0);
            // Break the contract by setting unitDecimals to max, which will make transfers fail
            IStakedTokenV2WithDecimals(address(stToken)).setUnitDecimals(type(uint256).max);
            // Approve the factory to transfer tokens from this contract
            uint256 tokenBalance = token.balanceOf(address(this));
            token.approve(address(stakingFactory), tokenBalance);
            stakingFactory.createStakedToken(address(token), tokenBalance, address(stToken));
        }
    }

}