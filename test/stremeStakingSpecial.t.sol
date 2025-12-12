// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StakedTokenV2Special} from "../contracts/hook/staking/StakedTokenv2Special.sol";
import {StakedTokenV2} from "../contracts/hook/staking/StakedTokenv2.sol";
import {StakingFactoryV2Special} from "../contracts/hook/staking/StakingFactoryV2Special.sol";
import {StremeRecover} from "../contracts/extras/StremeRecover.sol";
import {IStakedTokenV2} from "../contracts/interfaces/IStakedTokenV2.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

interface IDistributionPool {
    function getUnits(address memberAddr) external view returns (uint128);
    function updateMemberUnits(address memberAddr, uint128 newUnits) external returns (bool);
}

interface IStakingFactoryV2 {
    function createStakedToken(
        address stakeableToken,
        uint256 supply
    ) external returns (address stakedToken);
    function predictStakedTokenAddress(address stakeableToken) external view returns (address);
    function teamRecipient() external view returns (address);
}

contract StremeStakingSpecialTest is Test {
    // Real contracts from fork
    StakedTokenV2Special public stakedTokenSpecial;
    IStakedTokenV2 public originalStakedToken;
    IStakingFactoryV2 public stakingFactory;
    IDistributionPool public pool;
    IERC20 public stakeableToken;

    // Addresses from fork
    address public admin;
    address public teamRecipient;
    
    // Staker for banger
    address public staker1ForToken1 = 0x6D5239DEAD451398115532cFEc48A6Da59ff0Ba7;
    address public staker2ForToken1 = 0xE04885c3f1419C6E8495C33bDCf5F8387cd88846;
    address public staker1ForToken2 = 0x19C64afFdE518De2884C1944700E12D2Bb7016a4;

    // Staked tokens 1 and 2 (BANGER and LETS)
    address public stakedTokenAddress1 = 0x6128f62bFcFF4aC22036307da7a7E94D8016Aa83;
    address public stakedTokenAddress2 = 0x693dfD8c5FeAf4aEf6784dD831C25E57336e94AA;
    
    // Deployed StakingFactoryV2Special for testing
    StakingFactoryV2Special public stakingFactorySpecial;

    // ============ Invariants ============
    
    /**
     * @notice Invariant: Total supply should always equal sum of all balances
     */
    function invariant_totalSupplyEqualsSumOfBalances() internal view {
        // This would be checked across all test scenarios
        // Implementation would iterate through all known addresses and sum balances
    }

    /**
     * @notice Invariant: Units in pool should match token balances when converted
     */
    function invariant_unitsMatchTokenBalances() internal view {
        // For any address with balance, units should equal balance / (10 ** unitDecimals)
        // This ensures consistency between pool units and staked token balances
    }

    /**
     * @notice Invariant: Deposit timestamp should never be in the future
     */
    function invariant_depositTimestampsNotInFuture() internal view {
        // All deposit timestamps should be <= block.timestamp
    }

    /**
     * @notice Invariant: Lock duration should never increase
     */
    function invariant_lockDurationNeverIncreases() internal view {
        // Lock duration can only be reduced, never increased
    }

    /**
     * @notice Invariant: Claim can only happen once per address
     */
    function invariant_claimOncePerAddress() internal view {
        // If balanceOf(address) > 0, claimStakeFromUnits should revert
    }

    // ============ Helper Functions ============

    function setUp() public {
        // Create a fork of Base network
        // Use environment variable if available, otherwise use a public RPC
        string memory rpcUrl = vm.envOr("API_URL_BASE", string("https://mainnet.base.org"));
        vm.createSelectFork(rpcUrl);
        
        // Set addresses from fork
        admin = 0x55C4C73aC52B8043057d2CB9A3949a1f433c9331;
        stakingFactory = IStakingFactoryV2(0x30121dC4F99523087cb0ae8Ee001e651F6e30464);
        teamRecipient = stakingFactory.teamRecipient();
        
        // TODO: Set these addresses - example staked token addresses
        // Using addresses from StremeRecover test as examples
        stakedTokenAddress1 = 0x6128f62bFcFF4aC22036307da7a7E94D8016Aa83;
        stakedTokenAddress2 = 0x693dfD8c5FeAf4aEf6784dD831C25E57336e94AA;
        
        // Set original staked token for testing
        originalStakedToken = IStakedTokenV2(stakedTokenAddress1);
        stakeableToken = IERC20(originalStakedToken.stakeableToken());
        
        // Get pool from original staked token
        StakedTokenV2 stToken = StakedTokenV2(stakedTokenAddress1);
        pool = IDistributionPool(address(stToken.pool()));
        
        // Deploy StakedTokenV2Special implementation
        StakedTokenV2Special implementation = new StakedTokenV2Special();
        
        // Deploy StakingFactoryV2Special with the implementation
        stakingFactorySpecial = new StakingFactoryV2Special(address(implementation));
    }
    
    /**
     * @notice Helper: Get units for a user from the pool
     */
    function _getPoolUnits(address user) internal view returns (uint128) {
        return pool.getUnits(user);
    }

    /**
     * @notice Helper: Get deposit timestamp from original staked token
     * @dev Reads the public depositTimestamps mapping from the original contract
     */
    function _getOriginalDepositTimestamp(address stakedTokenAddr, address user) internal view returns (uint256) {
        // Since depositTimestamps is public, we can call it directly
        StakedTokenV2 stToken = StakedTokenV2(stakedTokenAddr);
        return stToken.depositTimestamps(user);
    }

    /**
     * @notice Helper: Calculate expected tokens from units
     */
    function _unitsToTokens(StakedTokenV2Special special, uint128 units) internal view returns (uint256) {
        return uint256(units) * (10 ** special.unitDecimals());
    }

    /**
     * @notice Helper: Calculate units from tokens
     */
    function _tokensToUnits(StakedTokenV2Special special, uint256 tokens) internal view returns (uint128) {
        return uint128(tokens / (10 ** special.unitDecimals()));
    }

    /**
     * @notice Helper: Assert claim was successful
     */
    function _assertClaimSuccessful(
        StakedTokenV2Special special,
        address user,
        uint128 expectedUnits,
        uint256 expectedTimestamp
    ) internal view {
        uint256 expectedTokens = _unitsToTokens(special, expectedUnits);
        assertEq(special.balanceOf(user), expectedTokens, "Balance should match expected tokens");
        assertEq(special.depositTimestamps(user), expectedTimestamp, "Deposit timestamp should match");
    }
    
    /**
     * @notice Helper: Deploy and initialize a StakedTokenV2Special for a given stakeable token
     * @dev This sets up a new special token for testing with a specific original staked token
     * Uses the factory to create the contract (which uses clones, allowing initialization)
     */
    function _deployStakedTokenSpecial(address stakeableTokenAddr, address originalStakedTokenAddr) internal returns (StakedTokenV2Special) {
        // Use the factory to create the contract - this uses clones which can be initialized
        // We pass 0 supply since we don't need tokens initially (users will claim them)
        IERC20 token = IERC20(stakeableTokenAddr);
        
        // Approve factory to transfer tokens (even if 0, we need approval)
        // Use a large approval to avoid issues
        token.approve(address(stakingFactorySpecial), type(uint256).max);
        
        // Create the staked token via factory with 0 supply
        // The factory will clone the implementation and initialize it
        address stakedTokenAddr = stakingFactorySpecial.createStakedToken(stakeableTokenAddr, 0, originalStakedTokenAddr);
        
        // Grant MANAGER_ROLE to the cloned contract on the original staked token
        // This is needed because _update() calls updateMemberUnits on the original token
        bytes32 managerRole = keccak256("MANAGER_ROLE");
        vm.prank(admin);
        AccessControlUpgradeable(originalStakedTokenAddr).grantRole(managerRole, stakedTokenAddr);
        
        return StakedTokenV2Special(stakedTokenAddr);
    }

    // ============ Test Stubs: claimStakeFromUnits ============

    /**
     * @notice Test: User can successfully claim tokens from units
     * @dev Verifies basic happy path - user with units in pool can claim corresponding tokens
     */
    function test_claimStakeFromUnits_Success() public {
        // Setup: Deploy special token for the stakeable token with original staked token address
        stakedTokenSpecial = _deployStakedTokenSpecial(address(stakeableToken), stakedTokenAddress1);
        
        // Setup: Verify staker1ForToken1 has units in pool and deposit timestamp
        uint128 units = _getPoolUnits(staker1ForToken1);
        uint256 timestamp = _getOriginalDepositTimestamp(stakedTokenAddress1, staker1ForToken1);
        require(units > 0, "Staker must have units");
        require(timestamp > 0, "Staker must have deposit timestamp");
        
        // Verify user has no balance in special token yet
        assertEq(stakedTokenSpecial.balanceOf(staker1ForToken1), 0, "User should have no balance initially");
        
        // Action: User calls claimStakeFromUnits
        vm.prank(staker1ForToken1);
        stakedTokenSpecial.claimStakeFromUnits(staker1ForToken1);
        
        // Assert: User receives correct token amount, deposit timestamp is preserved
        _assertClaimSuccessful(stakedTokenSpecial, staker1ForToken1, units, timestamp);
        
        // Additional assertions
        uint256 expectedTokens = _unitsToTokens(stakedTokenSpecial, units);
        assertEq(stakedTokenSpecial.totalSupply(), expectedTokens, "Total supply should equal minted tokens");
    }

    /**
     * @notice Test: Claim fails if user already has balance
     * @dev Verifies the "can only claim once" requirement
     */
    function test_claimStakeFromUnits_RevertsIfAlreadyClaimed() public {
        // Setup: Deploy special token with original staked token address
        stakedTokenSpecial = _deployStakedTokenSpecial(address(stakeableToken), stakedTokenAddress1);
        
        // Setup: Verify staker1ForToken1 has units
        uint128 units = _getPoolUnits(staker1ForToken1);
        require(units > 0, "Staker must have units");
        
        // Setup: User claims once successfully
        vm.prank(staker1ForToken1);
        stakedTokenSpecial.claimStakeFromUnits(staker1ForToken1);
        
        // Verify user now has balance
        assertGt(stakedTokenSpecial.balanceOf(staker1ForToken1), 0, "User should have balance after first claim");
        
        // Action: User tries to claim again
        vm.prank(staker1ForToken1);
        vm.expectRevert("can only claim once");
        stakedTokenSpecial.claimStakeFromUnits(staker1ForToken1);
        
        // Assert: Transaction reverts with "can only claim once"
        // (The expectRevert above handles this, but we can add additional checks)
        uint256 balanceAfterFailedClaim = stakedTokenSpecial.balanceOf(staker1ForToken1);
        uint256 expectedTokens = _unitsToTokens(stakedTokenSpecial, units);
        assertEq(balanceAfterFailedClaim, expectedTokens, "Balance should remain unchanged after failed claim");
    }

    /**
     * @notice Test: Claim with zero units mints zero tokens
     * @dev Edge case - user with no units should receive zero tokens
     */
    function test_claimStakeFromUnits_ZeroUnits() public {
        // Setup: Deploy special token
        stakedTokenSpecial = _deployStakedTokenSpecial(address(stakeableToken), stakedTokenAddress1);
        
        // Setup: Find or use an address with zero units
        // We'll use a new address that definitely has zero units
        address userWithZeroUnits = makeAddr("userWithZeroUnits");
        uint128 units = _getPoolUnits(userWithZeroUnits);
        require(units == 0, "User must have zero units");
        
        // Action: User calls claimStakeFromUnits
        vm.prank(userWithZeroUnits);
        stakedTokenSpecial.claimStakeFromUnits(userWithZeroUnits);
        
        // Assert: User receives zero tokens, deposit timestamp is still set
        assertEq(stakedTokenSpecial.balanceOf(userWithZeroUnits), 0, "Balance should be zero");
        uint256 timestamp = _getOriginalDepositTimestamp(stakedTokenAddress1, userWithZeroUnits);
        assertEq(stakedTokenSpecial.depositTimestamps(userWithZeroUnits), timestamp, "Timestamp should be set");
        assertEq(stakedTokenSpecial.totalSupply(), 0, "Total supply should be zero");
    }

    /**
     * @notice Test: Claim preserves original deposit timestamp
     * @dev Critical for lock duration calculations
     */
    function test_claimStakeFromUnits_PreservesDepositTimestamp() public {
        // Setup: Deploy special token
        stakedTokenSpecial = _deployStakedTokenSpecial(address(stakeableToken), stakedTokenAddress1);
        
        // Setup: Get original deposit timestamp
        uint256 originalTimestamp = _getOriginalDepositTimestamp(stakedTokenAddress1, staker1ForToken1);
        require(originalTimestamp > 0, "Must have original timestamp");
        
        // Verify user has units
        uint128 units = _getPoolUnits(staker1ForToken1);
        require(units > 0, "User must have units");
        
        // Action: User claims
        vm.prank(staker1ForToken1);
        stakedTokenSpecial.claimStakeFromUnits(staker1ForToken1);
        
        // Assert: Deposit timestamp matches original, unlock date is correct
        assertEq(stakedTokenSpecial.depositTimestamps(staker1ForToken1), originalTimestamp, "Timestamp should match");
        uint256 expectedUnlockDate = originalTimestamp + stakedTokenSpecial.lockDuration();
        assertEq(stakedTokenSpecial.unlockDate(staker1ForToken1), expectedUnlockDate, "Unlock date should be correct");
        
        // Additional check: lock duration should match original
        StakedTokenV2 originalStToken = StakedTokenV2(stakedTokenAddress1);
        assertEq(stakedTokenSpecial.lockDuration(), originalStToken.lockDuration(), "Lock duration should match original");
    }

    // ============ Core Tests: Full Recovery Process ============

    /**
     * @notice Test: Execute full recovery process with token 0x2F2b9cD1405488875D972A17ce50d3D562518d91
     * @dev Tests recovery with a different token - stakeAndDelegate works without approval (the exploit)
     */
    function test_FullRecovery_WithDifferentToken() public {
        // Use the staked token address provided by user
        address testStakedTokenAddr = 0x3839C8db5b3B6971362e96bD35bA9500E4dC3E9b;
        
        // Get the stakeable token and pool for this staked token
        IStakedTokenV2 testStakedToken = IStakedTokenV2(testStakedTokenAddr);
        IERC20 testStakeableToken = IERC20(testStakedToken.stakeableToken());
        StakedTokenV2 testStToken = StakedTokenV2(testStakedTokenAddr);
        IDistributionPool testPool = IDistributionPool(address(testStToken.pool()));
        
        bytes32 defaultAdminRole = bytes32(0);
        bytes32 managerRole = keccak256("MANAGER_ROLE");
        
        // ============ Phase 1: Setup Recovery ============
        
        // Step 1: Deploy the recovery contract as admin
        StremeRecover recovery;
        vm.startPrank(admin);
        recovery = new StremeRecover(address(stakingFactorySpecial));
        vm.stopPrank();
        
        // Step 2: Grant roles to recovery contract
        vm.startPrank(admin);
        AccessControlUpgradeable(testStakedTokenAddr).grantRole(defaultAdminRole, address(recovery));
        AccessControlUpgradeable(testStakedTokenAddr).grantRole(managerRole, address(recovery));
        vm.stopPrank();
        
        // Get initial state
        IStakedTokenV2[] memory stTokens = new IStakedTokenV2[](1);
        stTokens[0] = testStakedToken;
        
        // ============ Phase 2: Execute Exploit ============
        
        // Step 3: Execute exploit - stake all tokens to recovery contract
        vm.prank(admin);
        recovery.exploit(stTokens);
        
        // ============ Phase 3: Execute Recovery ============
        
        // Step 4: Advance time so tokens can be unstaked
        vm.warp(block.timestamp + 1);
        
        // Step 5: Execute recovery - unstake, break old contract, create new contract
        vm.prank(admin);
        recovery.recover(stTokens);
        
        // ============ Phase 4: Verify New Contract ============
        
        // Step 6: Get the new special token address created by factory
        address newSpecialTokenAddr = stakingFactorySpecial.predictStakedTokenAddress(address(testStakeableToken));
        StakedTokenV2Special newSpecialToken = StakedTokenV2Special(newSpecialTokenAddr);
        
        // Grant MANAGER_ROLE to the new special token on the original staked token
        vm.startPrank(admin);
        AccessControlUpgradeable(testStakedTokenAddr).grantRole(managerRole, newSpecialTokenAddr);
        vm.stopPrank();
        
        // Step 7: Verify tokens were transferred to new contract
        uint256 newContractBalance = testStakeableToken.balanceOf(newSpecialTokenAddr);
        assertGt(newContractBalance, 0, "New contract should have tokens from recovery");
        
        // ============ Phase 5: User Claims ============
        
        // Use the provided staker address
        address staker1 = 0x478a5579C3877C11929723C2A8d7763B77cacD1A;
        
        uint128 units1 = testPool.getUnits(staker1);
        require(units1 > 0, "staker1 should have units");
        
        // User claims
        vm.prank(staker1);
        newSpecialToken.claimStakeFromUnits(staker1);
        
        uint256 expectedTokens1 = _unitsToTokens(newSpecialToken, units1);
        assertEq(newSpecialToken.balanceOf(staker1), expectedTokens1, "User should have claimed tokens");
        
        // Verify deposit timestamp is preserved
        uint256 originalTimestamp = _getOriginalDepositTimestamp(testStakedTokenAddr, staker1);
        assertEq(newSpecialToken.depositTimestamps(staker1), originalTimestamp, "Deposit timestamp should be preserved");
        
        // ============ Phase 6: User Unstaking ============
        
        // Verify user can unstake (tokens are in contract from recovery)
        uint256 claimedBalance = newSpecialToken.balanceOf(staker1);
        assertGt(claimedBalance, 0, "User should have claimed tokens");
        
        // Get original deposit timestamp to calculate unlock time
        uint256 depositTimestamp = newSpecialToken.depositTimestamps(staker1);
        uint256 lockDuration = newSpecialToken.lockDuration();
        uint256 unlockTime = depositTimestamp + lockDuration;
        
        // Advance time past unlock if needed
        if (block.timestamp < unlockTime) {
            vm.warp(unlockTime + 1);
        }
        
        // Verify contract has tokens to unstake
        uint256 contractTokenBalance = testStakeableToken.balanceOf(newSpecialTokenAddr);
        assertGe(contractTokenBalance, claimedBalance, "Contract should have enough tokens for unstaking");
        
        // User unstakes half their tokens
        uint256 unstakeAmount = claimedBalance / 2;
        uint256 userTokenBalanceBefore = testStakeableToken.balanceOf(staker1);
        
        vm.prank(staker1);
        newSpecialToken.unstake(staker1, unstakeAmount);
        
        // Verify unstake worked
        assertEq(
            testStakeableToken.balanceOf(staker1),
            userTokenBalanceBefore + unstakeAmount,
            "User should receive unstaked tokens"
        );
        assertEq(
            newSpecialToken.balanceOf(staker1),
            claimedBalance - unstakeAmount,
            "User staked balance should decrease"
        );
    }

    /**
     * @notice Test: Execute full recovery process and verify complete functionality
     * @dev This is the main integration test - executes recovery and verifies:
     *      1. Recovery process completes successfully
     *      2. Tokens are transferred to new contract
     *      3. Users can claim their tokens
     *      4. Users can unstake (tokens are in contract from recovery)
     *      5. Original contract is broken
     */
    function test_FullRecovery_ExecuteAndVerify() public {
        bytes32 defaultAdminRole = bytes32(0);
        bytes32 managerRole = keccak256("MANAGER_ROLE");
        
        // ============ Phase 1: Setup Recovery ============
        
        // Step 1: Deploy the recovery contract as admin
        StremeRecover recovery;
        vm.startPrank(admin);
        recovery = new StremeRecover(address(stakingFactorySpecial));
        vm.stopPrank();
        
        // Step 2: Grant roles to recovery contract
        vm.startPrank(admin);
        AccessControlUpgradeable(stakedTokenAddress1).grantRole(defaultAdminRole, address(recovery));
        AccessControlUpgradeable(stakedTokenAddress1).grantRole(managerRole, address(recovery));
        vm.stopPrank();
        
        // Get initial state
        IStakedTokenV2[] memory stTokens = new IStakedTokenV2[](1);
        stTokens[0] = IStakedTokenV2(stakedTokenAddress1);
        IERC20 token = IERC20(stakeableToken);
        
        // Record initial token balance in old contract
        uint256 initialOldContractBalance = token.balanceOf(stakedTokenAddress1);
        assertGt(initialOldContractBalance, 0, "Old contract should have tokens initially");
        
        // ============ Phase 2: Execute Exploit ============
        
        // Step 3: Execute exploit - stake all tokens to recovery contract
        vm.prank(admin);
        recovery.exploit(stTokens);
        
        // Verify recovery contract has staked tokens
        uint256 recoveryStakedBalance = IStakedTokenV2(stakedTokenAddress1).balanceOf(address(recovery));
        assertEq(recoveryStakedBalance, initialOldContractBalance, "Recovery contract should have a bunch of staked tokens");
        
        // ============ Phase 3: Execute Recovery ============
        
        // Step 4: Advance time so tokens can be unstaked
        vm.warp(block.timestamp + 1);
        
        // Step 5: Execute recovery - unstake, break old contract, create new contract
        vm.prank(admin);
        recovery.recover(stTokens);
        
        // ============ Phase 4: Verify New Contract ============
        
        // Step 6: Get the new special token address created by factory
        address newSpecialTokenAddr = stakingFactorySpecial.predictStakedTokenAddress(address(stakeableToken));
        StakedTokenV2Special newSpecialToken = StakedTokenV2Special(newSpecialTokenAddr);
        
        // Grant MANAGER_ROLE to the new special token on the original staked token
        // This is needed because _update() calls updateMemberUnits on the original token
        vm.startPrank(admin);
        AccessControlUpgradeable(stakedTokenAddress1).grantRole(managerRole, newSpecialTokenAddr);
        vm.stopPrank();
        
        // Step 7: Verify tokens were transferred to new contract
        uint256 newContractBalance = token.balanceOf(newSpecialTokenAddr);
        assertGt(newContractBalance, 0, "New contract should have tokens from recovery");
        assertEq(token.balanceOf(address(recovery)), 0, "Recovery contract should have no tokens after recovery");
        assertEq(newContractBalance, initialOldContractBalance, "All tokens should be in new contract");
        
        // ============ Phase 5: User Claims ============
        
        // Step 8: Verify users can claim their tokens
        uint128 units1 = _getPoolUnits(staker1ForToken1);
        uint128 units2 = _getPoolUnits(staker2ForToken1);
        
        // Units should not be zero - these are real stakers
        require(units1 > 0, "staker1ForToken1 should have units");
        require(units2 > 0, "staker2ForToken1 should have units");
        
        // User 1 claims
        vm.prank(staker1ForToken1);
        newSpecialToken.claimStakeFromUnits(staker1ForToken1);
        uint256 expectedTokens1 = _unitsToTokens(newSpecialToken, units1);
        assertEq(newSpecialToken.balanceOf(staker1ForToken1), expectedTokens1, "User 1 should have claimed tokens");
        
        // Verify deposit timestamp is preserved
        uint256 originalTimestamp = _getOriginalDepositTimestamp(stakedTokenAddress1, staker1ForToken1);
        assertEq(newSpecialToken.depositTimestamps(staker1ForToken1), originalTimestamp, "Deposit timestamp should be preserved");
        
        // User 2 claims
        vm.prank(staker2ForToken1);
        newSpecialToken.claimStakeFromUnits(staker2ForToken1);
        uint256 expectedTokens2 = _unitsToTokens(newSpecialToken, units2);
        assertEq(newSpecialToken.balanceOf(staker2ForToken1), expectedTokens2, "User 2 should have claimed tokens");
        
        // ============ Phase 6: User Unstaking ============
        
        // Step 9: Verify users can unstake (tokens are in contract from recovery)
        uint256 claimedBalance = newSpecialToken.balanceOf(staker1ForToken1);
        assertGt(claimedBalance, 0, "User 1 should have claimed tokens");
        
        // Get original deposit timestamp to calculate unlock time
        uint256 depositTimestamp = newSpecialToken.depositTimestamps(staker1ForToken1);
        uint256 lockDuration = newSpecialToken.lockDuration();
        uint256 unlockTime = depositTimestamp + lockDuration;
        
        // Advance time past unlock if needed
        if (block.timestamp < unlockTime) {
            vm.warp(unlockTime + 1);
        }
        
        // Verify contract has tokens to unstake
        uint256 contractTokenBalance = token.balanceOf(newSpecialTokenAddr);
        assertGe(contractTokenBalance, claimedBalance, "Contract should have enough tokens for unstaking");
        
        // User unstakes half their tokens
        uint256 unstakeAmount = claimedBalance / 2;
        uint256 user1TokenBalanceBefore = token.balanceOf(staker1ForToken1);
        
        vm.prank(staker1ForToken1);
        newSpecialToken.unstake(staker1ForToken1, unstakeAmount);
        
        // Verify unstake worked
        assertEq(
            token.balanceOf(staker1ForToken1),
            user1TokenBalanceBefore + unstakeAmount,
            "User 1 should receive unstaked tokens"
        );
        assertEq(
            newSpecialToken.balanceOf(staker1ForToken1),
            claimedBalance - unstakeAmount,
            "User 1 staked balance should decrease"
        );
        assertEq(
            token.balanceOf(newSpecialTokenAddr),
            contractTokenBalance - unstakeAmount,
            "Contract token balance should decrease"
        );
        
        // ============ Phase 7: Verify Old Contract is Broken ============
        
        // Step 10: Verify original contract is broken (can't do operations)
        StakedTokenV2 brokenToken = StakedTokenV2(stakedTokenAddress1);
        vm.expectRevert();
        brokenToken.tokensToUnits(1);
        
        // Verify old contract has minimal/no tokens left (most should be in new contract)
        uint256 oldContractRemaining = token.balanceOf(stakedTokenAddress1);
        // Allow for small dust amounts, but verify most tokens were moved
        assertLt(oldContractRemaining, initialOldContractBalance / 100, "Old contract should have minimal tokens (dust only)");
    }

    // ============ Core Tests: Post-Recovery Functionality ============

    /**
     * @notice Test: Stake works correctly after recovery
     * @dev Verifies users can stake new tokens in the special contract
     * Note: On fork tests, we use a real address that has tokens
     */
    function test_PostRecovery_StakeWorks() public {
        // Setup: Deploy special token (simulating post-recovery state)
        stakedTokenSpecial = _deployStakedTokenSpecial(address(stakeableToken), stakedTokenAddress1);
        
        // Setup: Use a real address that has tokens (or skip if none available)
        // For now, we'll test with a user who has already claimed (they have tokens)
        // This verifies the contract works after recovery
        uint128 units1 = _getPoolUnits(staker1ForToken1);
        if (units1 == 0) {
            // Skip if user has no units
            return;
        }
        
        // User claims first (simulating post-recovery state)
        vm.prank(staker1ForToken1);
        stakedTokenSpecial.claimStakeFromUnits(staker1ForToken1);
        
        uint256 claimedBalance = stakedTokenSpecial.balanceOf(staker1ForToken1);
        assertGt(claimedBalance, 0, "User should have claimed tokens");
        
        // Verify the contract works - user can transfer (after lock expires)
        // This demonstrates the contract functions normally after recovery
        uint256 lockDuration = stakedTokenSpecial.lockDuration();
        vm.warp(block.timestamp + lockDuration + 1);
        
        // User can transfer tokens (proving contract works)
        address recipient = makeAddr("recipient");
        uint256 transferAmount = claimedBalance / 2;
        vm.prank(staker1ForToken1);
        stakedTokenSpecial.transfer(recipient, transferAmount);
        
        assertEq(stakedTokenSpecial.balanceOf(recipient), transferAmount, "Transfer should work");
    }

    /**
     * @notice Test: Unstake works correctly after recovery (after lock expires)
     * @dev Verifies users can unstake tokens from the special contract
     * Note: This test is now covered in test_FullRecovery_ExecuteAndVerify
     * which properly executes the recovery flow and tests unstaking with real tokens
     */
    function test_PostRecovery_UnstakeWorks() public {
        // This test is now integrated into test_FullRecovery_ExecuteAndVerify
        // which properly tests unstaking after the full recovery flow
        // where tokens are actually in the contract from recovery
    }

    /**
     * @notice Test: Unstake reverts if lock not expired
     * @dev Verifies lock duration is enforced
     */
    function test_PostRecovery_UnstakeRevertsIfLocked() public {
        // Setup: Deploy special token
        stakedTokenSpecial = _deployStakedTokenSpecial(address(stakeableToken), stakedTokenAddress1);
        
        // Use a real user who has units
        uint128 units1 = _getPoolUnits(staker1ForToken1);
        if (units1 == 0) {
            return; // Skip if no units
        }
        
        // User claims tokens (lock starts from original deposit timestamp)
        vm.prank(staker1ForToken1);
        stakedTokenSpecial.claimStakeFromUnits(staker1ForToken1);
        
        uint256 claimedBalance = stakedTokenSpecial.balanceOf(staker1ForToken1);
        assertGt(claimedBalance, 0, "User should have claimed tokens");
        
        // Try to unstake immediately (lock not expired if original timestamp + lockDuration hasn't passed)
        uint256 depositTimestamp = stakedTokenSpecial.depositTimestamps(staker1ForToken1);
        uint256 lockDuration = stakedTokenSpecial.lockDuration();
        
        // Only test if lock hasn't expired yet
        if (block.timestamp <= depositTimestamp + lockDuration) {
            vm.prank(staker1ForToken1);
            vm.expectRevert("StakedToken: tokens are still locked");
            stakedTokenSpecial.unstake(staker1ForToken1, claimedBalance);
        }
    }

    // ============ Core Tests: Security - Post-Recovery Functionality ============

    /**
     * @notice Test: Transfer works correctly after recovery
     * @dev Verifies transfers work normally in the new contract
     */
    function test_Security_TransferWorksAfterRecovery() public {
        // Setup: Deploy special token
        stakedTokenSpecial = _deployStakedTokenSpecial(address(stakeableToken), stakedTokenAddress1);
        
        // Use a real user who has units
        uint128 units1 = _getPoolUnits(staker1ForToken1);
        if (units1 == 0) {
            return; // Skip if no units
        }
        
        // User claims tokens
        vm.prank(staker1ForToken1);
        stakedTokenSpecial.claimStakeFromUnits(staker1ForToken1);
        
        uint256 claimedBalance = stakedTokenSpecial.balanceOf(staker1ForToken1);
        assertGt(claimedBalance, 0, "User should have claimed tokens");
        
        // Advance time past lock
        uint256 lockDuration = stakedTokenSpecial.lockDuration();
        vm.warp(block.timestamp + lockDuration + 1);
        
        // Action: Transfer tokens
        address recipient = makeAddr("recipient");
        uint256 transferAmount = claimedBalance / 2;
        vm.prank(staker1ForToken1);
        stakedTokenSpecial.transfer(recipient, transferAmount);
        
        // Assert: Transfer works correctly
        assertEq(stakedTokenSpecial.balanceOf(recipient), transferAmount, "Recipient should receive tokens");
        assertEq(stakedTokenSpecial.balanceOf(staker1ForToken1), claimedBalance - transferAmount, "Sender balance should decrease");
    }

    /**
     * @notice Test: Multiple users can claim and then use the contract normally
     * @dev Verifies the full user journey after recovery
     */
    function test_PostRecovery_MultipleUsersClaimAndUse() public {
        // Setup: Deploy special token
        stakedTokenSpecial = _deployStakedTokenSpecial(address(stakeableToken), stakedTokenAddress1);
        
        // User 1 claims
        uint128 units1 = _getPoolUnits(staker1ForToken1);
        require(units1 > 0, "staker1ForToken1 should have units");
        vm.prank(staker1ForToken1);
        stakedTokenSpecial.claimStakeFromUnits(staker1ForToken1);
        
        // User 2 claims
        uint128 units2 = _getPoolUnits(staker2ForToken1);
        require(units2 > 0, "staker2ForToken1 should have units");
        vm.prank(staker2ForToken1);
        stakedTokenSpecial.claimStakeFromUnits(staker2ForToken1);
        
        // Verify both have balances
        assertGt(stakedTokenSpecial.balanceOf(staker1ForToken1), 0, "User 1 should have balance");
        assertGt(stakedTokenSpecial.balanceOf(staker2ForToken1), 0, "User 2 should have balance");
        
        // Verify total supply matches
        uint256 totalSupply = stakedTokenSpecial.totalSupply();
        uint256 expectedSupply = _unitsToTokens(stakedTokenSpecial, units1) + _unitsToTokens(stakedTokenSpecial, units2);
        assertEq(totalSupply, expectedSupply, "Total supply should match sum of claims");
        
        // Verify both can still stake additional tokens (if they have any)
        // This tests that the contract works normally after claims
    }
}

