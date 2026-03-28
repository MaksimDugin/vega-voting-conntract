# VegaVoting Protocol (Foundry + Sepolia)

Репозиторий реализует систему голосования со стейкингом токена `VV` и NFT-результатом по финализированному голосованию.

## Что реализовано по ТЗ

- `VVToken` (ERC20, OpenZeppelin v5): токен для стейкинга/голосования.
- `Voting`:
  - только админ (`owner`) создаёт голосование;
  - уникальный `bytes32` id;
  - параметры: `deadline`, `votingPowerThreshold`, `description`;
  - стейкинг `A_i` на `D_i ∈ [1..4]` дней;
  - voting power: `sum(A_i * Dremain_i^2)` (с нормализацией на `days^2`);
  - голосование yes/no со стейкнутой силой;
  - early finalize при достижении `yesVotes >= threshold`;
  - finalize после `deadline`;
  - отдельная роль `finalizer` + owner по умолчанию;
  - emergency controls: `pause/unpause`.
- `VoteResultNFT` (ERC721, OpenZeppelin v5): при финализации минтится NFT с on-chain metadata результата.
- Деплой и сценарии через Foundry scripts.
- Расширенный тестовый набор.

## Контракты

- `src/VVToken.sol`
- `src/VoteResultNFT.sol`
- `src/Voting.sol`

## Скрипты

- `script/Deploy.s.sol` — деплой 3 контрактов.
- `script/SetupDemoVote.s.sol` — базовый сценарий создания голосования + два голоса.
- `script/CastVote.s.sol` — отдельный скрипт для одного участника (approve+stake+vote).
- `script/RunTwoPartyFlow.s.sol` — end-to-end pipeline с двумя участниками и выводом метрик/итогов.

## Тесты

`test/Voting.t.sol` покрывает:

- access control на create;
- валидации createVote;
- early finalize по threshold;
- сценарий с двумя голосующими;
- double-vote protection;
- finalize после deadline;
- ограничения finalizer роли;
- grant finalizer;
- withdraw после unlock;
- decaying voting power;
- pause-блокировку stake/vote.

---

## Установка

```bash
# Foundry
bash foundry-install.sh
source ~/.bashrc
foundryup

# зависимости
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit
```

## Сборка и тесты

```bash
forge build
forge test -vv
```

---

## Деплой в Sepolia

```bash
export RPC_URL="https://sepolia.infura.io/v3/<KEY>"
export ETHERSCAN_API_KEY="<KEY>"
export PRIVATE_KEY="0x..." # admin/deployer
export INITIAL_SUPPLY="1000000000000000000000000" # 1m VV
```

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify \
  -vvvv
```

Сохраните адреса из логов:
- `VVToken`
- `VoteResultNFT`
- `Voting`

---


## Отдельная верификация после деплоя (Sepolia)

Если деплой уже сделан и `--verify` не сработал, используйте отдельный скрипт:

```bash
export ETHERSCAN_API_KEY="<KEY>"
export DEPLOYER_ADDRESS="0x..."       # owner, который был передан в конструкторы
export VV_TOKEN_ADDRESS="0x..."
export RESULT_NFT_ADDRESS="0x..."
export VOTING_ADDRESS="0x..."
export INITIAL_SUPPLY="1000000000000000000000000"  # как на деплое (по умолчанию 1_000_000e18)
export CHAIN="sepolia"
export VERIFIER="etherscan"

bash script/VerifySepolia.sh
```

Эквивалент одной ручной команды (как в вашем примере):

```bash
forge verify-contract --watch --chain sepolia \
  <CONTRACT_ADDRESS> src/ContractFile.sol:ContractName \
  --verifier etherscan --etherscan-api-key "$ETHERSCAN_API_KEY"
```

Скрипт отправляет 3 `forge verify-contract` запроса с корректно ABI-encoded constructor args:
- `VVToken(address,uint256)`
- `VoteResultNFT(address)`
- `Voting(address,address,address)`

Если был другой `INITIAL_SUPPLY` при деплое, обязательно передайте именно его, иначе verification будет fail.

## Голосование с двумя участниками (и подтверждение через Etherscan)

Ниже детальный flow под ваш кейс с двумя private key участников.

### 1) Подготовить окружение

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
# для ранней финализации (2 участника * 100 * 4^2 = 3200)
export VOTING_POWER_THRESHOLD="3200000000000000000000"
```

### 2) Прогнать полный pipeline

```bash
forge script script/RunTwoPartyFlow.s.sol:RunTwoPartyFlow \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvvv
```

Скрипт:
- создаёт vote;
- переводит участникам VV;
- оба участника делают `approve -> stake -> vote(true)`;
- печатает метрики голосования и данные NFT, если голосование уже final.

### 3) Проверить транзакции на Etherscan

Откройте в браузере:
- `https://sepolia.etherscan.io/address/$VOTING_ADDRESS`
- `https://sepolia.etherscan.io/address/$VV_TOKEN_ADDRESS`
- `https://sepolia.etherscan.io/address/$RESULT_NFT_ADDRESS`

На вкладке **Transactions / Events** подтвердите события:

1. `VoteCreated(voteId, creator, deadline, threshold, description)`
2. у каждого участника:
   - `Approval(voter, voting, stakeAmount)` в `VVToken`
   - `Staked(voter, stakeId, amount, unlockAt)`
   - `Voted(voteId, voter, true, votingPower)`
3. когда достигнут threshold или после deadline:
   - `VoteFinalized(voteId, passed, yesVotes, noVotes, nftTokenId)`
4. в NFT-контракте:
   - `Transfer(0x0, owner, tokenId)` — mint result NFT.

> Для отчёта обычно достаточно ссылок на tx hashes + скриншот события finalization.

---

## Альтернативно: по шагам отдельными скриптами

### Создать голосование + раздать токены

```bash
forge script script/SetupDemoVote.s.sol:SetupDemoVote \
  --rpc-url "$RPC_URL" \
  --broadcast \
  -vvvv
```

### Отдельный скрипт для каждого участника

```bash
export VOTER_PRIVATE_KEY="$VOTER1_PRIVATE_KEY"
forge script script/CastVote.s.sol:CastVote --rpc-url "$RPC_URL" --broadcast -vvvv

export VOTER_PRIVATE_KEY="$VOTER2_PRIVATE_KEY"
forge script script/CastVote.s.sol:CastVote --rpc-url "$RPC_URL" --broadcast -vvvv
```

---

## Замечания по дизайну

- finalize сделан on-chain без оффчейн-агентов; вызвать может owner или назначенный finalizer.
- ранняя финализация автоматически происходит прямо в `vote()` при достижении `yesVotes >= threshold`.
- NFT результата минтится один раз на `tokenId = uint256(voteId)`.

## Extra (system design)

Логика протокола:

1. **Asset layer**: `VVToken` (ERC20).
2. **Governance/staking layer**: `Voting` хранит stake-позиции и агрегирует voting power.
3. **Result layer**: `VoteResultNFT` фиксирует неизменяемый итог в виде NFT.
4. **Ops layer**: Foundry scripts для деплоя, голосования и реплицируемых демо-flow.




## Частые ошибки (по реальному запуску)

1. `stake(..., 7)` -> `InvalidDuration`: допустимо только `1..4` дня.
2. `cast call $VOTING "stakes(address)" ...` не сработает: `stakes` приватный mapping. Используйте:
   - `stakeCount(address)`
   - `getStake(address,uint256)`
3. `createVote(string,uint256)` не существует. Верная сигнатура:
   - `createVote(bytes32,uint64,uint256,string)`
4. `getVoteCount()` теперь доступен как helper (и `voteIdAt(index)`).
5. `tokenOfOwnerByIndex(...)` работает, потому что `VoteResultNFT` поддерживает enumerable.
6. `finalizeVote` может ревертить `VoteAlreadyFinalized`, потому что контракт финализирует vote автоматически в `vote()` при `yesVotes >= threshold`.

### Минимальный ручной сценарий через cast (2 участника)

```bash
# 0) env
export RPC_URL="https://sepolia.infura.io/v3/<KEY>"
export ADMIN_PK="0x..."
export V1_PK="0x..."
export V2_PK="0x..."

export VVTOKEN="0x..."
export VOTING="0x..."
export VOTERESULTNFT="0x..."

export ADMIN_ADDR=$(cast wallet address --private-key $ADMIN_PK)
export V1_ADDR=$(cast wallet address --private-key $V1_PK)
export V2_ADDR=$(cast wallet address --private-key $V2_PK)

# 1) раздать токены двум участникам (делает admin)
cast send $VVTOKEN "transfer(address,uint256)" $V1_ADDR 100000000000000000000 --private-key $ADMIN_PK --rpc-url $RPC_URL
cast send $VVTOKEN "transfer(address,uint256)" $V2_ADDR 100000000000000000000 --private-key $ADMIN_PK --rpc-url $RPC_URL

# 2) создать vote
export VOTE_ID=$(cast keccak "vote-two-users-1")
export DEADLINE=$(($(date +%s) + 86400))
export THRESHOLD=3200000000000000000000
cast send $VOTING "createVote(bytes32,uint64,uint256,string)" $VOTE_ID $DEADLINE $THRESHOLD "Should pass?" --private-key $ADMIN_PK --rpc-url $RPC_URL

# 3) voter1 approve+stake+vote
cast send $VVTOKEN "approve(address,uint256)" $VOTING 100000000000000000000 --private-key $V1_PK --rpc-url $RPC_URL
cast send $VOTING "stake(uint256,uint256)" 100000000000000000000 4 --private-key $V1_PK --rpc-url $RPC_URL
cast send $VOTING "vote(bytes32,bool)" $VOTE_ID true --private-key $V1_PK --rpc-url $RPC_URL

# 4) voter2 approve+stake+vote
cast send $VVTOKEN "approve(address,uint256)" $VOTING 100000000000000000000 --private-key $V2_PK --rpc-url $RPC_URL
cast send $VOTING "stake(uint256,uint256)" 100000000000000000000 4 --private-key $V2_PK --rpc-url $RPC_URL
cast send $VOTING "vote(bytes32,bool)" $VOTE_ID true --private-key $V2_PK --rpc-url $RPC_URL

# 5) проверить итог
cast call $VOTING "getVote(bytes32)" $VOTE_ID --rpc-url $RPC_URL
cast call $VOTERESULTNFT "balanceOf(address)" $ADMIN_ADDR --rpc-url $RPC_URL
cast call $VOTERESULTNFT "tokenOfOwnerByIndex(address,uint256)" $ADMIN_ADDR 0 --rpc-url $RPC_URL
```
