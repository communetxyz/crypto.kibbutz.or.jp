// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/MaicaToken.sol";
import "../src/RicePriceOracle.sol";
import "../src/CrisisOracle.sol";
import "../src/ServiceOracle.sol";
import "../src/RiceStockOracle.sol";
import "../src/MemberRegistry.sol";
import "../src/RiceReserve.sol";
import "../src/BasicIncome.sol";

/**
 * @title KibbutzSystemTest
 * @dev Comprehensive tests for the kibbutz crypto-economic system
 */
contract KibbutzSystemTest is Test {
    // Test addresses
    address public deployer = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public merchant = address(0x4);
    address public mpcNode = address(0x5);

    // Contract instances
    MaicaToken public maicaToken;
    RicePriceOracle public ricePriceOracle;
    CrisisOracle public crisisOracle;
    ServiceOracle public serviceOracle;
    RiceStockOracle public riceStockOracle;
    MemberRegistry public memberRegistry;
    RiceReserve public riceReserve;
    BasicIncome public basicIncome;

    // Parameters
    uint256 public constant ALPHA = 100;
    uint256 public constant BETA = 50;
    uint256 public constant GAMMA = 1e18;
    uint256 public constant DELTA = 1e18;
    uint128 public constant BASELINE_PRICE = 500;
    uint64 public constant STALE_AFTER = 48 hours;

    function setUp() public {
        // Deploy oracles
        ricePriceOracle = new RicePriceOracle(STALE_AFTER);
        crisisOracle = new CrisisOracle(STALE_AFTER, 2);
        serviceOracle = new ServiceOracle(STALE_AFTER);
        riceStockOracle = new RiceStockOracle(STALE_AFTER);
        memberRegistry = new MemberRegistry();

        // Deploy core contracts
        maicaToken = new MaicaToken(
            "Maica",
            "MAICA",
            ALPHA,
            BETA,
            address(serviceOracle),
            address(riceStockOracle)
        );

        riceReserve = new RiceReserve(
            GAMMA,
            DELTA,
            BASELINE_PRICE,
            address(maicaToken),
            address(riceStockOracle),
            address(ricePriceOracle),
            address(crisisOracle)
        );

        basicIncome = new BasicIncome(
            address(memberRegistry),
            address(riceReserve)
        );

        // Configure permissions
        maicaToken.transferOwnership(address(riceReserve));
        riceReserve.transferOwnership(address(basicIncome));

        // Authorize test addresses
        ricePriceOracle.setNodeAuthorization(mpcNode, true);
        crisisOracle.setNodeAuthorization(mpcNode, true);
        serviceOracle.setUpdaterAuthorization(deployer, true);
        riceStockOracle.setUpdaterAuthorization(deployer, true);

        // Set initial data
        serviceOracle.updateCapacity(50, 100, 1000);
        riceStockOracle.updateStock(50000);
        ricePriceOracle.emergencyUpdatePrice(BASELINE_PRICE);
        crisisOracle.emergencyUpdateCrisis(false);

        // Add test members
        address[] memory members = new address[](3);
        members[0] = alice;
        members[1] = bob;
        members[2] = charlie;

        bool[] memory statuses = new bool[](3);
        statuses[0] = true;
        statuses[1] = true;
        statuses[2] = true;

        memberRegistry.bulkUpdateMembers(members, statuses);

        // Add merchant to allowlist
        maicaToken.proposeAllowChange(
            merchant,
            true,
            _signAllowChange(merchant, true, 0, deployer),
            _signAllowChange(merchant, true, 0, alice)
        );
    }

    // ========== MAICA TOKEN TESTS ==========

    function testMaicaTokenInitialization() public {
        assertEq(maicaToken.name(), "Maica");
        assertEq(maicaToken.symbol(), "MAICA");
        assertEq(maicaToken.alpha(), ALPHA);
        assertEq(maicaToken.beta(), BETA);
        assertEq(maicaToken.serviceOracle(), address(serviceOracle));
        assertEq(maicaToken.riceStockOracle(), address(riceStockOracle));
        assertTrue(maicaToken.allowList(deployer));
    }

    function testMaicaTokenTransferRestrictions() public {
        // Mint some tokens to alice
        maicaToken.mintToReserve(1000e18);
        maicaToken.transfer(alice, 1000e18);

        // Should fail when sending to non-allowlisted address
        vm.expectRevert("MaicaToken: recipient not in allowlist");
        maicaToken.transfer(bob, 100e18);

        // Should succeed when sending to allowlisted address
        maicaToken.transfer(merchant, 100e18);
        assertEq(maicaToken.balanceOf(merchant), 100e18);
    }

    function testMaicaTokenEmission() public {
        uint256 initialSupply = maicaToken.totalSupply();
        
        // Increase service capacity
        serviceOracle.updateCapacity(100, 200, 2000); // Doubled capacity
        
        // Increase rice harvest
        riceStockOracle.updateStock(100000); // Doubled stock
        
        // Execute emission
        maicaToken.executeEmission();
        
        uint256 newSupply = maicaToken.totalSupply();
        assertGt(newSupply, initialSupply, "Emission should increase supply");
    }

    function testMaicaTokenAllowlistManagement() public {
        address newMerchant = address(0x6);
        
        // Add new merchant with signatures
        maicaToken.proposeAllowChange(
            newMerchant,
            true,
            _signAllowChange(newMerchant, true, 0, deployer),
            _signAllowChange(newMerchant, true, 0, alice)
        );
        
        assertTrue(maicaToken.allowList(newMerchant));
        
        // Remove merchant
        maicaToken.proposeAllowChange(
            newMerchant,
            false,
            _signAllowChange(newMerchant, false, 1, deployer),
            _signAllowChange(newMerchant, false, 1, alice)
        );
        
        assertFalse(maicaToken.allowList(newMerchant));
    }

    // ========== RICE PRICE ORACLE TESTS ==========

    function testRicePriceOracle() public {
        vm.startPrank(mpcNode);
        
        // Submit new price
        ricePriceOracle.submitPrice(600, bytes32(uint256(1)));
        
        assertEq(ricePriceOracle.getPrice(), 600);
        assertFalse(ricePriceOracle.isStale());
        
        vm.stopPrank();
    }

    function testRicePriceOracleUnauthorized() public {
        vm.expectRevert();
        ricePriceOracle.submitPrice(600, bytes32(uint256(1)));
    }

    // ========== CRISIS ORACLE TESTS ==========

    function testCrisisOracle() public {
        vm.startPrank(mpcNode);
        
        // Submit crisis flag
        crisisOracle.submitFlag(true, bytes32(uint256(1)));
        
        assertTrue(crisisOracle.getCrisisStatus());
        assertFalse(crisisOracle.isStale());
        
        vm.stopPrank();
    }

    // ========== RICE RESERVE TESTS ==========

    function testRiceReserveRedemption() public {
        // Setup crisis and sufficient stock
        vm.prank(mpcNode);
        crisisOracle.submitFlag(true, bytes32(uint256(1)));
        
        // Mint Maica to alice
        maicaToken.mintToReserve(1000e18);
        maicaToken.transfer(alice, 1000e18);
        
        vm.startPrank(alice);
        
        // Redeem Maica for rice
        uint256 initialVoucher = riceReserve.getRiceVoucher(alice);
        maicaToken.approve(address(riceReserve), 100e18);
        riceReserve.redeem(100e18);
        
        uint256 finalVoucher = riceReserve.getRiceVoucher(alice);
        assertGt(finalVoucher, initialVoucher, "Rice voucher should increase");
        
        vm.stopPrank();
    }

    function testRiceReserveNoCrisis() public {
        // Ensure no crisis
        vm.prank(mpcNode);
        crisisOracle.submitFlag(false, bytes32(uint256(1)));
        
        // Mint Maica to alice
        maicaToken.mintToReserve(1000e18);
        maicaToken.transfer(alice, 1000e18);
        
        vm.startPrank(alice);
        maicaToken.approve(address(riceReserve), 100e18);
        
        vm.expectRevert();
        riceReserve.redeem(100e18);
        
        vm.stopPrank();
    }

    function testRiceReserveInsufficientStock() public {
        // Setup crisis
        vm.prank(mpcNode);
        crisisOracle.submitFlag(true, bytes32(uint256(1)));
        
        // Set low stock
        riceStockOracle.updateStock(20000); // Below 30,000 minimum
        
        // Mint Maica to alice
        maicaToken.mintToReserve(1000e18);
        maicaToken.transfer(alice, 1000e18);
        
        vm.startPrank(alice);
        maicaToken.approve(address(riceReserve), 100e18);
        
        vm.expectRevert();
        riceReserve.redeem(100e18);
        
        vm.stopPrank();
    }

    function testRiceReserveSwapRatio() public {
        uint256 ratio = riceReserve.calculateSwapRatio();
        assertGt(ratio, 0, "Swap ratio should be positive");
    }

    // ========== BASIC INCOME TESTS ==========

    function testBasicIncomeClaim() public {
        vm.startPrank(alice);
        
        uint256 initialVoucher = riceReserve.getRiceVoucher(alice);
        basicIncome.claim();
        
        uint256 finalVoucher = riceReserve.getRiceVoucher(alice);
        assertEq(finalVoucher - initialVoucher, 60, "Should receive 60 kg rice");
        
        vm.stopPrank();
    }

    function testBasicIncomeClaimTooEarly() public {
        vm.startPrank(alice);
        
        // First claim
        basicIncome.claim();
        
        // Try to claim again immediately - should revert
        vm.expectRevert();
        basicIncome.claim();
        
        vm.stopPrank();
    }

    function testBasicIncomeCumulativeClaim() public {
        vm.startPrank(alice);
        
        // First claim
        uint256 initialVoucher = riceReserve.getRiceVoucher(alice);
        basicIncome.claim();
        uint256 firstClaimVoucher = riceReserve.getRiceVoucher(alice);
        
        // Fast forward 6 months (182.5 days)
        vm.warp(block.timestamp + 182.5 days);
        
        // Second claim - should get additional amount
        basicIncome.claim();
        uint256 secondClaimVoucher = riceReserve.getRiceVoucher(alice);
        
        assertGt(secondClaimVoucher, firstClaimVoucher, "Should receive additional rice");
        
        vm.stopPrank();
    }

    function testBasicIncomeCalculateClaimableAmount() public {
        // New member should be able to claim immediately
        uint256 claimable = basicIncome.calculateClaimableAmount(alice);
        assertGt(claimable, 0, "New member should have claimable amount");
        
        // After claiming, should have 0 claimable amount
        vm.prank(alice);
        basicIncome.claim();
        
        claimable = basicIncome.calculateClaimableAmount(alice);
        assertEq(claimable, 0, "Should have 0 claimable amount after claiming");
        
        // After 6 months, should have additional claimable amount
        vm.warp(block.timestamp + 182.5 days);
        claimable = basicIncome.calculateClaimableAmount(alice);
        assertGt(claimable, 0, "Should have claimable amount after time");
    }

    function testBasicIncomeGetClaimSummary() public {
        (
            uint256 totalClaimed,
            uint256 totalAccumulated,
            uint256 claimableAmount
        ) = basicIncome.getClaimSummary(alice);
        
        assertEq(totalClaimed, 0, "New member should have 0 total claimed");
        assertGt(totalAccumulated, 0, "Should have accumulated amount");
        assertGt(claimableAmount, 0, "Should have claimable amount");
    }

    function testBasicIncomeNotMember() public {
        address nonMember = address(0x7);
        
        vm.startPrank(nonMember);
        vm.expectRevert();
        basicIncome.claim();
        vm.stopPrank();
    }

    function testBasicIncomeClaimInfo() public {
        (
            bool isMember,
            bool canClaimNow,
            uint256 claimableAmount,
            uint256 totalAccumulated,
            uint256 alreadyClaimed,
            uint256 membershipDuration,
            uint256 currentRate
        ) = basicIncome.getClaimInfo(alice);
        
        assertTrue(isMember);
        assertTrue(canClaimNow);
        assertGt(claimableAmount, 0, "Should have claimable amount");
        assertGt(totalAccumulated, 0, "Should have accumulated amount");
        assertEq(alreadyClaimed, 0, "Should have 0 already claimed for new member");
        assertGt(membershipDuration, 0, "Should have membership duration");
        assertEq(currentRate, 60, "Should have correct current rate");
    }

    // ========== INTEGRATION TESTS ==========

    function testCompleteSystemFlow() public {
        // 1. Setup crisis
        vm.prank(mpcNode);
        crisisOracle.submitFlag(true, bytes32(uint256(1)));
        
        // 2. Update oracles
        serviceOracle.updateCapacity(75, 150, 1500);
        riceStockOracle.updateStock(75000);
        vm.prank(mpcNode);
        ricePriceOracle.submitPrice(600, bytes32(uint256(1)));
        
        // 3. Execute Maica emission
        maicaToken.executeEmission();
        
        // 4. Distribute Maica to members
        maicaToken.mintToReserve(3000e18);
        maicaToken.transfer(alice, 1000e18);
        maicaToken.transfer(bob, 1000e18);
        maicaToken.transfer(charlie, 1000e18);
        
        // 5. Members claim basic income
        vm.prank(alice);
        basicIncome.claim();
        
        vm.prank(bob);
        basicIncome.claim();
        
        vm.prank(charlie);
        basicIncome.claim();
        
        // 6. Members redeem Maica for rice
        vm.startPrank(alice);
        maicaToken.approve(address(riceReserve), 500e18);
        riceReserve.redeem(500e18);
        vm.stopPrank();
        
        vm.startPrank(bob);
        maicaToken.approve(address(riceReserve), 300e18);
        riceReserve.redeem(300e18);
        vm.stopPrank();
        
        // 7. Verify final state
        assertGt(riceReserve.getRiceVoucher(alice), 60, "Alice should have basic income + redemption");
        assertGt(riceReserve.getRiceVoucher(bob), 60, "Bob should have basic income + redemption");
        assertEq(riceReserve.getRiceVoucher(charlie), 60, "Charlie should have only basic income");
    }

    // ========== HELPER FUNCTIONS ==========

    function _signAllowChange(
        address candidate,
        bool value,
        uint256 nonce,
        address signer
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                maicaToken.ALLOW_CHANGE_TYPEHASH(),
                candidate,
                value,
                nonce
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", maicaToken.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(signer)), hash);
        return abi.encodePacked(r, s, v);
    }
} 