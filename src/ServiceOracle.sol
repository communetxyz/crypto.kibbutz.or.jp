// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ServiceOracle
 * @dev Service capacity tracking oracle
 * 
 * Tracks service capacity including:
 * - Beds (accommodation capacity)
 * - Seats (dining/meeting capacity)
 * - Rentable square meters (space capacity)
 * 
 * Used by MaicaToken for emission calculations.
 */
contract ServiceOracle is Ownable {
    // Service capacity data
    uint256 public beds;
    uint256 public seats;
    uint256 public rentableSqm;
    uint64 public lastUpdate;
    
    // Configuration
    uint64 public staleAfter;
    uint64 public constant DEFAULT_STALE_AFTER = 7 days;
    
    // Authorized updaters
    mapping(address => bool) public authorizedUpdaters;
    
    // Events
    event CapacityUpdated(uint256 beds, uint256 seats, uint256 rentableSqm, uint64 timestamp);
    event UpdaterAuthorized(address indexed updater, bool authorized);
    event StaleAfterUpdated(uint64 staleAfter);
    
    // Errors
    error UnauthorizedUpdater();
    error InvalidCapacity();
    error StaleData();

    constructor(uint64 _staleAfter) {
        staleAfter = _staleAfter > 0 ? _staleAfter : DEFAULT_STALE_AFTER;
    }

    /**
     * @dev Update service capacity
     * @param _beds Number of beds
     * @param _seats Number of seats
     * @param _rentableSqm Rentable square meters
     */
    function updateCapacity(
        uint256 _beds,
        uint256 _seats,
        uint256 _rentableSqm
    ) external {
        if (!authorizedUpdaters[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedUpdater();
        }
        
        // Validate capacity values (reasonable ranges)
        if (_beds > 10000 || _seats > 10000 || _rentableSqm > 1000000) {
            revert InvalidCapacity();
        }
        
        beds = _beds;
        seats = _seats;
        rentableSqm = _rentableSqm;
        lastUpdate = uint64(block.timestamp);
        
        emit CapacityUpdated(_beds, _seats, _rentableSqm, lastUpdate);
    }

    /**
     * @dev Get total service capacity (used by MaicaToken)
     * @return Total capacity (beds + seats + rentableSqm)
     */
    function getCapacity() external view returns (uint256) {
        require(block.timestamp <= lastUpdate + staleAfter, "ServiceOracle: data is stale");
        return beds + seats + rentableSqm;
    }

    /**
     * @dev Get detailed capacity breakdown
     * @return _beds Number of beds
     * @return _seats Number of seats
     * @return _rentableSqm Rentable square meters
     * @return total Total capacity
     */
    function getCapacityBreakdown() external view returns (
        uint256 _beds,
        uint256 _seats,
        uint256 _rentableSqm,
        uint256 total
    ) {
        require(block.timestamp <= lastUpdate + staleAfter, "ServiceOracle: data is stale");
        _beds = beds;
        _seats = seats;
        _rentableSqm = rentableSqm;
        total = beds + seats + rentableSqm;
    }

    /**
     * @dev Check if capacity data is stale
     * @return True if data is stale
     */
    function isStale() external view returns (bool) {
        return block.timestamp > lastUpdate + staleAfter;
    }

    /**
     * @dev Authorize/deauthorize capacity updaters
     */
    function setUpdaterAuthorization(address updater, bool authorized) external onlyOwner {
        authorizedUpdaters[updater] = authorized;
        emit UpdaterAuthorized(updater, authorized);
    }

    /**
     * @dev Update stale after period
     */
    function setStaleAfter(uint64 _staleAfter) external onlyOwner {
        require(_staleAfter > 0, "ServiceOracle: stale after must be positive");
        staleAfter = _staleAfter;
        emit StaleAfterUpdated(_staleAfter);
    }

    /**
     * @dev Get capacity with staleness check
     * @return capacity Total capacity
     * @return isStaleData True if data is stale
     */
    function getCapacityWithStaleness() external view returns (uint256 capacity, bool isStaleData) {
        capacity = beds + seats + rentableSqm;
        isStaleData = block.timestamp > lastUpdate + staleAfter;
    }

    /**
     * @dev Emergency function to update capacity (only owner, for testing)
     */
    function emergencyUpdateCapacity(
        uint256 _beds,
        uint256 _seats,
        uint256 _rentableSqm
    ) external onlyOwner {
        beds = _beds;
        seats = _seats;
        rentableSqm = _rentableSqm;
        lastUpdate = uint64(block.timestamp);
        emit CapacityUpdated(_beds, _seats, _rentableSqm, lastUpdate);
    }
} 