# Fundtir - Comprehensive DeFi Ecosystem

Fundtir is a complete decentralized finance (DeFi) ecosystem featuring a democratic governance system, multi-tier staking mechanism, token presale functionality, and sophisticated vesting schedules. The platform implements a unique "one wallet, one vote" governance system where each participant has equal voting power regardless of their token holdings, ensuring true democratic participation.

## 🏗️ Project Overview

This project includes a complete suite of smart contracts:

- **FNDRGovernance**: A comprehensive DAO contract implementing democratic governance with integrated staking and vesting support
- **FNDRStaking**: A multi-tier staking contract with APY rewards, dividend distributions, and governance checkpointing
- **FundtirToken**: An ERC20 token (FNDR) with 700M total supply, burnable and permit functionality
- **FundtirPresale**: ICO contract for token presale functionality with USDT payments
- **FundtirVesting**: Advanced token vesting contract with cliff periods and progressive releases
- **Comprehensive Test Suite**: Full test coverage for all contracts and their interactions (100+ tests)
- **Hardhat Integration**: Modern development environment with TypeScript support
- **Complete Documentation**: Extensive NatSpec comments for all contracts and functions
- **Deployment Modules**: Hardhat Ignition modules for easy deployment across networks

## 📋 Contract Features

### FNDRGovernance (DAO Contract)
- **Democratic Voting**: One wallet = one vote (regardless of token amount)
- **Proposal System**: Create, vote on, and execute governance proposals
- **Threshold Requirements**: Proposers need 0.25% of total token supply (staked + vested combined)
- **Voting Periods**: Configurable voting delay and period (default: 60s delay, 300s voting)
- **Snapshot Mechanism**: Historic voting power lookup with fallback to current balances
- **Execution Control**: Manual execution via designated executor (typically multisig)
- **Integration**: Seamless integration with staking and vesting contracts
- **Dynamic Quorum**: Admin-configurable quorum requirements
- **Voting Weight**: Minimum voting weight requirement for participation

### FNDRStaking Contract
- **Multi-Tier Staking**: 4 different staking plans with varying APYs and durations
  - Plan 1: 8.97% APY for 90 days
  - Plan 2: 14.35% APY for 365 days  
  - Plan 3: 21.52% APY for 730 days
  - Plan 4: 28.69% APY for 1460 days
- **Interest Calculation**: Linear interest calculation based on staked amount and duration
- **USDT Rewards**: Interest paid in USDT (6 decimals) based on FNDR price
- **Dividend Distribution**: Manual dividend distributions in USDT with snapshot-based eligibility
- **Governance Integration**: Staking provides voting power in DAO governance
- **Checkpointing**: Historic stake lookup for governance snapshots
- **Dynamic Pricing**: FNDR-to-USDT price conversion for reward calculations
- **Access Control**: Role-based access control for admin functions

### FundtirToken (FNDR)
- **ERC20 Standard**: Full ERC20 implementation with burn and permit functionality
- **Fixed Supply**: 700 million tokens minted to admin wallet
- **Ownable2Step**: Admin-controlled with two-step ownership transfer for enhanced security
- **ERC20Permit**: Gasless approvals using EIP-2612 standard
- **ERC20Burnable**: Token burning functionality for deflationary mechanics
- **Decimals**: 18 decimals for precision in calculations

### FundtirPresale
- **ICO Functionality**: Token presale contract for initial coin offering
- **USDT Payments**: Accepts USDT (6 decimals) for token purchases
- **Price Management**: Configurable token price in USDT
- **Investment Management**: Handles presale investments and token distribution
- **Minimum Purchase**: Configurable minimum purchase threshold
- **Access Control**: Role-based access control for presale management
- **Token Distribution**: Automatic FNDR token distribution upon USDT payment

### FundtirVesting
- **Advanced Vesting**: Sophisticated token vesting with cliff periods and progressive releases
- **Cliff Periods**: Initial lock-up periods before any tokens become available
- **Progressive Release**: Gradual token release over specified periods with configurable frequency
- **Instant Unlock**: Optional immediate token release percentage
- **Multiple Schedules**: Support for multiple vesting schedules per beneficiary
- **Time-based Unlocking**: Precise time-based token release mechanisms
- **Beneficiary Management**: Individual vesting schedules for multiple beneficiaries
- **Flexible Parameters**: Configurable cliff periods, vesting periods, and release frequencies

## 🚀 Getting Started

### Prerequisites
- Node.js (v16 or higher)
- npm or yarn
- Hardhat installed globally (optional)

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd Fundtir
```

2. Install dependencies:
```bash
npm install
```

3. Compile contracts:
```bash
npx hardhat compile
```

### Quick Deployment

**Option 1: Automated Deployment (Recommended)**
```bash
# Deploy all contracts automatically
npx hardhat run scripts/deploy-all.ts --network localhost

# Deploy to other networks
npx hardhat run scripts/deploy-all.ts --network sepolia
```

**Option 2: Manual Deployment**
```bash
# 1. Deploy Token
npx hardhat ignition deploy ignition/modules/FundtirToken.ts --network localhost

# 2. Deploy Presale (depends on token)
npx hardhat ignition deploy ignition/modules/FundtirPresale.ts --network localhost

# 3. Deploy Vesting (depends on token)
npx hardhat ignition deploy ignition/modules/FundtirVesting.ts --network localhost

# 4. Deploy Staking (depends on token and USDT)
npx hardhat ignition deploy ignition/modules/FundtirStaking.ts --network localhost

# 5. Deploy DAO (depends on all others)
npx hardhat ignition deploy ignition/modules/FundtirDAO.ts --network localhost
```

For detailed deployment instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).

## 🧪 Testing

The project includes comprehensive test coverage with 100+ tests covering:

- **Contract Deployment**: All contracts deployment and initialization
- **DAO Governance**: Proposal creation, voting mechanisms, and execution
- **Staking Operations**: Multi-tier staking, interest calculations, and rewards
- **Vesting Schedules**: Complex vesting scenarios including 54-month schedules
- **Presale Functionality**: Token presale operations and USDT payments
- **Integration Tests**: Cross-contract interactions and governance integration
- **Admin Functions**: Access controls, parameter updates, and management
- **Edge Cases**: Error handling, boundary conditions, and security scenarios
- **Time Manipulation**: EVM time advancement for testing time-dependent features

### Running Tests

Run all tests:
```bash
npx hardhat test
```

Run specific test files:
```bash
npx hardhat test test/FundtirDAO.ts
npx hardhat test test/FundtirStaking.ts
npx hardhat test test/FundtirVesting.ts
npx hardhat test test/FundtirPresale.ts
npx hardhat test test/FundtirToken.ts
```

## 🚀 Deployment

### Ignition Modules

The project includes comprehensive Hardhat Ignition deployment modules for easy deployment across different networks:

- **Individual Modules**: Deploy contracts one by one in dependency order
- **Network-Specific**: Deploy with network-specific configurations
- **Parameter Override**: Customize deployment parameters

### Deployment Commands

```bash
# Deploy individual contracts in dependency order
npx hardhat ignition deploy ignition/modules/FundtirToken.ts --network localhost
npx hardhat ignition deploy ignition/modules/FundtirPresale.ts --network localhost
npx hardhat ignition deploy ignition/modules/FundtirVesting.ts --network localhost
npx hardhat ignition deploy ignition/modules/FundtirStaking.ts --network localhost
npx hardhat ignition deploy ignition/modules/FundtirDAO.ts --network localhost

# Deploy to other networks
npx hardhat ignition deploy ignition/modules/FundtirToken.ts --network sepolia
npx hardhat ignition deploy ignition/modules/FundtirPresale.ts --network sepolia
# ... continue with other contracts
```

### Supported Networks

- **localhost** - Local development
- **sepolia** - Ethereum testnet
- **mainnet** - Ethereum mainnet
- **polygon** - Polygon mainnet
- **bsc** - Binance Smart Chain

For detailed deployment instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).

## 📊 Governance System

### How It Works

1. **Participation**: Users stake FNDR tokens or have unclaimed vested tokens
2. **Proposal Creation**: Participants with ≥0.25% of total supply (staked + vested) can create proposals
3. **Voting**: All eligible participants can vote (one vote per wallet, regardless of token amount)
4. **Execution**: Proposals pass with simple majority after quorum is met
5. **Snapshot Mechanism**: Voting power is determined at proposal creation time

### Key Features

- **Democratic**: Equal voting power for all participants (one wallet, one vote)
- **Secure**: Requires staking or vesting to participate (prevents spam)
- **Transparent**: All votes and proposals are on-chain with full audit trail
- **Flexible**: Configurable voting periods, thresholds, and quorum requirements
- **Integrated**: Seamless integration with staking and vesting contracts
- **Snapshot-based**: Historic voting power lookup for fair governance

### Voting Power Calculation

Voting power is calculated as:
- **Staked Amount**: Tokens staked in the staking contract (historic snapshot)
- **Unclaimed Vested Amount**: Total vested - total released from vesting contracts
- **Combined Power**: Staked + Unclaimed Vested = Total Voting Power

### Governance Parameters

- **Proposal Threshold**: 0.25% of total token supply (configurable)
- **Voting Delay**: 60 seconds (configurable)
- **Voting Period**: 300 seconds (configurable)
- **Quorum**: 100 votes (configurable)
- **Minimum Voting Weight**: 1000 tokens (configurable)

## 🔧 Configuration

### Network Configuration

The project supports multiple networks:
- **Local Development**: Hardhat Network
- **Testnet**: Sepolia (configured with environment variables)
- **Mainnet**: Ethereum (requires proper configuration)

### Environment Variables

Set up your environment variables:
```bash
# For testnet deployment
export SEPOLIA_PRIVATE_KEY="your-private-key"
export SEPOLIA_RPC_URL="your-rpc-url"
```

## 📁 Project Structure

```
Fundtir/
├── contracts/
│   ├── FundtirDAO.sol           # Governance contract with integrated staking/vesting
│   ├── FundtirStaking.sol       # Multi-tier staking with APY rewards
│   ├── FundtirToken.sol         # ERC20 token with burn and permit functionality
│   ├── FundtirPresale.sol       # ICO contract with USDT payments
│   └── FundtirVesting.sol       # Advanced token vesting with cliff periods
├── test/
│   ├── FundtirDAO.ts            # DAO governance tests (50 tests)
│   ├── FundtirStaking.ts        # Staking functionality tests (30+ tests)
│   ├── FundtirVesting.ts        # Vesting schedule tests (20+ tests)
│   ├── FundtirPresale.ts        # Presale functionality tests
│   └── FundtirToken.ts          # Token functionality tests
├── ignition/
│   └── modules/                 # Hardhat Ignition deployment modules
│       ├── FundtirToken.ts      # Token deployment module
│       ├── FundtirPresale.ts    # Presale deployment module
│       ├── FundtirVesting.ts    # Vesting deployment module
│       ├── FundtirStaking.ts    # Staking deployment module
│       ├── FundtirDAO.ts        # DAO deployment module
│       ├── NetworkConfig.ts     # Network configurations
│       └── README.md            # Deployment documentation
├── scripts/
│   ├── send-op-tx.ts            # Transaction scripts
│   └── deploy-all.ts            # Automated deployment script
├── hardhat.config.ts            # Hardhat configuration
├── package.json                 # Dependencies and scripts
├── tsconfig.json                # TypeScript configuration
├── README.md                    # This comprehensive documentation
└── DEPLOYMENT.md                # Detailed deployment guide
```

## 🛠️ Development

### Adding New Features

1. Create new contracts in `contracts/`
2. Add comprehensive NatSpec documentation
3. Add corresponding tests in `test/`
4. Update deployment modules in `ignition/modules/`
5. Run tests to ensure functionality
6. Update README documentation

### Code Quality

- **Solidity Best Practices**: All contracts follow industry standards
- **Comprehensive Testing**: 100+ tests with full coverage
- **TypeScript**: Type safety for development and testing
- **Hardhat**: Modern development environment with advanced features
- **OpenZeppelin**: Battle-tested security contracts and patterns
- **Security Features**:
  - ReentrancyGuard for protection against reentrancy attacks
  - Ownable2Step for enhanced ownership security
  - AccessControl for role-based permissions
  - Pausable for emergency stops
- **Documentation**: Extensive NatSpec comments for all functions and contracts

### Development Workflow

1. **Contract Development**: Write contracts with comprehensive documentation
2. **Testing**: Create thorough test suites for all functionality
3. **Integration**: Test cross-contract interactions
4. **Security Review**: Implement security best practices
5. **Documentation**: Maintain up-to-date documentation

## 🔒 Security Features

- **Access Control**: Role-based permissions for admin functions
- **Reentrancy Protection**: Guards against reentrancy attacks
- **Ownership Security**: Two-step ownership transfer for enhanced security
- **Pausable Contracts**: Emergency stop functionality where applicable
- **Input Validation**: Comprehensive parameter validation
- **Safe Math**: Overflow/underflow protection
- **Time-based Security**: Proper time manipulation for vesting and staking

## 📈 Tokenomics

### FNDR Token
- **Total Supply**: 700,000,000 FNDR tokens
- **Decimals**: 18 (standard precision)
- **Features**: Burnable, Permit-enabled, Ownable
- **Distribution**: Minted to admin wallet upon deployment

### Staking Rewards
- **Plan 1**: 8.97% APY for 90 days
- **Plan 2**: 14.35% APY for 365 days
- **Plan 3**: 21.52% APY for 730 days
- **Plan 4**: 28.69% APY for 1460 days
- **Reward Currency**: USDT (6 decimals)
- **Calculation**: Linear interest based on staked amount and duration

### Vesting Schedules
- **Flexible Parameters**: Configurable cliff periods, vesting periods, and frequencies
- **Multiple Schedules**: Support for multiple vesting schedules per beneficiary
- **Progressive Release**: Gradual token release with configurable frequency
- **Example**: 54-month vesting with 12-month cliff and 6-month release intervals

## 📝 License

This project is licensed under the MIT License.
