// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RicePriceOracle
 * @dev MPC/TLS-based rice price oracle that receives signed price data
 * 
 * A federation of MPC nodes fetches retail rice price data from multiple
 * consumer-price websites over TLS, computes the median, signs a TLS-notary
 * proof, and pushes it on-chain.
 */
contract RicePriceOracle is Ownable {
    // Price data
    uint128 public priceYenPerKg;
    bytes32 public lastProof;
    uint64 public lastUpdate;
    
    // Configuration
    uint64 public staleAfter;
    uint64 public constant DEFAULT_STALE_AFTER = 48 hours;
    
    // Authorized MPC nodes
    mapping(address => bool) public authorizedNodes;
    
    // Events
    event PriceUpdated(uint128 price, bytes32 proof, uint64 timestamp);
    event NodeAuthorized(address indexed node, bool authorized);
    event StaleAfterUpdated(uint64 staleAfter);
    
    // Errors
    error InvalidProof();
    error StaleData();
    error UnauthorizedNode();
    error InvalidPrice();

    constructor(uint64 _staleAfter) {
        staleAfter = _staleAfter > 0 ? _staleAfter : DEFAULT_STALE_AFTER;
    }

    /**
     * @dev Submit new price data with TLS proof
     * @param price Price in yen per kg (must be reasonable range)
     * @param proof TLS notary proof from MPC nodes
     */
    function submitPrice(uint128 price, bytes32 proof) external {
        if (!authorizedNodes[msg.sender]) {
            revert UnauthorizedNode();
        }
        
        if (price == 0 || price > 10000) { // Reasonable price range: 1-10,000 yen/kg
            revert InvalidPrice();
        }
        
        // Verify proof (in production, this would verify the TLS notary proof)
        if (!_verifyProof(proof, price)) {
            revert InvalidProof();
        }
        
        // Check if data is stale
        if (block.timestamp > lastUpdate + staleAfter) {
            revert StaleData();
        }
        
        priceYenPerKg = price;
        lastProof = proof;
        lastUpdate = uint64(block.timestamp);
        
        emit PriceUpdated(price, proof, lastUpdate);
    }

    /**
     * @dev Get current price
     * @return Current price in yen per kg
     */
    function getPrice() external view returns (uint128) {
        require(priceYenPerKg > 0, "RicePriceOracle: no price data");
        require(block.timestamp <= lastUpdate + staleAfter, "RicePriceOracle: price is stale");
        return priceYenPerKg;
    }

    /**
     * @dev Check if price data is stale
     * @return True if price data is stale
     */
    function isStale() external view returns (bool) {
        return block.timestamp > lastUpdate + staleAfter;
    }

    /**
     * @dev Authorize/deauthorize MPC nodes
     */
    function setNodeAuthorization(address node, bool authorized) external onlyOwner {
        authorizedNodes[node] = authorized;
        emit NodeAuthorized(node, authorized);
    }

    /**
     * @dev Update stale after period
     */
    function setStaleAfter(uint64 _staleAfter) external onlyOwner {
        require(_staleAfter > 0, "RicePriceOracle: stale after must be positive");
        staleAfter = _staleAfter;
        emit StaleAfterUpdated(_staleAfter);
    }

    /**
     * @dev Verify TLS notary proof (placeholder implementation)
     * In production, this would verify the actual TLS notary proof
     */
    function _verifyProof(bytes32 proof, uint128 price) internal pure returns (bool) {
        // Placeholder: in production, this would verify the TLS notary proof
        // For now, we'll accept any non-zero proof
        return proof != bytes32(0);
    }

    /**
     * @dev Emergency function to update price (only owner, for testing)
     */
    function emergencyUpdatePrice(uint128 price) external onlyOwner {
        require(price > 0 && price <= 10000, "RicePriceOracle: invalid price");
        priceYenPerKg = price;
        lastUpdate = uint64(block.timestamp);
        emit PriceUpdated(price, bytes32(0), lastUpdate);
    }
} 