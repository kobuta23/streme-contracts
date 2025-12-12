// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StremeRecover} from "../contracts/extras/StremeRecover.sol";
import {IStakedTokenV2} from "../contracts/interfaces/IStakedTokenV2.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/**
 * Run a fork test which does the following:
 * 1. Impersonate the admin and give our contract admin rights 
 * 2. Deploy the recovery contract
 * 3. Check it worked
 */
   

interface IStakingFactoryV2 {
    function createStakedToken(
        address stakeableToken,
        uint256 supply
    ) external returns (address stakedToken);
}

contract StremeRecoverTest is Test {
    StremeRecover public recoveryContract;
    address public admin;
    IStakingFactoryV2 public stakingFactory;

    function setUp() public {
        // Create a fork of Base network
        // Use environment variable if available, otherwise use a public RPC
        string memory rpcUrl = vm.envOr("API_URL_BASE", string("https://mainnet.base.org"));
        vm.createSelectFork(rpcUrl);
        
        admin = 0x55C4C73aC52B8043057d2CB9A3949a1f433c9331;
        // TODO: Set the actual staking factory address or deploy it in the test
        // For now, using a placeholder - this will need to be updated
        stakingFactory = IStakingFactoryV2(0x30121dC4F99523087cb0ae8Ee001e651F6e30464);
    }

    function test_StremeRecover() public {
        // Array of staked token addresses to recover
        address[] memory stTokenAddrs = new address[](1);
        stTokenAddrs[0] = 0x6128f62bFcFF4aC22036307da7a7E94D8016Aa83;
        // stTokenAddrs[1] = 0x693dfD8c5FeAf4aEf6784dD831C25E57336e94AA; // Temporarily disabled due to RPC issues
        
        bytes32 defaultAdminRole = bytes32(0); // DEFAULT_ADMIN_ROLE is 0x00
        bytes32 managerRole = keccak256("MANAGER_ROLE");
        
        // Convert address array to IStakedTokenV2 array
        IStakedTokenV2[] memory stTokens = new IStakedTokenV2[](stTokenAddrs.length);
        for (uint256 i = 0; i < stTokenAddrs.length; i++) {
            stTokens[i] = IStakedTokenV2(stTokenAddrs[i]);
        }
        
        // Step 1: Deploy the recovery contract as admin
        vm.startPrank(admin);
        recoveryContract = new StremeRecover(address(stakingFactory));
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
        
        // Step 5: Call recover() to reduce lock duration, unstake, drain tokens, and break transfers
        vm.prank(admin);
        recoveryContract.recover(stTokens);
        
        // Step 5.5: Verify that tokens were transferred to the new staked token contract
        // Note: The factory creates a new staked token and transfers tokens to it
        // We can verify this by checking the recovery contract has 0 tokens after recover()
        for (uint256 i = 0; i < stTokenAddrs.length; i++) {
            address stTokenAddr = stTokenAddrs[i];
            IERC20 token = IERC20(IStakedTokenV2(stTokenAddr).stakeableToken());
            uint256 recoveryBalance = token.balanceOf(address(recoveryContract));
            console.log("Recovery contract token balance after recover: ", recoveryBalance);
            // All tokens should have been transferred to the new staked token contract
            assertEq(recoveryBalance, 0, "All tokens should be transferred to new staked token");
        }
        
        // Step 6: Verify that transfers, stake, and stakeAndDelegate are broken
        // The _units() calculation will overflow when computing 10 ** type(uint256).max
        // This will cause any transfer or stake operation to fail
        for (uint256 i = 0; i < stTokenAddrs.length; i++) {
            address stTokenAddr = stTokenAddrs[i];
            IERC20 token = IERC20(IStakedTokenV2(stTokenAddr).stakeableToken());
            uint256 balance = token.balanceOf(stTokenAddr);
            console.log("Balance remaining in stToken: ", stTokenAddr, balance);
            console.log("Balance of token remaining in this: ", token.balanceOf(address(this)));
            console.log("Balance of stToken remaining in this: ", address(this), IStakedTokenV2(stTokenAddr).balanceOf(address(this)));
            // Verify that _units() calculation fails due to unitDecimals overflow
            // Calling tokensToUnits() (which calls _units()) should revert
            // because 10 ** type(uint256).max will overflow
            vm.expectRevert();
            IStakedTokenV2(stTokenAddr).tokensToUnits(1);
        }
    }
}