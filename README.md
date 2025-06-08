# On-chain DAO for Community Investment
A decentralized autonomous organization (DAO) for community-driven investments built on Stacks blockchain.

## 🎯 Features

- 💰 Deposit funds into the DAO
- 📝 Create investment proposals
- 🗳️ Vote on proposals based on stake
- ⚡ Execute successful proposals automatically

## 🚀 How to Use

1. **Deposit Funds**
   - Call `deposit` function with STX amount
   - Your voting power increases with your deposit

2. **Create Proposal**
   - Must have minimum stake (1M microSTX)
   - Specify recipient and amount
   - Proposals last for 144 blocks (~24 hours)

3. **Vote on Proposals**
   - Each member can vote once per proposal
   - Voting power = (deposit amount * 100) / 100
   - Votes can be YES or NO

4. **Execute Proposals**
   - Automatic execution after voting period
   - Requires more YES than NO votes
   - Funds transferred to recipient if successful

## 📋 Functions

- `deposit`: Add funds to the DAO
- `create-proposal`: Submit new investment proposal
- `vote`: Cast vote on active proposal
- `execute-proposal`: Complete successful proposals
- `get-proposal`: View proposal details
- `get-user-balance`: Check member's balance

## 🔒 Security

- Time-locked voting periods
- Stake-based voting power
- Protected execution mechanics
```
