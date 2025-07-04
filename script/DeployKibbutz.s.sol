// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/MaicaToken.sol";
import "../src/RicePriceOracle.sol";
import "../src/CrisisOracle.sol";
import "../src/ServiceOracle.sol";
import "../src/RiceStockOracle.sol";
import "../src/MemberRegistry.sol";
import "../src/RiceReserve.sol";
import "../src/BasicIncome.sol";

/**
 * @title DeployKibbutz
 * @dev Deployment script for the complete kibbutz crypto-economic system
 */
contract DeployKibbutz is Script {
    // Contract addresses
    address public maicaToken;
    address public ricePriceOracle;
    address public crisisOracle;
    address public serviceOracle;
    address public riceStockOracle;
    address public memberRegistry;
    address public riceReserve;
    address public basicIncome;

    // Emission parameters (α, β)
    uint256 public constant ALPHA = 100; // Service capacity coefficient
    uint256 public constant BETA = 50;   // Rice harvest coefficient

    // Swap ratio parameters (γ, δ)
    uint256 public constant GAMMA = 1e18; // Stock/supply ratio coefficient
    uint256 public constant DELTA = 1e18; // Price ratio coefficient

    // Baseline rice price (¥/kg)
    uint128 public constant BASELINE_PRICE = 500; // 500 yen per kg

    // Oracle configuration
    uint64 public constant PRICE_STALE_AFTER = 48 hours;
    uint64 public constant CRISIS_STALE_AFTER = 24 hours;
    uint64 public constant SERVICE_STALE_AFTER = 7 days;
    uint64 public constant STOCK_STALE_AFTER = 24 hours;
    uint8 public constant CRISIS_THRESHOLD = 2; // 2 out of 3 nodes

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying Kibbutz Crypto-Economic System...");
        console.log("Deployer:", deployer);

        // 1. Deploy oracles first
        console.log("\n1. Deploying oracles...");
        
        ricePriceOracle = address(new RicePriceOracle(PRICE_STALE_AFTER));
        console.log("RicePriceOracle deployed at:", ricePriceOracle);

        crisisOracle = address(new CrisisOracle(CRISIS_STALE_AFTER, CRISIS_THRESHOLD));
        console.log("CrisisOracle deployed at:", crisisOracle);

        serviceOracle = address(new ServiceOracle(SERVICE_STALE_AFTER));
        console.log("ServiceOracle deployed at:", serviceOracle);

        riceStockOracle = address(new RiceStockOracle(STOCK_STALE_AFTER));
        console.log("RiceStockOracle deployed at:", riceStockOracle);

        memberRegistry = address(new MemberRegistry());
        console.log("MemberRegistry deployed at:", memberRegistry);

        // 2. Deploy core contracts
        console.log("\n2. Deploying core contracts...");

        maicaToken = address(new MaicaToken(
            "Maica",
            "MAICA",
            ALPHA,
            BETA,
            serviceOracle,
            riceStockOracle
        ));
        console.log("MaicaToken deployed at:", maicaToken);

        riceReserve = address(new RiceReserve(
            GAMMA,
            DELTA,
            BASELINE_PRICE,
            maicaToken,
            riceStockOracle,
            ricePriceOracle,
            crisisOracle
        ));
        console.log("RiceReserve deployed at:", riceReserve);

        basicIncome = address(new BasicIncome(
            memberRegistry,
            riceReserve
        ));
        console.log("BasicIncome deployed at:", basicIncome);

        // 3. Configure permissions and initial state
        console.log("\n3. Configuring permissions and initial state...");

        // Transfer MaicaToken ownership to RiceReserve
        MaicaToken(maicaToken).transferOwnership(riceReserve);
        console.log("MaicaToken ownership transferred to RiceReserve");

        // Transfer RiceReserve ownership to BasicIncome
        RiceReserve(riceReserve).transferOwnership(basicIncome);
        console.log("RiceReserve ownership transferred to BasicIncome");

        // Add deployer as authorized node for price oracle
        RicePriceOracle(ricePriceOracle).setNodeAuthorization(deployer, true);
        console.log("Deployer authorized as price oracle node");

        // Add deployer as authorized node for crisis oracle
        CrisisOracle(crisisOracle).setNodeAuthorization(deployer, true);
        console.log("Deployer authorized as crisis oracle node");

        // Add deployer as authorized updater for service oracle
        ServiceOracle(serviceOracle).setUpdaterAuthorization(deployer, true);
        console.log("Deployer authorized as service oracle updater");

        // Add deployer as authorized updater for rice stock oracle
        RiceStockOracle(riceStockOracle).setUpdaterAuthorization(deployer, true);
        console.log("Deployer authorized as rice stock oracle updater");

        // Set initial data
        ServiceOracle(serviceOracle).updateCapacity(50, 100, 1000); // 50 beds, 100 seats, 1000 sqm
        console.log("Initial service capacity set");

        RiceStockOracle(riceStockOracle).updateStock(50000); // 50,000 kg initial stock
        console.log("Initial rice stock set");

        RicePriceOracle(ricePriceOracle).emergencyUpdatePrice(BASELINE_PRICE);
        console.log("Initial rice price set");

        CrisisOracle(crisisOracle).emergencyUpdateCrisis(false);
        console.log("Initial crisis status set (false)");

        // Add some initial members
        address[] memory initialMembers = new address[](3);
        initialMembers[0] = deployer;
        initialMembers[1] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Test address 1
        initialMembers[2] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Test address 2

        bool[] memory statuses = new bool[](3);
        statuses[0] = true;
        statuses[1] = true;
        statuses[2] = true;

        MemberRegistry(memberRegistry).bulkUpdateMembers(initialMembers, statuses);
        console.log("Initial members added");

        vm.stopBroadcast();

        // 4. Print deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("MaicaToken:", maicaToken);
        console.log("RicePriceOracle:", ricePriceOracle);
        console.log("CrisisOracle:", crisisOracle);
        console.log("ServiceOracle:", serviceOracle);
        console.log("RiceStockOracle:", riceStockOracle);
        console.log("MemberRegistry:", memberRegistry);
        console.log("RiceReserve:", riceReserve);
        console.log("BasicIncome:", basicIncome);
        console.log("\nParameters:");
        console.log("Alpha (service capacity coefficient):", ALPHA);
        console.log("Beta (rice harvest coefficient):", BETA);
        console.log("Gamma (stock/supply ratio coefficient):", GAMMA);
        console.log("Delta (price ratio coefficient):", DELTA);
        console.log("Baseline rice price:", BASELINE_PRICE, "yen/kg");
        console.log("Minimum rice stock for redemption:", 30000, "kg");
        console.log("Basic income per year:", 60, "kg");
        console.log("\nDeployment completed successfully!");
    }
} 