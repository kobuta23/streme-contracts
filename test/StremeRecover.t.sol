// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StremeRecover} from "../contracts/extras/StremeRecover.sol";
import {IStakedTokenV2} from "../contracts/interfaces/IStakedTokenV2.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

/**
 * Run a fork test which does the following:
 * 1. Impersonate the admin and give our contract admin rights 
 * 2. Deploy the recovery contract
 * 3. Check it worked
 */
   

contract StremeRecoverTest is Test {
    StremeRecover public recoveryContract;
    address public admin;
    address public recoveryPot;

    function setUp() public {
        admin = 0x55C4C73aC52B8043057d2CB9A3949a1f433c9331;
        recoveryPot = 0x8b604e9d0FA582f0d5f3C1c3fC4045E5078B6D2f;
    }

    function test_StremeRecover() public {
        // Array of staked token addresses to recover
        address[] memory stTokenAddrs = new address[](2);
        stTokenAddrs[0] = 0x6128f62bFcFF4aC22036307da7a7E94D8016Aa83;
        stTokenAddrs[1] = 0x693dfD8c5FeAf4aEf6784dD831C25E57336e94AA;
        
        bytes32 defaultAdminRole = bytes32(0); // DEFAULT_ADMIN_ROLE is 0x00
        bytes32 managerRole = keccak256("MANAGER_ROLE");
        
        // Convert address array to IStakedTokenV2 array
        IStakedTokenV2[] memory stTokens = new IStakedTokenV2[](stTokenAddrs.length);
        for (uint256 i = 0; i < stTokenAddrs.length; i++) {
            stTokens[i] = IStakedTokenV2(stTokenAddrs[i]);
        }
        
        // Step 1: Deploy the recovery contract as admin
        vm.startPrank(admin);
        recoveryContract = new StremeRecover(recoveryPot);
        vm.stopPrank();
        
        // Step 2: Calculate the recovery contract address and grant roles
        address recoveryContractAddr = address(recoveryContract);
        
        // Grant DEFAULT_ADMIN_ROLE and MANAGER_ROLE to the recovery contract address for all tokens
        vm.startPrank(admin);
        for (uint256 i = 0; i < stTokenAddrs.length; i++) {
            address stTokenAddr = stTokenAddrs[i];
            
            // Check if admin has DEFAULT_ADMIN_ROLE
            bool adminHasRole = AccessControlUpgradeable(stTokenAddr).hasRole(defaultAdminRole, admin);
            require(adminHasRole, "Admin does not have DEFAULT_ADMIN_ROLE");
            
            // Grant roles to recovery contract
            AccessControlUpgradeable(stTokenAddr).grantRole(defaultAdminRole, recoveryContractAddr);
            AccessControlUpgradeable(stTokenAddr).grantRole(managerRole, recoveryContractAddr);
        }
        vm.stopPrank();
        
        // Step 3: Call exploit() to stake all tokens
        vm.prank(admin);
        recoveryContract.exploit(stTokens);
        
        // Step 4: Advance time by 1 second so tokens can be unstaked
        // (lock duration check requires block.timestamp > depositTimestamp + lockDuration)
        vm.warp(block.timestamp + 1);
        
        // Step 5: Call recover() to reduce lock duration, unstake, and drain tokens
        vm.prank(admin);
        recoveryContract.recover(stTokens);
        // print the balance of the stTokens, should be zero but if not at least close
        for (uint256 i = 0; i < stTokenAddrs.length; i++) {
            address stTokenAddr = stTokenAddrs[i];
            IERC20 token = IERC20(IStakedTokenV2(stTokenAddr).stakeableToken());
            uint256 balance = token.balanceOf(stTokenAddr);
            console.log("Balance remaining in stToken: ", stTokenAddr, balance);
        }
    }
}