# Kibbutz Crypto-Economic System

A comprehensive blockchain-based economic system for kibbutz communities, implementing algorithmic local currency, rice-based economics, and crisis management mechanisms.

## Overview

This system implements 6 core mechanisms that work together to create a sustainable, community-driven economy:

1. **Maica Community Currency** - Algorithmic local money for all on-site spending
2. **MPC/TLS Rice-Price Oracle** - Trust-minimized feed of ¥ per kg
3. **Rice-Reserve & Swap Ratio R(t)** - Determines kg-per-Maica and redeems Maica for rice during crises
4. **Maica Usage Market (Allow-listed Transfers)** - Only approved merchant/utility addresses may receive Maica
5. **Crisis Oracle (MPC/TLS Newspapers)** - Emits a crisis flag by classifying news content
6. **Basic Rice-Income (60 kg / year)** - Universal annual rice entitlement for every registered member

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  ServiceOracle  │    │ RiceStockOracle │    │ RicePriceOracle │
│  (Capacity)     │    │   (Harvest)     │    │   (¥/kg)        │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌─────────────▼─────────────┐
                    │      MaicaToken           │
                    │   (Community Currency)    │
                    └─────────────┬─────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │     RiceReserve           │
                    │   (Redemption Engine)     │
                    └─────────────┬─────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
┌─────────▼─────────┐    ┌────────▼────────┐    ┌────────▼────────┐
│   CrisisOracle    │    │  BasicIncome    │    │ MemberRegistry  │
│   (News Class.)   │    │  (60kg/year)    │    │  (Membership)   │
└───────────────────┘    └─────────────────┘    └─────────────────┘
```

## Core Contracts

### 1. MaicaToken
- **Purpose**: Community currency with restricted transfers
- **Emission Formula**: `ΔM = α * max(0, C_t - C_{t-1}) + β * R_t / 1000`
- **Features**:
  - Monthly algorithmic emission based on service capacity and rice harvest
  - Allow-listed transfers (only approved merchants can receive)
  - EIP-712 signature-based allowlist management
  - 30-day emission cadence

### 2. RicePriceOracle
- **Purpose**: MPC/TLS-based rice price feed
- **Features**:
  - Authorized MPC nodes submit price data with TLS proofs
  - Configurable staleness period (default: 48 hours)
  - Price validation and range checking
  - Emergency price updates for testing

### 3. CrisisOracle
- **Purpose**: News-based crisis detection
- **Features**:
  - MPC cluster analyzes newspaper articles
  - BERT-based crisis classification
  - Majority voting mechanism
  - Configurable crisis threshold

### 4. RiceReserve
- **Purpose**: Rice redemption engine with crisis-based activation
- **Swap Ratio**: `R(t) = min(γ * S/M, δ * P₀/P_t)`
- **Activation Conditions**:
  - Crisis flag must be true
  - Available rice stock ≥ 30,000 kg
- **Features**:
  - Deterministic swap ratio calculation
  - Rice voucher issuance
  - Crisis and stock monitoring

### 5. BasicIncome
- **Purpose**: Universal rice entitlement system with cumulative claiming
- **Features**:
  - Configurable rice amount per year per member (default: 60 kg)
  - All balance calculations done in function context
  - Cumulative claiming based on time elapsed since last claim
  - Members can claim whenever they want
  - Member registry integration
  - Automatic voucher issuance
  - Dynamic amount updates by owner
  - Comprehensive claim tracking and history

### 6. ServiceOracle
- **Purpose**: Service capacity tracking
- **Features**:
  - Tracks beds, seats, and rentable square meters
  - Used for Maica emission calculations
  - Authorized updater system
  - Configurable staleness period

### 7. RiceStockOracle
- **Purpose**: Rice stock tracking
- **Features**:
  - Monitors available rice in kg
  - Used for redemption eligibility and swap ratios
  - Authorized updater system
  - Stock validation

### 8. MemberRegistry
- **Purpose**: Community membership management
- **Features**:
  - Member addition/removal
  - Join date tracking
  - Bulk member operations
  - Membership duration calculation

## Installation & Setup

### Prerequisites
- [Foundry](https://getfoundry.sh/)
- Node.js (for additional tooling)

### Installation
```bash
# Clone the repository
git clone <repository-url>
cd crypto.kibbutz.or.jp

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Environment Setup
Create a `.env` file:
```bash
PRIVATE_KEY=your_private_key_here
RPC_URL=your_rpc_url_here
```

## Deployment

### Local Development
```bash
# Start local node
anvil

# Deploy to local network
forge script script/DeployKibbutz.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Mainnet Deployment
```bash
# Deploy to mainnet
forge script script/DeployKibbutz.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## Usage Examples

### 1. Adding a Merchant to Allowlist
```solidity
// Two existing allowlisted addresses must sign
bytes memory sig1 = signAllowChange(newMerchant, true, nonce, signer1);
bytes memory sig2 = signAllowChange(newMerchant, true, nonce, signer2);

maicaToken.proposeAllowChange(newMerchant, true, sig1, sig2);
```

### 2. Executing Monthly Emission
```solidity
// Anyone can call this when emission is due
maicaToken.executeEmission();
```

### 3. Claiming Basic Income
```solidity
// Member can claim whenever they want - amount is calculated cumulatively
basicIncome.claim();

// Check claimable amount for a member
uint256 claimable = basicIncome.calculateClaimableAmount(member);

// Get comprehensive claim information
(
    bool isMember,
    uint64 lastClaimTime,
    bool canClaimNow,
    uint256 claimableAmount,
    uint256 timeElapsed,
    uint256 totalClaimed,
    uint256 currentRate
) = basicIncome.getClaimInfo(member);

// Calculate total claimed by a member
uint256 totalClaimed = basicIncome.calculateTotalClaimed(member, currentTime);

// Owner can update the basic income amount
basicIncome.setKgPerYear(80); // Change to 80 kg per year

// Check current basic income amount
uint256 currentAmount = basicIncome.getCurrentKgPerYear();
```

### 4. Redeeming Maica for Rice (during crisis)
```solidity
// Only works when crisis flag is true and sufficient stock exists
riceReserve.redeem(maicaAmount);
```

### 5. Updating Oracle Data
```solidity
// Service capacity update
serviceOracle.updateCapacity(beds, seats, rentableSqm);

// Rice stock update
riceStockOracle.updateStock(availableKg);

// Price update (authorized nodes only)
ricePriceOracle.submitPrice(price, proof);

// Crisis flag update (authorized nodes only)
crisisOracle.submitFlag(crisis, proof);
```

## Testing

### Run All Tests
```bash
forge test
```

### Run Specific Test
```bash
forge test --match-test testMaicaTokenEmission
```

### Run Tests with Verbose Output
```bash
forge test -vvv
```

### Gas Report
```bash
forge test --gas-report
```

## Configuration Parameters

### Emission Parameters
- `α (alpha)`: Service capacity coefficient (default: 100)
- `β (beta)`: Rice harvest coefficient (default: 50)

### Swap Ratio Parameters
- `γ (gamma)`: Stock/supply ratio coefficient (default: 1e18)
- `δ (delta)`: Price ratio coefficient (default: 1e18)
- `P₀`: Baseline rice price at deployment (default: 500 ¥/kg)

### System Constants
- Minimum rice stock for redemption: 30,000 kg
- Basic income per year: Configurable (default: 60 kg)
- Emission interval: 30 days
- Basic income: Cumulative claiming based on time elapsed

### Oracle Configuration
- Price oracle staleness: 48 hours
- Crisis oracle staleness: 24 hours
- Service oracle staleness: 7 days
- Stock oracle staleness: 24 hours
- Crisis threshold: 2 out of 3 nodes

## Security Considerations

### Access Control
- All oracles use authorized updater/node systems
- MaicaToken ownership transferred to RiceReserve
- RiceReserve ownership transferred to BasicIncome
- Allowlist management requires EIP-712 signatures

### Economic Safety
- Swap ratio uses minimum of two calculations
- Crisis activation requires both flag and sufficient stock
- Emission formula prevents negative growth
- Staleness checks prevent outdated data usage

### Oracle Security
- TLS notary proofs for price data
- MPC aggregation for crisis detection
- Configurable staleness periods
- Emergency functions for testing only

## Economic Model

### Maica Emission
The system emits new Maica tokens monthly based on:
1. **Service Capacity Growth**: `α * max(0, C_t - C_{t-1})`
2. **Rice Harvest**: `β * R_t / 1000`

This creates a currency that grows with the community's productive capacity.

### Rice Redemption
During crises, Maica can be redeemed for rice at ratio:
`R(t) = min(γ * S/M, δ * P₀/P_t)`

This ensures:
- Sufficient rice backing (S/M ratio)
- Price stability (P₀/P_t ratio)
- Crisis-only activation

### Basic Income
Every member accumulates rice entitlements continuously, providing:
- Universal basic needs coverage
- Independence from work frequency
- Community solidarity mechanism
- Flexible claiming schedule
- Proportional accumulation based on time elapsed

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

MIT License - see LICENSE file for details.

## Acknowledgments

This system is inspired by:
- Local currency movements
- Universal basic income experiments
- Community resilience mechanisms
- Algorithmic stablecoin designs
- Oracle-based economic systems

## Support

For questions, issues, or contributions, please open an issue on GitHub or contact the development team.
