# 🏗️ DeFi Scaffold - Complete DEX Solution

A clean, minimal, and well-organized Automated Market Maker (AMM) implementation for the Sui blockchain. This project provides both smart contracts and a TypeScript SDK for building decentralized exchanges.

## 🌟 Features

### Smart Contracts
- **Simple & Clean Architecture** - Well-organized, readable code structure
- **Minimal Design** - Only essential features, no bloat
- **Type Safety** - Full Move language type safety
- **Comprehensive Testing** - Extensive test coverage for all functionality
- **Gas Optimized** - Efficient operations to minimize transaction costs

### Core Functionality
- ✅ Create trading pairs between any two tokens
- ✅ Add/remove liquidity with automatic optimal ratios
- ✅ Token swapping with slippage protection
- ✅ Multi-hop routing for indirect token pairs
- ✅ Fee collection and protocol revenue
- ✅ Admin controls for fee management

### TypeScript SDK
- 🔧 **Easy Integration** - Simple API for frontend applications
- 📊 **Rich Querying** - Get quotes, pair info, and route optimization
- 🛡️ **Type Safe** - Full TypeScript support with proper types
- 🚀 **Production Ready** - Handles errors, retries, and edge cases
- 📖 **Well Documented** - Comprehensive examples and documentation

## 📁 Project Structure

```
defi-scaffold/
├── contracts/                  # Move smart contracts
│   ├── sources/
│   │   ├── dex_core.move      # Core AMM logic
│   │   └── dex_utils.move     # SDK utility functions
│   ├── tests/
│   │   └── dex_tests.move     # Comprehensive test suite
│   └── Move.toml              # Move package configuration
├── scripts/                   # TypeScript SDK and tools
│   ├── dex-sdk.ts            # Main SDK implementation
│   ├── examples/
│   │   └── dex-examples.ts   # Usage examples
│   └── helpers/              # Utility functions
└── README.md                 # This file
```

## 🚀 Quick Start

### Prerequisites

- [Sui CLI](https://docs.sui.io/build/install) installed
- [Node.js](https://nodejs.org/) v18+ installed
- Basic understanding of Move and TypeScript

### Installation

1. **Clone the repository**
```bash
git clone <repository-url>
cd defi-scaffold
```

2. **Install dependencies**
```bash
npm install
```

3. **Build smart contracts**
```bash
cd contracts
sui move build
```

4. **Run tests**
```bash
sui move test
```

### Deploy to Testnet

1. **Deploy contracts**
```bash
sui client publish --gas-budget 20000000
```

2. **Update SDK configuration**
```typescript
const DEX_CONFIG = {
  packageId: "0x...", // Your deployed package ID
  registryId: "0x...", // Registry object ID from deployment
  adminCapId: "0x...", // Admin capability ID
};
```

## 💡 Usage Examples

### Creating a Trading Pair

```typescript
import { createTestnetDexSDK } from './scripts/dex-sdk';
import { getSigner } from './scripts/helpers/getSigner';

const sdk = createTestnetDexSDK(DEX_CONFIG);
const signer = getSigner({ secretKey: YOUR_PRIVATE_KEY });

// Create USDC-USDT pair with 0.3% fee
const result = await sdk.createPair(
  signer,
  "0x...::usdc::USDC",    // Token A type
  "0x...::usdt::USDT",    // Token B type  
  "1000000",              // Initial amount A (1 USDC)
  "1000000",              // Initial amount B (1 USDT)
  30,                     // 0.3% fee in basis points
  coinAId,                // USDC coin object ID
  coinBId                 // USDT coin object ID
);
```

### Adding Liquidity

```typescript
const result = await sdk.addLiquidity(
  signer,
  pairId,
  "1000000",   // Amount A
  "2000000",   // Amount B
  "0",         // Minimum LP tokens (auto-calculated)
  coinAId,     // Token A coin ID
  coinBId,     // Token B coin ID
  0.5          // 0.5% slippage tolerance
);
```

### Token Swapping

```typescript
const result = await sdk.swap(
  signer,
  pairId,
  "0x...::usdc::USDC",    // Input token type
  "0x...::usdt::USDT",    // Output token type
  "1000000",              // Input amount (1 USDC)
  "990000",               // Minimum output (1% slippage)
  coinInputId,            // Input coin ID
  1.0                     // 1% slippage tolerance
);
```

### Getting Swap Quotes

```typescript
const quote = await sdk.getSwapQuote(
  pairId,
  "0x...::usdc::USDC",
  "1000000",  // 1 USDC
  0.5         // 0.5% slippage
);

console.log(`Expected output: ${quote.amountOut} USDT`);
console.log(`Price impact: ${quote.priceImpact}%`);
```

## 🏗️ Architecture Overview

### Smart Contract Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   dex_core      │    │   dex_utils     │
│                 │    │                 │
│ • TradingPair   │◄───┤ • SDK Wrappers  │
│ • PairRegistry  │    │ • Auto Transfer │
│ • Core Logic    │    │ • Batch Ops     │
│ • Admin Funcs   │    │ • Multi-hop     │
└─────────────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐
│   dex_tests     │
│                 │
│ • Unit Tests    │
│ • Integration   │
│ • Edge Cases    │
│ • Math Verify   │
└─────────────────┘
```

### Key Improvements Over Traditional AMMs

1. **📦 Modular Design**: Core logic separated from utility functions
2. **🧪 Comprehensive Testing**: Extensive test coverage including edge cases
3. **🔒 Better Security**: Multiple validation layers and error handling
4. **⚡ Gas Optimization**: Efficient algorithms and data structures
5. **🛠️ Developer Experience**: Clean APIs and excellent documentation
6. **🎯 Minimal Complexity**: Only essential features, avoiding feature bloat

## 🧪 Testing

The project includes comprehensive tests covering:

- ✅ Core functionality (create, add/remove liquidity, swap)
- ✅ Edge cases (zero amounts, large trades, minimum liquidity)
- ✅ Error conditions (slippage, insufficient liquidity, invalid parameters)
- ✅ Mathematical correctness (constant product formula, precision)
- ✅ Integration scenarios (multi-hop swaps, batch operations)
- ✅ Admin functions (fee updates, fee collection)

Run tests with:
```bash
cd contracts
sui move test
```

## 🔧 Configuration

### Environment Variables

Create a `.env` file:
```env
SUI_NETWORK=testnet
PRIVATE_KEY=your_private_key_here
ADMIN_PRIVATE_KEY=admin_private_key_here
```

### SDK Configuration

```typescript
const DEX_CONFIG = {
  packageId: "0x...",     // Deployed package ID
  registryId: "0x...",    // Registry object ID  
  adminCapId: "0x...",    // Admin capability ID (optional)
};
```

## 📊 Performance

### Gas Costs (Testnet)
- Create Pair: ~2M gas units
- Add Liquidity: ~500K gas units
- Swap: ~400K gas units
- Remove Liquidity: ~450K gas units

### Mathematical Precision
- Uses u128 for intermediate calculations to prevent overflow
- Implements proper rounding for LP token calculations
- Maintains constant product invariant (x * y = k)

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

1. **Code Style**: Follow existing patterns and naming conventions
2. **Testing**: Add tests for any new functionality
3. **Documentation**: Update documentation for API changes
4. **Simplicity**: Keep additions minimal and focused

## 📄 License

This project is licensed under the MIT License. See LICENSE file for details.

## 🆘 Support

- 📚 [Sui Documentation](https://docs.sui.io/)
- 💬 [Sui Discord](https://discord.gg/sui)
- 🐛 [Report Issues](repository-issues-url)

## 🔮 Roadmap

- [ ] **V2 Features**: Concentrated liquidity, multiple fee tiers
- [ ] **Analytics**: Historical data tracking and analytics
- [ ] **Governance**: Token-based governance for protocol decisions  
- [ ] **Cross-chain**: Bridge integration for multi-chain support
- [ ] **Mobile SDK**: React Native SDK for mobile applications

---

**Built with ❤️ for the Sui ecosystem**
