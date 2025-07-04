// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CrisisOracle
 * @dev MPC/TLS-based crisis detection oracle
 * 
 * An MPC cluster fetches full-text articles from predefined reputable online
 * newspapers over TLS, runs a BERT-based crisis classifier, aggregates votes,
 * and pushes a boolean crisis flag plus TLS proof.
 */
contract CrisisOracle is Ownable {
    // Crisis state
    bool public crisis;
    bytes32 public classifierProof;
    uint64 public lastUpdate;
    
    // Configuration
    uint64 public staleAfter;
    uint64 public constant DEFAULT_STALE_AFTER = 24 hours;
    
    // Authorized MPC nodes
    mapping(address => bool) public authorizedNodes;
    
    // Crisis threshold (majority of classifiers must vote crisis)
    uint8 public crisisThreshold;
    uint8 public constant DEFAULT_CRISIS_THRESHOLD = 2; // 2 out of 3 nodes
    
    // Events
    event CrisisFlagUpdated(bool crisis, bytes32 proof, uint64 timestamp);
    event NodeAuthorized(address indexed node, bool authorized);
    event StaleAfterUpdated(uint64 staleAfter);
    event CrisisThresholdUpdated(uint8 threshold);
    
    // Errors
    error InvalidProof();
    error StaleData();
    error UnauthorizedNode();
    error InvalidThreshold();

    constructor(uint64 _staleAfter, uint8 _crisisThreshold) {
        staleAfter = _staleAfter > 0 ? _staleAfter : DEFAULT_STALE_AFTER;
        crisisThreshold = _crisisThreshold > 0 ? _crisisThreshold : DEFAULT_CRISIS_THRESHOLD;
    }

    /**
     * @dev Submit crisis flag with aggregated MPC proof
     * @param _crisis Crisis flag (true if crisis detected)
     * @param proof Aggregated MPC proof from news classification
     */
    function submitFlag(bool _crisis, bytes32 proof) external {
        if (!authorizedNodes[msg.sender]) {
            revert UnauthorizedNode();
        }
        
        // Verify proof (in production, this would verify the aggregated MPC proof)
        if (!_verifyProof(proof, _crisis)) {
            revert InvalidProof();
        }
        
        // Check if data is stale
        if (block.timestamp > lastUpdate + staleAfter) {
            revert StaleData();
        }
        
        crisis = _crisis;
        classifierProof = proof;
        lastUpdate = uint64(block.timestamp);
        
        emit CrisisFlagUpdated(_crisis, proof, lastUpdate);
    }

    /**
     * @dev Get current crisis status
     * @return Current crisis flag
     */
    function getCrisisStatus() external view returns (bool) {
        require(block.timestamp <= lastUpdate + staleAfter, "CrisisOracle: data is stale");
        return crisis;
    }

    /**
     * @dev Check if crisis data is stale
     * @return True if crisis data is stale
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
        require(_staleAfter > 0, "CrisisOracle: stale after must be positive");
        staleAfter = _staleAfter;
        emit StaleAfterUpdated(_staleAfter);
    }

    /**
     * @dev Update crisis threshold
     */
    function setCrisisThreshold(uint8 _threshold) external onlyOwner {
        require(_threshold > 0, "CrisisOracle: threshold must be positive");
        crisisThreshold = _threshold;
        emit CrisisThresholdUpdated(_threshold);
    }

    /**
     * @dev Verify aggregated MPC proof (placeholder implementation)
     * In production, this would verify the actual aggregated MPC proof
     * showing that a majority of classifiers voted for crisis
     */
    function _verifyProof(bytes32 proof, bool _crisis) internal view returns (bool) {
        // Placeholder: in production, this would verify the aggregated MPC proof
        // showing that at least crisisThreshold nodes voted for crisis
        return proof != bytes32(0);
    }

    /**
     * @dev Emergency function to update crisis flag (only owner, for testing)
     */
    function emergencyUpdateCrisis(bool _crisis) external onlyOwner {
        crisis = _crisis;
        lastUpdate = uint64(block.timestamp);
        emit CrisisFlagUpdated(_crisis, bytes32(0), lastUpdate);
    }

    /**
     * @dev Get crisis status with staleness check
     * @return crisis Current crisis flag
     * @return isStaleData True if data is stale
     */
    function getCrisisStatusWithStaleness() external view returns (bool, bool) {
        bool isStaleData = block.timestamp > lastUpdate + staleAfter;
        return (crisis, isStaleData);
    }
} 