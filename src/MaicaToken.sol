// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title MaicaToken
 * @dev Community currency with restricted transfers and algorithmic emission
 * 
 * Emission formula: ΔM = α * max(0, C_t - C_{t-1}) + β * R_t / 1000
 * where C_t = service capacity, R_t = rice harvest
 */
contract MaicaToken is ERC20, Ownable {
    using ECDSA for bytes32;

    // Emission parameters
    uint256 public immutable alpha;
    uint256 public immutable beta;
    
    // Emission timing
    uint64 public nextEmissionBlock;
    uint256 public constant EMISSION_INTERVAL = 30 days;
    
    // Oracle addresses
    address public serviceOracle;
    address public riceStockOracle;
    
    // Allowlist management
    mapping(address => bool) public allowList;
    mapping(address => uint256) public nonces;
    
    // Historical data for emission calculation
    uint256 public lastServiceCapacity;
    uint256 public lastRiceHarvest;
    
    // Events
    event AllowListUpdated(address indexed account, bool allowed);
    event EmissionExecuted(uint256 amount, uint256 serviceCapacity, uint256 riceHarvest);
    event OraclesUpdated(address serviceOracle, address riceStockOracle);
    
    // EIP-712 domain separator
    bytes32 public constant DOMAIN_SEPARATOR = keccak256(
        abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("MaicaToken")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        )
    );
    
    bytes32 public constant ALLOW_CHANGE_TYPEHASH = keccak256(
        "AllowChange(address candidate,bool value,uint256 nonce)"
    );

    constructor(
        string memory name,
        string memory symbol,
        uint256 _alpha,
        uint256 _beta,
        address _serviceOracle,
        address _riceStockOracle
    ) ERC20(name, symbol) {
        alpha = _alpha;
        beta = _beta;
        serviceOracle = _serviceOracle;
        riceStockOracle = _riceStockOracle;
        nextEmissionBlock = uint64(block.timestamp + EMISSION_INTERVAL);
        
        // Add deployer to allowlist
        allowList[msg.sender] = true;
    }

    /**
     * @dev Override transfer to enforce allowlist restrictions
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(allowList[to], "MaicaToken: recipient not in allowlist");
        return super.transfer(to, amount);
    }

    /**
     * @dev Override transferFrom to enforce allowlist restrictions
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(allowList[to], "MaicaToken: recipient not in allowlist");
        return super.transferFrom(from, to, amount);
    }

    /**
     * @dev Execute monthly emission if conditions are met
     */
    function executeEmission() external {
        require(block.timestamp >= nextEmissionBlock, "MaicaToken: emission not due yet");
        
        // Get current data from oracles
        uint256 currentServiceCapacity = ServiceOracle(serviceOracle).getCapacity();
        uint256 currentRiceHarvest = RiceStockOracle(riceStockOracle).getHarvest();
        
        // Calculate emission amount
        uint256 serviceEmission = alpha * max(0, currentServiceCapacity - lastServiceCapacity);
        uint256 riceEmission = beta * currentRiceHarvest / 1000;
        uint256 totalEmission = serviceEmission + riceEmission;
        
        if (totalEmission > 0) {
            _mint(address(this), totalEmission);
            emit EmissionExecuted(totalEmission, currentServiceCapacity, currentRiceHarvest);
        }
        
        // Update state
        lastServiceCapacity = currentServiceCapacity;
        lastRiceHarvest = currentRiceHarvest;
        nextEmissionBlock = uint64(block.timestamp + EMISSION_INTERVAL);
    }

    /**
     * @dev Add/remove address from allowlist with EIP-712 signatures
     */
    function proposeAllowChange(
        address candidate,
        bool value,
        bytes calldata sig1,
        bytes calldata sig2
    ) external {
        require(sig1.length == 65 && sig2.length == 65, "MaicaToken: invalid signature length");
        
        bytes32 structHash = keccak256(
            abi.encode(ALLOW_CHANGE_TYPEHASH, candidate, value, nonces[candidate])
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        
        address signer1 = hash.recover(sig1);
        address signer2 = hash.recover(sig2);
        
        require(signer1 != signer2, "MaicaToken: duplicate signers");
        require(allowList[signer1] && allowList[signer2], "MaicaToken: signers not in allowlist");
        
        allowList[candidate] = value;
        nonces[candidate]++;
        
        emit AllowListUpdated(candidate, value);
    }

    /**
     * @dev Mint tokens to reserve (called by RiceReserve during redemption)
     */
    function mintToReserve(uint256 amount) external {
        require(msg.sender == owner(), "MaicaToken: only owner can mint to reserve");
        _mint(msg.sender, amount);
    }

    /**
     * @dev Burn tokens (called by RiceReserve during redemption)
     */
    function burn(address from, uint256 amount) external {
        require(msg.sender == owner(), "MaicaToken: only owner can burn");
        _burn(from, amount);
    }

    /**
     * @dev Update oracle addresses
     */
    function updateOracles(address _serviceOracle, address _riceStockOracle) external onlyOwner {
        serviceOracle = _serviceOracle;
        riceStockOracle = _riceStockOracle;
        emit OraclesUpdated(_serviceOracle, _riceStockOracle);
    }

    /**
     * @dev Utility function for max operation
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}

/**
 * @title ServiceOracle
 * @dev Interface for service capacity oracle
 */
interface ServiceOracle {
    function getCapacity() external view returns (uint256);
}

/**
 * @title RiceStockOracle
 * @dev Interface for rice stock oracle
 */
interface RiceStockOracle {
    function getHarvest() external view returns (uint256);
} 