# White-Hack-Recover-Migration Process

## Overview Diagram

```mermaid
flowchart TB
    subgraph "Phase 1: Initial State"
        STV2[StakedTokenV2<br/>Original Contract]
        POOL[DistributionPool<br/>Shared Pool]
        USERS[Users with<br/>Staked Tokens]
        HACKER[Hacker Address<br/>0x8B6B00...]
        
        USERS -->|"Have staked tokens<br/>& units in pool"| STV2
        STV2 -->|"Tracks units"| POOL
        HACKER -->|"Has malicious units"| POOL
    end
    
    subgraph "Phase 2: Exploit (StremeRecover.exploit)"
        SR[StremeRecover<br/>Contract]
        ADMIN[Admin<br/>0x55C4C7...]
        
        ADMIN -->|"1. Grant ADMIN & MANAGER roles"| SR
        ADMIN -->|"2. Call exploit()"| SR
        SR -->|"3. stakeAndDelegate()<br/>Stake all tokens to self"| STV2
        SR -->|"4. updateMemberUnits()<br/>Remove hacker units"| POOL
        SR -->|"5. updateMemberUnits()<br/>Remove own units"| POOL
    end
    
    subgraph "Phase 3: Recovery (StremeRecover.recover)"
        SR2[StremeRecover<br/>Contract]
        TOKENS[Stakeable Tokens<br/>In StakedTokenV2]
        
        ADMIN -->|"Call recover()"| SR2
        SR2 -->|"1. reduceLockDuration(0)"| STV2
        SR2 -->|"2. unstake() all tokens"| STV2
        STV2 -->|"3. Transfer tokens"| TOKENS
        TOKENS -->|"4. Tokens in StremeRecover"| SR2
        SR2 -->|"5. setUnitDecimals(type(uint256).max)"| STV2
        STV2 -.->|"6. BROKEN<br/>Overflow on transfers"| STV2
        SR2 -->|"7. approve() tokens"| TOKENS
        SR2 -->|"8. createStakedToken()"| SFSPEC[StakingFactoryV2Special]
    end
    
    subgraph "Phase 4: Migration (User Claims)"
        STV2SPEC[StakedTokenV2Special<br/>New Contract]
        USER1[User 1]
        USER2[User 2]
        
        SFSPEC -->|"Creates & initializes"| STV2SPEC
        TOKENS -->|"All tokens transferred"| STV2SPEC
        STV2SPEC -->|"Reads from"| POOL
        STV2SPEC -->|"Reads from"| STV2
        USER1 -->|"claimStakeFromUnits()"| STV2SPEC
        USER2 -->|"claimStakeFromUnits()"| STV2SPEC
        STV2SPEC -->|"Mints tokens based on units"| USER1
        STV2SPEC -->|"Mints tokens based on units"| USER2
    end
    
    Phase1 --> Phase2
    Phase2 --> Phase3
    Phase3 --> Phase4
    
    style STV2 fill:#ffcccc
    style STV2SPEC fill:#ccffcc
    style SR fill:#ffffcc
    style POOL fill:#ccccff
    style HACKER fill:#ff0000,color:#fff
```

## Detailed Sequence Diagram

```mermaid
sequenceDiagram
    participant Admin
    participant SR as StremeRecover
    participant STV2 as StakedTokenV2<br/>(Original)
    participant Pool as DistributionPool
    participant Factory as StakingFactoryV2Special
    participant STV2S as StakedTokenV2Special<br/>(New)
    participant User

    Note over Admin,User: Phase 1: Setup & Exploit
    Admin->>STV2: Grant ADMIN & MANAGER roles to SR
    Admin->>SR: exploit([stTokens])
    SR->>STV2: stakeAndDelegate(SR, allTokens)
    STV2->>SR: Mint staked tokens
    SR->>Pool: updateMemberUnits(hacker, 0)
    SR->>Pool: updateMemberUnits(SR, 0)
    
    Note over Admin,User: Phase 2: Recovery
    Admin->>SR: recover([stTokens])
    SR->>STV2: reduceLockDuration(0)
    SR->>STV2: unstake(SR, allBalance)
    STV2->>SR: Transfer stakeable tokens
    SR->>STV2: setUnitDecimals(type(uint256).max)
    Note over STV2: Contract now broken<br/>(overflow on transfers)
    SR->>SR: approve(Factory, tokenBalance)
    SR->>Factory: createStakedToken(token, balance)
    
    Note over Admin,User: Phase 3: Factory Creates New Contract
    Factory->>STV2S: Clone & Initialize
    STV2S->>STV2: Read pool address
    STV2S->>STV2: Read lockDuration
    SR->>STV2S: Transfer all tokens
    Note over STV2S: New contract ready<br/>with all tokens
    
    Note over Admin,User: Phase 4: User Migration
    User->>STV2S: claimStakeFromUnits(user)
    STV2S->>STV2S: Check balanceOf(user) == 0
    STV2S->>STV2: depositTimestamps(user)
    STV2S->>Pool: getUnits(user)
    STV2S->>STV2S: _unitsToTokens(units)
    STV2S->>User: Mint tokens
    STV2S->>STV2S: Set depositTimestamps[user]
    Note over User: User has tokens<br/>with preserved timestamp
```

## State Transition Diagram

```mermaid
stateDiagram-v2
    [*] --> OriginalState: Deploy contracts
    
    OriginalState: StakedTokenV2<br/>- Users staked<br/>- Units in pool<br/>- Hacker has units
    
    OriginalState --> Exploited: StremeRecover.exploit()
    Exploited: StakedTokenV2<br/>- All tokens staked to SR<br/>- Hacker units removed<br/>- SR units removed
    
    Exploited --> Recovered: StremeRecover.recover()
    Recovered: StakedTokenV2<br/>- Lock duration = 0<br/>- All tokens unstaked<br/>- unitDecimals = MAX<br/>- BROKEN (overflow)
    
    Recovered --> NewContractCreated: Factory.createStakedToken()
    NewContractCreated: StakedTokenV2Special<br/>- All tokens transferred<br/>- References original pool<br/>- References original STV2<br/>- Ready for claims
    
    NewContractCreated --> UserClaims: Users call claimStakeFromUnits()
    UserClaims: StakedTokenV2Special<br/>- Users mint tokens<br/>- Timestamps preserved<br/>- Units converted to tokens
    
    UserClaims --> [*]: All users migrated
```

## Data Flow Diagram

```mermaid
flowchart LR
    subgraph "Original State"
        A[User Staked Tokens<br/>in StakedTokenV2]
        B[User Units<br/>in DistributionPool]
        C[User Deposit Timestamp<br/>in StakedTokenV2]
    end
    
    subgraph "Recovery Process"
        D[StremeRecover<br/>Collects all tokens]
        E[StakingFactoryV2Special<br/>Creates new contract]
    end
    
    subgraph "New State"
        F[StakedTokenV2Special<br/>Holds all tokens]
        G[DistributionPool<br/>Still has user units]
        H[Original StakedTokenV2<br/>Still has timestamps]
    end
    
    subgraph "User Claim"
        I[User calls<br/>claimStakeFromUnits]
        J[Reads units from Pool]
        K[Reads timestamp from<br/>Original StakedTokenV2]
        L[Converts units to tokens<br/>units * 10^18]
        M[Mints tokens to user<br/>Preserves timestamp]
    end
    
    A --> D
    D --> E
    E --> F
    B --> G
    C --> H
    F --> I
    G --> J
    H --> K
    J --> L
    K --> L
    L --> M
    
    style A fill:#ffcccc
    style F fill:#ccffcc
    style D fill:#ffffcc
    style E fill:#ffffcc
```

## Key Operations Breakdown

### 1. Exploit Phase
- **Purpose**: Take control of all tokens and clean up malicious units
- **Actions**:
  1. Stake all tokens from StakedTokenV2 to StremeRecover
  2. Remove hacker's units from pool
  3. Remove StremeRecover's own units (so stakers get correct amount)

### 2. Recovery Phase
- **Purpose**: Extract tokens, break old contract, create new one
- **Actions**:
  1. Reduce lock duration to 0
  2. Unstake all tokens to StremeRecover
  3. Break original contract (set unitDecimals to max)
  4. Create new StakedTokenV2Special with all tokens

### 3. Migration Phase
- **Purpose**: Allow users to claim their tokens in new contract
- **Actions**:
  1. User calls `claimStakeFromUnits()`
  2. Contract reads user's units from shared pool
  3. Contract reads user's original deposit timestamp
  4. Contract mints tokens: `units * (10 ** unitDecimals)`
  5. Contract preserves original timestamp for lock calculations

## Critical Invariants

1. **Pool Units Preserved**: The DistributionPool still has all user units after recovery
2. **Timestamps Preserved**: Original StakedTokenV2 still has deposit timestamps (read-only)
3. **Token Conservation**: All tokens from original contract end up in new contract
4. **One-Time Claim**: Users can only claim once (balanceOf == 0 check)
5. **Unit Conversion**: `tokens = units * (10 ** unitDecimals)` where unitDecimals = 18

