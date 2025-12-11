// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../interfaces/IStakedTokenV2.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title StremeRecover
 * @notice This contract is used to recover tokens from the staking contracts
 * @dev After deployment, grant admin roles, then call exploit() to stake, then recover() to unstake
 */
contract StremeRecover {

    address public recoveryPot;
    address public admin;

    error NotAdmin();

    constructor(address _recoveryPot) {
        recoveryPot = _recoveryPot;
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
            stToken.unstake(recoveryPot, stToken.balanceOf(address(this)));
            assert(token.balanceOf(recoveryPot) > 0);
            assert(token.balanceOf(address(this)) == 0);
            assert(stToken.balanceOf(address(this)) == 0);
        }
    }
}