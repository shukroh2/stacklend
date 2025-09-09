# StackLend Protocol

A DAO-governed lending and borrowing protocol implemented in Clarity v2 for the Stacks blockchain.

## Overview

StackLend enables users to:
- Deposit STX as collateral
- Borrow against their collateral
- Earn interest on deposits
- Participate in liquidations
- Govern protocol parameters through DAO

## Key Features

- **Collateralized Lending**: 150% minimum collateral ratio
- **Dynamic Interest Rates**: 5% base rate (annualized)
- **Liquidation Mechanism**: Triggered below 120% collateral ratio
- **DAO Governance**: Adjustable parameters including:
  - Collateral ratios
  - Interest rates
  - Liquidation thresholds
  - Treasury fees

## Technical Details

- **Language**: Clarity v2
- **Platform**: Stacks Blockchain
- **Smart Contract**: stacklend.clar

## Protocol Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Collateral Ratio | 150% | Minimum required collateral |
| Liquidation Threshold | 120% | Trigger for liquidation |
| Interest Rate | 5% | Annual borrowing rate |
| Liquidation Bonus | 5% | Incentive for liquidators |
| Treasury Fee | 1% | Protocol revenue share |

## Usage Warning

This is a reference implementation. Before deployment:
- Complete security audit
- Test thoroughly with Clarinet
- Adapt for production use

## Development

To test locally:
1. Install Clarinet
2. Run test suite
3. Deploy to testnet before mainnet

## License

MIT License
