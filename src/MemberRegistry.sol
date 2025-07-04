// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MemberRegistry
 * @dev Community membership registry
 * 
 * Manages membership status for the kibbutz community.
 * Used by BasicIncome contract to determine eligibility.
 */
contract MemberRegistry is Ownable {
    // Member tracking
    mapping(address => bool) public members;
    mapping(address => uint64) public joinDate;
    
    // Member count
    uint256 public totalMembers;
    
    // Events
    event MemberAdded(address indexed member, uint64 joinDate);
    event MemberRemoved(address indexed member);
    event BulkMembersUpdated(address[] members, bool[] statuses);
    
    // Errors
    error AlreadyMember();
    error NotMember();
    error InvalidAddress();

    constructor() {
        // Add deployer as first member
        _addMember(msg.sender);
    }

    /**
     * @dev Add a new member
     * @param member Address to add as member
     */
    function addMember(address member) external onlyOwner {
        if (member == address(0)) {
            revert InvalidAddress();
        }
        if (members[member]) {
            revert AlreadyMember();
        }
        
        _addMember(member);
    }

    /**
     * @dev Remove a member
     * @param member Address to remove from membership
     */
    function removeMember(address member) external onlyOwner {
        if (!members[member]) {
            revert NotMember();
        }
        
        members[member] = false;
        totalMembers--;
        
        emit MemberRemoved(member);
    }

    /**
     * @dev Check if address is a member
     * @param member Address to check
     * @return True if address is a member
     */
    function isMember(address member) external view returns (bool) {
        return members[member];
    }

    /**
     * @dev Get member join date
     * @param member Address to check
     * @return Join date timestamp (0 if not a member)
     */
    function getJoinDate(address member) external view returns (uint64) {
        return members[member] ? joinDate[member] : 0;
    }

    /**
     * @dev Get member information
     * @param member Address to check
     * @return isMember Whether address is a member
     * @return joinDate Member join date (0 if not a member)
     * @return membershipDuration Duration of membership in seconds (0 if not a member)
     */
    function getMemberInfo(address member) external view returns (
        bool isMember,
        uint64 joinDate,
        uint256 membershipDuration
    ) {
        isMember = members[member];
        if (isMember) {
            joinDate = joinDate[member];
            membershipDuration = block.timestamp - joinDate;
        } else {
            joinDate = 0;
            membershipDuration = 0;
        }
    }

    /**
     * @dev Bulk update member statuses
     * @param memberAddresses Array of member addresses
     * @param statuses Array of membership statuses (true = add, false = remove)
     */
    function bulkUpdateMembers(
        address[] calldata memberAddresses,
        bool[] calldata statuses
    ) external onlyOwner {
        require(
            memberAddresses.length == statuses.length,
            "MemberRegistry: arrays length mismatch"
        );
        
        for (uint256 i = 0; i < memberAddresses.length; i++) {
            address member = memberAddresses[i];
            bool status = statuses[i];
            
            if (member == address(0)) {
                revert InvalidAddress();
            }
            
            if (status && !members[member]) {
                _addMember(member);
            } else if (!status && members[member]) {
                members[member] = false;
                totalMembers--;
                emit MemberRemoved(member);
            }
        }
        
        emit BulkMembersUpdated(memberAddresses, statuses);
    }

    /**
     * @dev Get all members (warning: gas intensive for large communities)
     * @return memberAddresses Array of all member addresses
     */
    function getAllMembers() external view returns (address[] memory memberAddresses) {
        // This is a simplified implementation
        // In production, you'd want to use a more efficient data structure
        // or implement pagination
        revert("MemberRegistry: getAllMembers not implemented for gas efficiency");
    }

    /**
     * @dev Internal function to add a member
     * @param member Address to add
     */
    function _addMember(address member) internal {
        members[member] = true;
        joinDate[member] = uint64(block.timestamp);
        totalMembers++;
        
        emit MemberAdded(member, joinDate[member]);
    }

    /**
     * @dev Emergency function to reset membership (only owner, for testing)
     */
    function emergencyResetMembership(address member) external onlyOwner {
        if (members[member]) {
            members[member] = false;
            totalMembers--;
            emit MemberRemoved(member);
        }
    }
} 