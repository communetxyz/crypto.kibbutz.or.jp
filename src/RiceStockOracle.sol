// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RiceStockOracle
 * @dev Rice stock tracking oracle
 * 
 * Tracks available rice stock in kg. Used by RiceReserve for
 * redemption eligibility and swap ratio calculations.
 */
contract RiceStockOracle is Ownable {
    // Rice stock data
    uint256 public availableKg;
    uint64 public lastUpdate;
    
    // Configuration
    uint64 public staleAfter;
    uint64 public constant DEFAULT_STALE_AFTER = 24 hours;
    
    // Authorized updaters
    mapping(address => bool) public authorizedUpdaters;
    
    // Events
    event StockUpdated(uint256 availableKg, uint64 timestamp);
    event UpdaterAuthorized(address indexed updater, bool authorized);
    event StaleAfterUpdated(uint64 staleAfter);
    
    // Errors
    error UnauthorizedUpdater();
    error InvalidStock();
    error StaleData();

    constructor(uint64 _staleAfter) {
        staleAfter = _staleAfter > 0 ? _staleAfter : DEFAULT_STALE_AFTER;
    }

    /**
     * @dev Update rice stock
     * @param _availableKg Available rice stock in kg
     */
    function updateStock(uint256 _availableKg) external {
        if (!authorizedUpdaters[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedUpdater();
        }
        
        // Validate stock amount (reasonable range: 0 to 1,000,000 kg)
        if (_availableKg > 1_000_000) {
            revert InvalidStock();
        }
        
        availableKg = _availableKg;
        lastUpdate = uint64(block.timestamp);
        
        emit StockUpdated(_availableKg, lastUpdate);
    }

    /**
     * @dev Get available rice stock (used by RiceReserve)
     * @return Available rice stock in kg
     */
    function getAvailableKg() external view returns (uint256) {
        require(block.timestamp <= lastUpdate + staleAfter, "RiceStockOracle: data is stale");
        return availableKg;
    }

    /**
     * @dev Get rice harvest (used by MaicaToken for emission)
     * @return Rice harvest in kg (same as available stock for simplicity)
     */
    function getHarvest() external view returns (uint256) {
        require(block.timestamp <= lastUpdate + staleAfter, "RiceStockOracle: data is stale");
        return availableKg;
    }

    /**
     * @dev Check if stock data is stale
     * @return True if data is stale
     */
    function isStale() external view returns (bool) {
        return block.timestamp > lastUpdate + staleAfter;
    }

    /**
     * @dev Authorize/deauthorize stock updaters
     */
    function setUpdaterAuthorization(address updater, bool authorized) external onlyOwner {
        authorizedUpdaters[updater] = authorized;
        emit UpdaterAuthorized(updater, authorized);
    }

    /**
     * @dev Update stale after period
     */
    function setStaleAfter(uint64 _staleAfter) external onlyOwner {
        require(_staleAfter > 0, "RiceStockOracle: stale after must be positive");
        staleAfter = _staleAfter;
        emit StaleAfterUpdated(_staleAfter);
    }

    /**
     * @dev Get stock with staleness check
     * @return stock Available rice stock in kg
     * @return isStaleData True if data is stale
     */
    function getStockWithStaleness() external view returns (uint256 stock, bool isStaleData) {
        stock = availableKg;
        isStaleData = block.timestamp > lastUpdate + staleAfter;
    }

    /**
     * @dev Emergency function to update stock (only owner, for testing)
     */
    function emergencyUpdateStock(uint256 _availableKg) external onlyOwner {
        availableKg = _availableKg;
        lastUpdate = uint64(block.timestamp);
        emit StockUpdated(_availableKg, lastUpdate);
    }
} 