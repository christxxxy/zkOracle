# ZK-Oracle: Consensus-Based Zero-Knowledge Proof Verification Network

A decentralized oracle network built on Stacks blockchain that enables consensus-based verification of zero-knowledge proofs across multiple cryptographic protocols.

## Overview

ZK-Oracle provides a trustless mechanism for verifying zero-knowledge proofs through a network of bonded validators who reach consensus through voting. The system supports multiple ZK proof families and incentivizes honest participation through economic bonding and reward mechanisms.

## Key Features

- **Multi-Protocol Support**: Supports STARK, SNARK, Bulletproof, and PLONK-based zero-knowledge proofs
- **Consensus-Based Verification**: Multiple validators vote on proof validity to reach consensus
- **Economic Security**: Validators must bond STX tokens and are rewarded for honest behavior
- **Reputation System**: Tracks validator and submitter performance over time
- **Flexible Configuration**: Customizable consensus thresholds and protocol parameters

## Architecture

### Core Components

1. **Proof Submissions**: Users submit ZK proofs with associated rewards for verification
2. **Validator Network**: Bonded validators specialized in different proof systems
3. **Consensus Mechanism**: Vote-based consensus with configurable thresholds
4. **Reward Distribution**: Economic incentives for honest participation

### Supported Protocol Families

| Protocol | Base Reward | Voting Period | Expertise Required |
|----------|-------------|---------------|-------------------|
| stark-based | 2 STX | 150 blocks | Yes |
| snark-based | 1.5 STX | 120 blocks | Yes |
| bulletproof | 1 STX | 100 blocks | No |
| plonk-based | 1.8 STX | 140 blocks | Yes |

## Getting Started

### Prerequisites

- Stacks wallet with STX tokens
- Understanding of zero-knowledge proofs
- For validators: Technical expertise in supported ZK protocols

### Network Initialization

The oracle admin must first initialize the network:

```clarity
(contract-call? .zk-oracle initialize-oracle-network)
```

### Joining as a Validator

To become a validator, you need to:

1. **Bond STX tokens** (minimum 3 STX)
2. **Specify your specializations** in ZK protocols
3. **Provide a validator name**

```clarity
(contract-call? .zk-oracle join-validator-network 
  "ZK-Expert-Validator"
  (list "stark-based" "snark-based"))
```

### Submitting Proofs for Verification

Users can submit ZK proofs for consensus verification:

```clarity
(contract-call? .zk-oracle submit-for-consensus
  "stark-based"                    ;; Protocol family
  0x1234...                        ;; Proof commitment (32 bytes)
  0x5678...                        ;; Witness inputs (up to 1024 bytes)
  0x9abc...                        ;; Verification parameters (up to 512 bytes)
  u2000000)                        ;; Consensus reward (2 STX)
```

### Validator Voting

Validators can vote on submitted proofs:

```clarity
(contract-call? .zk-oracle cast-vote
  u1                               ;; Submission ID
  true                             ;; Vote (true = valid, false = invalid)
  u95)                             ;; Confidence level (0-100)
```

### Finalizing Consensus

Once consensus is reached, anyone can finalize the result:

```clarity
(contract-call? .zk-oracle finalize-consensus u1)
```

## Economic Model

### Validator Economics

- **Initial Bond**: 3 STX required to join as validator
- **Voting Power**: Can be increased by bonding additional STX (1 STX = +1 voting power)
- **Rewards**: Share of consensus rewards based on correct votes
- **Slashing**: Reputation penalties for incorrect votes

### Submission Economics

- **Base Rewards**: Minimum rewards based on protocol complexity
- **Locked Funds**: Submitters lock reward amount until consensus
- **Refunds**: Expired submissions can be reclaimed by submitters

## Consensus Mechanism

### Voting Process

1. **Submission**: Proof submitted with locked reward
2. **Voting Period**: Validators cast weighted votes within deadline
3. **Consensus Check**: Minimum threshold of votes required
4. **Finalization**: Rewards distributed to winning validators

### Consensus Requirements

- **Default Threshold**: 3 validators minimum for consensus
- **Vote Types**: Binary (valid/invalid) with confidence levels
- **Weighted Voting**: Based on validator's bonded amount and reputation

## Query Functions

### Submission Information
```clarity
(get-submission-details u1)          ;; Get submission details
(has-consensus-been-reached u1)      ;; Check if consensus reached
```

### Validator Information
```clarity
(get-validator-info 'SP123...)       ;; Get validator stats
(get-vote-details u1 'SP123...)     ;; Get specific vote details
```

### Network Status
```clarity
(get-consensus-threshold)            ;; Current consensus threshold
(get-protocol-config "stark-based")  ;; Protocol configuration
```

## Security Considerations

### Validator Security
- Validators must maintain technical expertise in their specialized protocols
- Economic bonding ensures skin in the game
- Reputation system tracks long-term performance

### Submission Security
- Proof commitments prevent front-running
- Time-locked voting periods ensure fair evaluation
- Multiple validators reduce single points of failure

### Network Security
- Admin controls for emergency situations (halt/restart network)
- Configurable parameters for network governance
- Fee withdrawal mechanisms for network sustainability

## Error Codes

| Code | Error | Description |
|------|-------|-------------|
| 500 | ACCESS_FORBIDDEN | Insufficient permissions |
| 501 | SUBMISSION_NOT_FOUND | Invalid submission ID |
| 502 | INVALID_SUBMISSION | Malformed submission data |
| 503 | SUBMISSION_EXISTS | Duplicate submission or vote |
| 504 | BOND_INSUFFICIENT | Insufficient bonded amount |
| 505 | VALIDATOR_INACTIVE | Validator not active |
| 506 | PROTOCOL_UNSUPPORTED | Unknown protocol family |

## Administrative Functions

Network administrators can:

- **Update consensus thresholds**
- **Add new protocol families**
- **Halt/restart the network** in emergencies
- **Withdraw network fees**

## Future Enhancements

- **Slashing mechanisms** for malicious validators
- **Automated reward distribution** improvements
- **Cross-chain proof verification** support
- **Advanced reputation algorithms**
- **Governance token** for decentralized administration

## Contributing

This is an open-source project. Contributions are welcome for:

- Additional ZK protocol support
- Security improvements
- Gas optimization
- Documentation enhancements
