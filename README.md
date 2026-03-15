# StoneForm Presale

A production-grade tiered token presale system deployed on **BSC Mainnet**, featuring automatic tier progression, Sablier-powered token vesting, and multi-layered security.

> **Live on BSC Mainnet:** [`0xc470e8691a9bcdc081db971615060a17b3577543`](https://bscscan.com/address/0xc470e8691a9bcdc081db971615060a17b3577543)

---

## What It Does

StoneForm Presale allows projects to run a structured token sale where:

1. **Buyers purchase tokens** across multiple pricing tiers that automatically progress as caps fill
2. **A backend signer** authorizes each purchase via ECDSA signatures, enabling off-chain KYC/whitelist logic
3. **After the sale finalizes**, buyers claim their tokens through Sablier vesting streams with per-tier TGE unlock percentages and linear vesting schedules

A single purchase can span multiple tiers — if Tier 0 fills mid-transaction, the remaining collateral rolls into Tier 1 at the new price, all in one atomic operation.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    StoneFormPresaleAdvanced                  │
│                                                             │
│  AccessControl ─── ADMIN_ROLE (multisig)                    │
│                └── SIGNER_ROLE (backend)                     │
│                                                             │
│  Purchase Flow:                                             │
│  ┌──────────┐    ┌───────────┐    ┌──────────────────────┐  │
│  │  Buyer   │───>│  Verify   │───>│  Tier Calculation     │  │
│  │ + Sig    │    │  ECDSA    │    │  (auto-progression)   │  │
│  └──────────┘    └───────────┘    └──────────┬───────────┘  │
│                                              │              │
│  Vesting Flow:                               ▼              │
│  ┌──────────┐    ┌───────────┐    ┌──────────────────────┐  │
│  │  Buyer   │───>│ Finalize  │───>│  Sablier Stream      │  │
│  │  Claims  │    │ (TGE)     │    │  (linear unlock)     │  │
│  └──────────┘    └───────────┘    └──────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Tier Configuration (Example)

| Tier | Price | Cap | Vesting | TGE Unlock |
|------|-------|-----|---------|------------|
| 0 | 0.010 USD | 50,000 tokens | 180 days | 10% |
| 1 | 0.015 USD | 30,000 tokens | 270 days | 15% |
| 2 | 0.020 USD | 20,000 tokens | 365 days | 20% |

---

## Security

| Layer | Implementation |
|-------|---------------|
| **Access Control** | OpenZeppelin `AccessControl` with separated `ADMIN_ROLE` (multisig) and `SIGNER_ROLE` (backend) |
| **Reentrancy Protection** | OpenZeppelin `ReentrancyGuard` on `purchaseTokens` and `createMyVesting` |
| **Pause Mechanism** | OpenZeppelin `Pausable` — admin can halt purchases and vesting claims |
| **Signature Verification** | ECDSA signature required per purchase with nonce replay protection |
| **Admin Transfer** | 2-step process (`initiateAdminTransfer` -> `acceptAdminRole`) prevents accidental ownership loss |
| **Safe Transfers** | `SafeERC20` for all token operations |
| **Emergency Recovery** | `emergencyWithdraw` for both ERC20 and native tokens |

---

## Project Structure

```
stoneform-presale/
├── src/
│   ├── StoneFormPresaleAdvanced.sol   # Core presale contract (tiered + vesting + security)
│   ├── StoneFormPresale.sol           # Simple ICO contract (flat-rate, Chainlink oracles)
│   └── StoneFormToken.sol             # ERC20 token + mock USD for testing
├── script/
│   ├── DeployStoneFormAdvanced.s.sol  # Deploy orchestrator (uses HelperConfig)
│   ├── HelperConfig.s.sol             # Multi-chain config (BSC mainnet + Anvil)
│   └── Interactions.s.sol             # Modular post-deploy steps
├── test/
│   ├── unit/
│   │   └── StoneFormPresaleAdvanced.t.sol  # 35 unit tests
│   └── mocks/
│       └── MockSablier.sol            # Sablier mock for local testing
├── foundry.toml
└── Makefile
```

---

## Tech Stack

- **Solidity** `^0.8.28`
- **Foundry** (Forge, Cast, Anvil)
- **OpenZeppelin Contracts** v5 — AccessControl, ReentrancyGuard, Pausable, SafeERC20, ECDSA
- **Sablier V2** — Token vesting via lockup linear streams
- **BSC (BNB Smart Chain)** — Production deployment

---

## Testing

35 unit tests covering all contract functionality:

```
forge test
```

```
[PASS] testConstructorSetsRoles()
[PASS] testConstructorSetsTiers()
[PASS] testConstructorComputesHardCap()
[PASS] testConstructorRevertsZeroAdmin()
[PASS] testConstructorRevertsZeroSigner()
[PASS] testConstructorRevertsNoTiers()
[PASS] testConstructorRevertsZeroTierPrice()
[PASS] testInitPresale()
[PASS] testInitPresaleRevertsNonAdmin()
[PASS] testInitPresaleRevertsPastTime()
[PASS] testPurchaseTokens()
[PASS] testPurchaseRevertsBeforeInit()
[PASS] testPurchaseRevertsBelowMinPurchase()
[PASS] testPurchaseRevertsInvalidPaymentToken()
[PASS] testPurchaseRevertsReusedNonce()
[PASS] testPurchaseRevertsInvalidSignature()
[PASS] testPurchaseProgressesThroughTiers()
[PASS] testPauseBlocksPurchase()
[PASS] testUnpauseAllowsPurchase()
[PASS] testFinalizePresale()
[PASS] testFinalizeRevertsWithoutPresaleToken()
[PASS] testFinalizeRevertsDoubleFinalize()
[PASS] testCreateMyVesting()
[PASS] testCreateVestingRevertsBeforeFinalize()
[PASS] testCreateVestingRevertsDoubleCreation()
[PASS] testTwoStepAdminTransfer()
[PASS] testAcceptAdminRevertsWrongCaller()
[PASS] testUpdateSigner()
[PASS] testEmergencyWithdrawERC20()
[PASS] testEmergencyWithdrawRevertsNonAdmin()
[PASS] testEmergencyWithdrawRevertsZeroAddress()
[PASS] testSetPresaleToken()
[PASS] testSetPresaleTokenRevertsZeroAddress()
[PASS] testSetMinPurchase()
[PASS] testSetMaxPurchase()

Suite result: ok. 35 passed; 0 failed; 0 skipped
```

---

## Quick Start

```bash
# Clone
git clone --recurse-submodules https://github.com/0xSylla/stoneform-presale.git
cd stoneform-presale

# Install dependencies
make install

# Build
make build

# Run tests
make test

# Deploy locally
make anvil          # Terminal 1
make deploy-anvil   # Terminal 2

# Deploy to BSC
make deploy-bsc
```

---

## Deployment

The deploy script uses the **HelperConfig pattern** for multi-chain support:

- **Anvil (local):** Automatically deploys mock tokens (MockUSD) and a mock Sablier contract
- **BSC Mainnet:** Uses real USDT (`0x55d3...7955`) and Sablier (`0x06bd...0C74`) addresses

```bash
# Configure environment
cp .env.example .env
# Edit .env with your keys

# Deploy to BSC mainnet
forge script script/DeployStoneFormAdvanced.s.sol:DeployStoneFormAdvanced \
  --rpc-url $BSC_RPC_URL \
  --broadcast --verify \
  --etherscan-api-key $BSCSCAN_API_KEY -vvvv
```

---

## Key Design Decisions

**Why ECDSA signatures instead of on-chain whitelists?**
Gas-efficient KYC/whitelist enforcement. The backend signs authorized purchases off-chain — no gas cost to add/remove users, and the whitelist can scale to millions without storage costs.

**Why Sablier for vesting?**
Battle-tested protocol for token streaming. Users get an NFT representing their vesting position that they can track in the Sablier dashboard — no custom vesting UI needed.

**Why automatic tier progression?**
A single `purchaseTokens` call handles cross-tier purchases atomically. If a buyer sends enough collateral to fill Tier 0 and partially fill Tier 1, both tiers update in one transaction with correct pricing for each portion.

---

## License

MIT
