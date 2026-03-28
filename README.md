# VegaVoting Protocol (Foundry + Sepolia)

Репозиторий реализует систему on-chain голосования со стейкингом токена `VV` и NFT-результатом после финализации.

## Реализовано

### Контракты
- **VVToken** (`ERC20`, OpenZeppelin v5) — токен для стейкинга и голосования.
- **Voting** — контракт управления голосованием:
  - только админ (`owner`) может создавать голосования;
  - уникальный `bytes32 voteId`;
  - параметры голосования: `deadline`, `votingPowerThreshold`, `description`;
  - участники стейкают `A_i` VV на `D_i ∈ [1..4]` дней;
  - voting power рассчитывается как:
    - `VP = Σ (A_i * Dremain^2)`
  - голосование `yes/no` с использованием текущей voting power;
  - **early finalize** если `yesVotes >= threshold`;
  - finalize после `deadline`;
  - `pause/unpause` (emergency control).
- **VoteResultNFT** (`ERC721`, OpenZeppelin v5) — при финализации минтится NFT с итогами голосования (on-chain metadata).

---

## Структура проекта

### Контракты
- `src/VVToken.sol`
- `src/Voting.sol`
- `src/VoteResultNFT.sol`

### Скрипты
- `script/Deploy.s.sol` — деплой всех контрактов.
- `script/SetupDemoVote.s.sol` — создаёт голосование и делает базовый демо flow.
- `script/CastVote.s.sol` — approve + stake + vote одним пользователем.
- `script/RunTwoPartyFlow.s.sol` — end-to-end сценарий с 2 участниками.

### Тесты
`test/Voting.t.sol` покрывает:
- доступ только admin на `createVote`;
- early finalize при достижении threshold;
- double-vote protection;
- finalize после deadline;
- withdraw после unlock;
- decaying voting power;
- pause-блокировку stake/vote.

---

## Установка

```bash
# установить Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# зависимости
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit
````

---

## Сборка и тесты

```bash
forge build
forge test -vv
```

---

## Деплой в Sepolia

### Env

```bash
export RPC_URL="https://sepolia.infura.io/v3/<KEY>"
export PRIVATE_KEY="0x..." # deployer/admin
export INITIAL_SUPPLY="1000000000000000000000000" # 1m VV
```

### Deploy

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvvv
```

Сохраните адреса из логов:

* `VVToken`
* `Voting`
* `VoteResultNFT`

---

## Демо: голосование с двумя участниками

### Env

```bash
export RPC_URL="https://sepolia.infura.io/v3/<KEY>"

export ADMIN_PRIVATE_KEY="0x..."
export VOTER1_PRIVATE_KEY="0x..."
export VOTER2_PRIVATE_KEY="0x..."

export VV_TOKEN_ADDRESS="0x..."
export VOTING_ADDRESS="0x..."
export RESULT_NFT_ADDRESS="0x..."

export VOTE_ID="0x1111111111111111111111111111111111111111111111111111111111111111"
export DESCRIPTION="Should VegaVoting proposal #1 pass?"

export STAKE_AMOUNT="100000000000000000000" # 100 VV
export LOCK_DAYS="4"
export DEADLINE_OFFSET="86400" # 1 day

# 2 участника * 100 * 4^2 = 3200 voting power
export VOTING_POWER_THRESHOLD="3200000000000000000000"
```

### Полный pipeline

```bash
forge script script/RunTwoPartyFlow.s.sol:RunTwoPartyFlow \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvvv
```

Скрипт:

* создаёт vote;
* раздаёт VV двум участникам;
* оба участника делают `approve -> stake -> vote(true)`;
* при достижении threshold голосование финализируется автоматически;
* минтится NFT результата.

---

## Альтернатива: по шагам

### 1) Setup vote

```bash
forge script script/SetupDemoVote.s.sol:SetupDemoVote \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvvv
```

### 2) Vote от каждого участника

```bash
export VOTER_PRIVATE_KEY="$VOTER1_PRIVATE_KEY"
forge script script/CastVote.s.sol:CastVote --rpc-url "$RPC_URL" --broadcast -vvvv

export VOTER_PRIVATE_KEY="$VOTER2_PRIVATE_KEY"
forge script script/CastVote.s.sol:CastVote --rpc-url "$RPC_URL" --broadcast -vvvv
```

---

## Полезные ссылки (Sepolia)

После запуска откройте:

* Voting contract: `https://sepolia.etherscan.io/address/<VOTING_ADDRESS>`
* Token contract: `https://sepolia.etherscan.io/address/<VV_TOKEN_ADDRESS>`
* NFT contract: `https://sepolia.etherscan.io/address/<RESULT_NFT_ADDRESS>`

На вкладке **Events** должны быть видны события:

* `VoteCreated(...)`
* `Staked(...)`
* `Voted(...)`
* `VoteFinalized(...)`
* `Transfer(0x0, owner, tokenId)` (mint NFT)

---

## Design Notes

* voting power уменьшается по мере приближения `unlockAt`, т.к. зависит от `Dremain^2`.
* early finalize происходит автоматически внутри `vote()`, если достигнут threshold.
* результат фиксируется NFT и не может быть изменён.

