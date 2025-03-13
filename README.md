# Nawhal Protocol & Nawhal Finance

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Twitter Follow](https://img.shields.io/twitter/follow/nawhalfi?style=social)](https://twitter.com/nawhalfi)
[![Discord](https://img.shields.io/discord/YOUR_DISCORD_ID?style=flat-square)](https://discord.gg/nawhalfi)

Nawhal Protocol is a decentralized liquidity protocol layer built on Sui Move, providing efficient and secure liquidity infrastructure for DeFi applications. Nawhal Finance (nawhal.fi) is a perpetual trading platform developed on top of this protocol.

## 🌟 Features

- 💧 Efficient liquidity protocol layer
- 📈 Zero-slippage perpetual trading
- 🔒 Multi-layer security mechanisms
- 💰 Competitive LP yields
- ⚡ Fast trade execution
- 🛡️ Decentralized risk management

## 🚀 Quick Start

### Prerequisites

- Sui CLI
- Move language development environment
- Node.js >= 16
- Yarn or npm

### Installation

1. Clone the repository

```bash
git clone https://github.com/nawhalfi/nawhal-protocol.git
cd nawhal-protocol
```

2. Install dependencies

```bash
# Install Move dependencies
sui move install

# Install frontend dependencies
cd frontend
yarn install
```

3. Run development environment

```bash
# Start local testnet
sui start

# Start frontend development server
cd frontend
yarn dev
```

## 📚 Documentation

For detailed documentation, visit our [GitBook](https://docs.nawhal.fi):

- [Technical Whitepaper](https://docs.nawhal.fi/whitepaper)
- [API Documentation](https://docs.nawhal.fi/api)
- [Smart Contract Documentation](https://docs.nawhal.fi/contracts)
- [Integration Guide](https://docs.nawhal.fi/integration)

## 🔧 Architecture

### Core Modules

1. Protocol Layer (`/move/protocol`)
   - Liquidity pool management
   - Price oracle integration
   - Risk management system

2. Trading Layer (`/move/exchange`)
   - Order management
   - Position management
   - Liquidation system

3. Frontend (`/frontend`)
   - React application
   - Web3 integration
   - Data visualization

## 🛠️ Development

### Directory Structure

```
nawhal-fi/
├── contracts/                          # Smart contracts
│   ├── nawhal/
│        ├── sources/
│        │       ├── market.move        # market contract
│        │       ├── pool.move          # pool contract
│       └── tests/                      # unit tests
├── docs/                               
└── scripts/                            
```

### Testing

```bash
# Run Move tests
sui move test

# Run frontend tests
cd frontend
yarn test
```

## 🤝 Contributing

We welcome community contributions! Please check our [Contributing Guide](CONTRIBUTING.md) to learn how to participate in the project development.

1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## 🔗 Links

- [Official Website](https://nawhal.fi)
- [Documentation](https://docs.nawhal.fi)
- [Twitter](https://twitter.com/nawhalfi)
- [Discord](https://discord.gg/nawhalfi)
- [Blog](https://blog.nawhal.fi)

## 💬 Community

- Discord: [Join our Discord](https://discord.gg/nawhalfi)
- Twitter: [@nawhalfi](https://twitter.com/nawhalfi)
- Telegram: [Nawhal Official](https://t.me/nawhalfi)

## ⚠️ Disclaimer

Nawhal Protocol and Nawhal Finance are still under development. Please use with caution and understand the associated risks. 