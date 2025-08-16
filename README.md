# 🎫 Subscription Access Token

A Clarity smart contract implementing time-bound utility tokens for subscription-based access control on the Stacks blockchain.

## 🚀 Features

- ⏱️ **Time-bound subscriptions** with automatic expiration
- 🎚️ **Multi-tier access levels** (Basic, Premium, Enterprise)
- 🎟️ **Access tokens** for temporary resource access
- 💰 **Flexible pricing** with STX payments
- 🔄 **Auto-renewal** functionality
- 🎁 **Gift subscriptions** to other users
- 📊 **Revenue tracking** and analytics
- ⬆️ **Subscription upgrades** between tiers
- 🎯 **Bulk operations** for efficiency

## 📋 Subscription Tiers

| Tier | 📦 Name | 💰 Price | ⏰ Duration | 🔑 Access Level |
|------|---------|----------|-------------|-----------------|
| 1 | Basic | 1 STX | 1008 blocks (~1 week) | Level 1 |
| 2 | Premium | 2.5 STX | 2016 blocks (~2 weeks) | Level 2 |
| 3 | Enterprise | 5 STX | 4032 blocks (~1 month) | Level 3 |

## 🛠️ Usage

### Initialize Contract

```clarity
;; Deploy and initialize subscription tiers
(contract-call? .subscription-access-token initialize-tiers)
```

### Subscribe to a Tier

```clarity
;; Subscribe to Basic tier (tier 1)
(contract-call? .subscription-access-token subscribe u1)

;; Subscribe to Premium tier (tier 2)
(contract-call? .subscription-access-token subscribe u2)

;; Subscribe to Enterprise tier (tier 3)
(contract-call? .subscription-access-token subscribe u3)
```

### Check Subscription Status

```clarity
;; Check if user has active Basic subscription
(contract-call? .subscription-access-token is-subscription-active 'SP1234567890 u1)

;; Get detailed subscription status
(contract-call? .subscription-access-token get-subscription-status 'SP1234567890 u1)

;; Get all active subscriptions for a user
(contract-call? .subscription-access-token get-user-active-subscriptions 'SP1234567890)
```

### Generate and Use Access Tokens

```clarity
;; Generate an access token for your active subscription
(contract-call? .subscription-access-token generate-access-token u1)

;; Use an access token (marks it as used)
(contract-call? .subscription-access-token use-access-token u1)

;; Check if token is still valid
(contract-call? .subscription-access-token is-token-valid u1)
```

### Subscription Management

```clarity
;; Renew subscription
(contract-call? .subscription-access-token renew-subscription u1)

;; Enable auto-renewal
(contract-call? .subscription-access-token set-auto-renew u1 true)

;; Upgrade from Basic to Premium
(contract-call? .subscription-access-token upgrade-subscription u1 u2)

;; Cancel subscription
(contract-call? .subscription-access-token cancel-subscription u1)

;; Gift a subscription to someone
(contract-call? .subscription-access-token gift-subscription 'SP1234567890 u1)
```

### Access Control

```clarity
;; Validate user has required access level
(contract-call? .subscription-access-token validate-access 'SP1234567890 u2 u1)

;; Batch validate multiple users
(contract-call? .subscription-access-token batch-validate-users 
  (list 'SP1111111111 'SP2222222222 'SP3333333333) u1 u1)
```

### Analytics & Admin

```clarity
;; Get contract statistics
(contract-call? .subscription-access-token get-contract-stats)

;; Get revenue stats for a period
(contract-call? .subscription-access-token get-revenue-stats u1)

;; Preview subscription costs
(contract-call? .subscription-access-token preview-subscription-cost u2 u500)
```

## 🔧 Admin Functions

```clarity
;; Extend subscription (owner only)
(contract-call? .subscription-access-token extend-subscription 'SP1234567890 u1 u500)

;; Emergency extend (owner only)
(contract-call? .subscription-access-token emergency-extend-subscription 'SP1234567890 u1 u1000)

;; Withdraw revenue (owner only)
(contract-call? .subscription-access-token withdraw-revenue u1000000)
```

## 🏗️ Architecture

The contract uses several key data structures:

- **📋 Subscriptions Map**: Tracks user subscriptions with expiry times
- **🎚️ Subscription Tiers Map**: Defines tier pricing and access levels  
- **🎟️ Access Tokens Map**: Manages temporary access tokens
- **📊 Revenue Tracking Map**: Records revenue by time periods

## 🧪 Testing

```bash
# Run contract tests
clarinet test

# Check contract syntax
clarinet check

# Start local development environment
clarinet console
```

## 🚦 Error Codes

| Code | Description |
|------|------------|
| 100 | Unauthorized access |
| 101 | Subscription expired |
| 102 | Invalid amount |
| 103 | Subscription not found |
| 104 | Already subscribed |
| 105 | Invalid tier |
| 106 | Insufficient payment |

## 💡 Use Cases

- 🔐 **API Access Control**: Limit API calls based on subscription tier
- 📱 **Premium Features**: Unlock advanced functionality for subscribers
- 🎮 **Gaming**: Time-limited game passes or premium content access
- 📰 **Content Platforms**: Subscription-based article or media access
- 🛠️ **SaaS Tools**: Feature gating and usage limits
- 🎓 **Educational**: Course access and learning materials

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly with `clarinet test`
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details.
