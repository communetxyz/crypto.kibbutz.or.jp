// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./MaicaToken.sol";
import "./RicePriceOracle.sol";
import "./CrisisOracle.sol";

/**
 * @title RiceReserve
 * @dev Rice redemption engine with crisis-based swap ratio
 * 
 * RiceReserve redeems Maica for rice vouchers only when:
 * 1. CrisisOracle.crisis == true, and
 * 2. RiceStockOracle.availableKg >= 30,000
 * 
 * The deterministic ratio is:
 * R(t) = min(γ * S/M, δ * P₀/P_t)
 * where:
 * S = RiceStockOracle.availableKg (kg)
 * M = MaicaToken.totalSupply()
 * P_t = current ¥/kg from RicePriceOracle
 * P₀ = baseline ¥/kg at contract deployment
 */
contract RiceReserve is Ownable {
    // Swap ratio parameters
    uint256 public immutable gamma;
    uint256 public immutable delta;
    uint128 public immutable P0; // Baseline price at deployment
    
    // Minimum rice stock for redemption (30,000 kg = 30 tons)
    uint256 public constant MIN_RICE_STOCK = 30_000;
    
    // Oracle addresses
    address public maicaToken;
    address public riceStockOracle;
    address public ricePriceOracle;
    address public crisisOracle;
    
    // Rice voucher tracking
    mapping(address => uint256) public riceVoucherKg;
    uint256 public totalRiceLiability;
    
    // Events
    event RiceRedeemed(address indexed holder, uint256 maicaAmount, uint256 riceKg, uint256 ratio);
    event VoucherIssued(address indexed holder, uint256 riceKg);
    event OraclesUpdated(address maicaToken, address riceStockOracle, address ricePriceOracle, address crisisOracle);
    
    // Errors
    error NoCrisis();
    error InsufficientRiceStock();
    error InvalidAmount();
    error InvalidRatio();

    constructor(
        uint256 _gamma,
        uint256 _delta,
        uint128 _P0,
        address _maicaToken,
        address _riceStockOracle,
        address _ricePriceOracle,
        address _crisisOracle
    ) {
        gamma = _gamma;
        delta = _delta;
        P0 = _P0;
        maicaToken = _maicaToken;
        riceStockOracle = _riceStockOracle;
        ricePriceOracle = _ricePriceOracle;
        crisisOracle = _crisisOracle;
    }

    /**
     * @dev Redeem Maica for rice vouchers
     * @param maicaAmount Amount of Maica to redeem
     */
    function redeem(uint256 maicaAmount) external {
        if (maicaAmount == 0) {
            revert InvalidAmount();
        }
        
        // Check crisis condition
        bool isCrisis = CrisisOracle(crisisOracle).getCrisisStatus();
        if (!isCrisis) {
            revert NoCrisis();
        }
        
        // Check rice stock condition
        uint256 availableRice = RiceStockOracle(riceStockOracle).getAvailableKg();
        if (availableRice < MIN_RICE_STOCK) {
            revert InsufficientRiceStock();
        }
        
        // Calculate swap ratio R(t)
        uint256 ratio = calculateSwapRatio();
        if (ratio == 0) {
            revert InvalidRatio();
        }
        
        // Calculate rice amount
        uint256 riceKg = (maicaAmount * ratio) / 1e18; // ratio is in wei (1e18 precision)
        
        // Burn Maica tokens
        MaicaToken(maicaToken).burn(msg.sender, maicaAmount);
        
        // Issue rice voucher
        riceVoucherKg[msg.sender] += riceKg;
        totalRiceLiability += riceKg;
        
        emit RiceRedeemed(msg.sender, maicaAmount, riceKg, ratio);
    }

    /**
     * @dev Calculate the swap ratio R(t)
     * R(t) = min(γ * S/M, δ * P₀/P_t)
     * @return Swap ratio in wei (1e18 precision)
     */
    function calculateSwapRatio() public view returns (uint256) {
        uint256 S = RiceStockOracle(riceStockOracle).getAvailableKg();
        uint256 M = MaicaToken(maicaToken).totalSupply();
        uint128 P_t = RicePriceOracle(ricePriceOracle).getPrice();
        
        if (M == 0 || P_t == 0) {
            return 0;
        }
        
        // Calculate γ * S/M
        uint256 ratio1 = (gamma * S * 1e18) / M;
        
        // Calculate δ * P₀/P_t
        uint256 ratio2 = (delta * P0 * 1e18) / P_t;
        
        // Return minimum of the two ratios
        return ratio1 < ratio2 ? ratio1 : ratio2;
    }

    /**
     * @dev Issue rice voucher (called by BasicIncome)
     * @param holder Address to issue voucher to
     * @param riceKg Amount of rice in kg
     */
    function issueVoucher(address holder, uint256 riceKg) external {
        require(msg.sender == owner(), "RiceReserve: only owner can issue vouchers");
        require(riceKg > 0, "RiceReserve: invalid rice amount");
        
        riceVoucherKg[holder] += riceKg;
        totalRiceLiability += riceKg;
        
        emit VoucherIssued(holder, riceKg);
    }

    /**
     * @dev Get rice voucher balance for an address
     * @param holder Address to check
     * @return Rice voucher balance in kg
     */
    function getRiceVoucher(address holder) external view returns (uint256) {
        return riceVoucherKg[holder];
    }

    /**
     * @dev Check if redemption is currently allowed
     * @return True if redemption is allowed
     */
    function isRedemptionAllowed() external view returns (bool) {
        try CrisisOracle(crisisOracle).getCrisisStatus() returns (bool isCrisis) {
            if (!isCrisis) return false;
        } catch {
            return false;
        }
        
        try RiceStockOracle(riceStockOracle).getAvailableKg() returns (uint256 availableRice) {
            return availableRice >= MIN_RICE_STOCK;
        } catch {
            return false;
        }
    }

    /**
     * @dev Update oracle addresses
     */
    function updateOracles(
        address _maicaToken,
        address _riceStockOracle,
        address _ricePriceOracle,
        address _crisisOracle
    ) external onlyOwner {
        maicaToken = _maicaToken;
        riceStockOracle = _riceStockOracle;
        ricePriceOracle = _ricePriceOracle;
        crisisOracle = _crisisOracle;
        
        emit OraclesUpdated(_maicaToken, _riceStockOracle, _ricePriceOracle, _crisisOracle);
    }

    /**
     * @dev Get current system state for redemption
     * @return isCrisis Current crisis status
     * @return availableRice Available rice stock in kg
     * @return swapRatio Current swap ratio
     * @return canRedeem Whether redemption is currently allowed
     */
    function getRedemptionState() external view returns (
        bool isCrisis,
        uint256 availableRice,
        uint256 swapRatio,
        bool canRedeem
    ) {
        try CrisisOracle(crisisOracle).getCrisisStatus() returns (bool crisis) {
            isCrisis = crisis;
        } catch {
            isCrisis = false;
        }
        
        try RiceStockOracle(riceStockOracle).getAvailableKg() returns (uint256 rice) {
            availableRice = rice;
        } catch {
            availableRice = 0;
        }
        
        swapRatio = calculateSwapRatio();
        canRedeem = isCrisis && availableRice >= MIN_RICE_STOCK;
    }
}

/**
 * @title RiceStockOracle
 * @dev Interface for rice stock oracle
 */
interface RiceStockOracle {
    function getAvailableKg() external view returns (uint256);
} 