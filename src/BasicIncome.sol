// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./RiceReserve.sol";

/**
 * @title BasicIncome
 * @dev Universal rice entitlement system with cumulative claiming
 * 
 * Users can claim tokens whenever they want. Their claimed balance is calculated
 * cumulatively based on time elapsed since their last claim, with all calculations
 * done in the function context.
 */
contract BasicIncome is Ownable {
    // Configuration
    uint256 public kgPerYear = 60;
    
    // Oracle addresses
    address public memberRegistry;
    address public riceReserve;
    
    // Claim tracking - stores the timestamp of last claim
    mapping(address => uint64) public lastClaimTime;
    
    // Events
    event RiceClaimed(
        address indexed member, 
        uint256 riceKg, 
        uint64 claimTime, 
        uint256 timeElapsed,
        uint256 totalClaimed
    );
    event OraclesUpdated(address memberRegistry, address riceReserve);
    event KgPerYearUpdated(uint256 newKgPerYear);
    
    // Errors
    error NotMember();
    error NoClaimableAmount();
    error InvalidOracle();
    error InvalidAmount();

    constructor(address _memberRegistry, address _riceReserve) {
        memberRegistry = _memberRegistry;
        riceReserve = _riceReserve;
    }

    /**
     * @dev Claim accumulated rice entitlement
     * All balance calculations are done in function context
     */
    function claim() external {
        // Check if caller is a registered member
        if (!MemberRegistry(memberRegistry).isMember(msg.sender)) {
            revert NotMember();
        }
        
        // Get current timestamp for calculations
        uint64 currentTime = uint64(block.timestamp);
        uint64 lastClaim = lastClaimTime[msg.sender];
        
        // Calculate time elapsed since last claim
        uint256 timeElapsed;
        if (lastClaim == 0) {
            // First time claiming - use current time as elapsed time
            timeElapsed = currentTime;
        } else {
            timeElapsed = currentTime - lastClaim;
        }
        
        // Calculate claimable amount based on time elapsed
        uint256 claimableAmount = (timeElapsed * kgPerYear) / 365 days;
        
        if (claimableAmount == 0) {
            revert NoClaimableAmount();
        }
        
        // Issue rice voucher
        RiceReserve(riceReserve).issueVoucher(msg.sender, claimableAmount);
        
        // Update last claim time
        lastClaimTime[msg.sender] = currentTime;
        
        // Calculate total claimed for this user (for event)
        uint256 totalClaimed = calculateTotalClaimed(msg.sender, currentTime);
        
        emit RiceClaimed(
            msg.sender, 
            claimableAmount, 
            currentTime, 
            timeElapsed,
            totalClaimed
        );
    }

    /**
     * @dev Calculate claimable amount for a member
     * All calculations done in function context
     * @param member Address to check
     * @return Claimable amount in kg
     */
    function calculateClaimableAmount(address member) public view returns (uint256) {
        if (!MemberRegistry(memberRegistry).isMember(member)) {
            return 0;
        }
        
        uint64 currentTime = uint64(block.timestamp);
        uint64 lastClaim = lastClaimTime[member];
        
        // Calculate time elapsed
        uint256 timeElapsed;
        if (lastClaim == 0) {
            // First time claiming
            timeElapsed = currentTime;
        } else {
            timeElapsed = currentTime - lastClaim;
        }
        
        // Calculate amount based on time elapsed and annual rate
        return (timeElapsed * kgPerYear) / 1 years;
    }

    /**
     * @dev Calculate total rice claimed by a member since joining
     * @param member Address to check
     * @param currentTime Current timestamp (for consistency)
     * @return Total rice claimed in kg
     */
    function calculateTotalClaimed(address member, uint64 currentTime) public view returns (uint256) {
        if (!MemberRegistry(memberRegistry).isMember(member)) {
            return 0;
        }
        
        uint64 lastClaim = lastClaimTime[member];
        
        if (lastClaim == 0) {
            // Haven't claimed yet
            return 0;
        }
        
        // Calculate total time since first claim
        uint256 totalTimeElapsed = currentTime - lastClaim;
        
        // Calculate total claimed based on total time
        return (totalTimeElapsed * kgPerYear) / 365 days;
    }

    /**
     * @dev Get comprehensive claim information for a member
     * All calculations done in function context
     * @param member Address to check
     * @return isMember Whether address is a registered member
     * @return lastClaimTime Timestamp of last claim
     * @return canClaimNow Whether member can claim now
     * @return claimableAmount Amount that can be claimed now
     * @return timeElapsed Time elapsed since last claim
     * @return totalClaimed Total rice claimed by this member
     * @return currentRate Current kg per year rate
     */
    function getClaimInfo(address member) external view returns (
        bool isMember,
        uint64 lastClaimTime,
        bool canClaimNow,
        uint256 claimableAmount,
        uint256 timeElapsed,
        uint256 totalClaimed,
        uint256 currentRate
    ) {
        uint64 currentTime = uint64(block.timestamp);
        isMember = MemberRegistry(memberRegistry).isMember(member);
        lastClaimTime = lastClaimTime[member];
        currentRate = kgPerYear;
        
        if (isMember) {
            claimableAmount = calculateClaimableAmount(member);
            canClaimNow = claimableAmount > 0;
            
            if (lastClaimTime == 0) {
                timeElapsed = currentTime;
                totalClaimed = 0;
            } else {
                timeElapsed = currentTime - lastClaimTime;
                totalClaimed = calculateTotalClaimed(member, currentTime);
            }
        } else {
            canClaimNow = false;
            claimableAmount = 0;
            timeElapsed = 0;
            totalClaimed = 0;
        }
    }

    /**
     * @dev Check if a member can claim rice
     * @param member Address to check
     * @return True if member can claim
     */
    function canClaim(address member) external view returns (bool) {
        return calculateClaimableAmount(member) > 0;
    }

    /**
     * @dev Get time until next claim would be available
     * @param member Address to check
     * @return Time in seconds until next claim (0 if can claim now)
     */
    function timeUntilNextClaim(address member) external view returns (uint256) {
        if (!MemberRegistry(memberRegistry).isMember(member)) {
            return 0;
        }
        
        uint256 claimableAmount = calculateClaimableAmount(member);
        if (claimableAmount > 0) {
            return 0; // Can claim now
        }
        
        // Calculate time needed for next claim
        uint256 timeNeeded = (365 days * 1) / kgPerYear; // Time for 1 kg
        uint64 lastClaim = lastClaimTime[member];
        
        if (lastClaim == 0) {
            return 0; // New member, can claim immediately
        }
        
        uint256 timeElapsed = block.timestamp - lastClaim;
        if (timeElapsed >= timeNeeded) {
            return 0; // Can claim now
        }
        
        return timeNeeded - timeElapsed;
    }

    /**
     * @dev Update oracle addresses
     */
    function updateOracles(address _memberRegistry, address _riceReserve) external onlyOwner {
        memberRegistry = _memberRegistry;
        riceReserve = _riceReserve;
        
        emit OraclesUpdated(_memberRegistry, _riceReserve);
    }

    /**
     * @dev Update basic income amount per year
     * @param newKgPerYear New amount in kg per year
     */
    function setKgPerYear(uint256 newKgPerYear) external onlyOwner {
        if (newKgPerYear == 0) {
            revert InvalidAmount();
        }
        kgPerYear = newKgPerYear;
        emit KgPerYearUpdated(newKgPerYear);
    }

    /**
     * @dev Get current basic income amount
     * @return Current kg per year
     */
    function getCurrentKgPerYear() external view returns (uint256) {
        return kgPerYear;
    }

    /**
     * @dev Emergency function to reset claim time (only owner, for testing)
     */
    function emergencyResetClaim(address member) external onlyOwner {
        lastClaimTime[member] = 0;
    }

    /**
     * @dev Get member's claim history
     * @param member Address to check
     * @return lastClaimTime Timestamp of last claim
     * @return timeSinceLastClaim Time elapsed since last claim
     * @return totalTimeAsMember Total time as member (if available)
     */
    function getClaimHistory(address member) external view returns (
        uint64 lastClaimTime,
        uint256 timeSinceLastClaim,
        uint256 totalTimeAsMember
    ) {
        lastClaimTime = lastClaimTime[member];
        uint64 currentTime = uint64(block.timestamp);
        
        if (lastClaimTime == 0) {
            timeSinceLastClaim = currentTime;
            totalTimeAsMember = 0; // Would need member join time to calculate this
        } else {
            timeSinceLastClaim = currentTime - lastClaimTime;
            totalTimeAsMember = 0; // Placeholder - would need member registry integration
        }
    }
}

/**
 * @title MemberRegistry
 * @dev Interface for member registry
 */
interface MemberRegistry {
    function isMember(address member) external view returns (bool);
} 