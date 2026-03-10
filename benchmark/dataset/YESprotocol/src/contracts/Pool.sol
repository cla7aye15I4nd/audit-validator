// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";

interface IStakePool {
    function depositReward(uint256 amount) external;
}

interface IToken {
    function pair() external view returns (address);
}

contract Pool is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");
    uint256 public constant USDT_DECIMALS = 1e18;
    uint256 public constant MAX_REWARD_USDT = 5000000 ether;
    uint256 public constant ROUND_TX_COUNT = 8; // Number of transactions per round
    address public token;
    address public stakePool;
    bool public openFreeTrade; // Whether free trading is open
    FeeInfo public feeInfo;
    mapping(uint256 roundAmount => uint256 roundId) public roundIds; // Record current round for each amount
    mapping(uint256 roundAmount => mapping(uint256 roundId => RoundInfo)) public roundInfos; // Record transaction info for each round
    mapping(uint256 roundAmount => bool opened) public openRoundAmounts; // Allowed round amounts
    mapping(uint256 lastDigit => mapping(uint256 roundId => BetRoundInfo)) public betRoundInfos;
    mapping(uint256 lastDigit => BetPoolInfo) public betPoolInfos; // Pool info for last digit 8/9
    mapping(uint256 lastDigit => uint256 roundId) public betRoundIds; // Record current round for each amount
    mapping(uint256 lastDigit => uint16[7] levelPoints) public betLevelPoints; // Record level distribution ratio for each amount

    event Buy(address indexed buyer, uint256 tokenAmount, uint256 usdtAmount);
    event Sell(address indexed seller, uint256 feeAmount);
    event Play(address indexed buyer, uint256 indexed roundId, uint256 indexed txId, uint256 tokenAmount, uint256 lockAmount, uint256 usdtAmount);
    event RoundClosed(uint256 indexed roundAmount, uint256 indexed roundId, uint256 settleBlockNumber);
    event RoundSettled(uint256 indexed roundAmount, uint256 indexed roundId, bytes32 settleBlockHash);
    event Win(address indexed winner, uint256 roundAmount, uint256 roundId, uint256 txId, uint256 winAmount);
    event FeeAllocated(uint256 amount, uint256 totalAllocated, uint256 totalSellFee, uint256 timestamp);

    event Bet(
        address indexed buyer,
        uint256 indexed roundId,
        uint256 indexed txId,
        uint256 tokenAmount,
        uint256 lockAmount,
        uint256 usdtAmount,
        bytes32 betHash
    );
    event BetWin(address indexed winner, uint256 roundAmount, uint256 roundId, uint256 txId, uint256 winAmount, uint256 level);

    struct BetTransaction {
        address to; // Receiver address
        uint8 luckyLevel; // Lucky level 0-7
        uint256 tokenAmount;
        uint256 usdtAmount;
        uint256 lockAmount;
        uint256 luckyAmount;
        bytes32 betHash; // Bet hash
        uint8[] betNumbers; // Bet numbers
    }

    struct BetRoundInfo {
        uint256 roundAmount; // Round amount
        uint256 totalLockAmount;
        uint256 settleBlockNumber; // Settlement block number
        uint256 normalPrizeAmount; // Normal prize pool
        uint256 specialPrizeAmount; // Special prize pool
        bytes32 settleBlockHash; // Settlement block hash
        BetTransaction[ROUND_TX_COUNT] transactions; // Fixed length array
        uint8 txCount; // Current transaction count
        uint8[] winNumbers; // Winning numbers
        mapping(uint8 level => uint8[]) levelWinners; // Winners for each level
    }

    struct BetPoolInfo {
        uint256 prizeAmount; // Prize pool amount
        uint256 specialPrizeAmount; // Special prize pool amount
        uint256 allocatePoint; // Total allocation points
    }

    struct BuyTransaction {
        bool isContributor; // Whether is a contributor
        address to; // Receiver address
        uint256 tokenAmount;
        uint256 usdtAmount;
        uint256 lockAmount;
        uint256 luckyAmount;
    }

    struct RoundInfo {
        uint256 totalLockAmount;
        uint256 settleBlockNumber; // Settlement block number
        bytes32 settleBlockHash; // Settlement block hash
        BuyTransaction[ROUND_TX_COUNT] transactions; // Fixed length array
        uint8 txCount; // Current transaction count
    }

    struct FeeInfo {
        uint256 totalSellFee;
        uint256 allocatedFee;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SETTLER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);

        token = 0x7465bD41AE03818250aF58E1d826396B89616fd0;
        _grantRole(SETTLER_ROLE, 0xe8Ac079c6965b0b68D83CDD3f1a2716bDc5dde98);
        _grantRole(OPERATOR_ROLE, 0xe8Ac079c6965b0b68D83CDD3f1a2716bDc5dde98);
        uint16[7] memory pool8LevelPoints = [uint16(0), 75, 20, 5, 0, 0, 0];
        uint16[7] memory pool9LevelPoints = [uint16(0), 0, 40, 30, 20, 7, 3];
        betLevelPoints[8] = pool8LevelPoints;
        betLevelPoints[9] = pool9LevelPoints;
    }

    modifier onlyToken() {
        require(msg.sender == token, "Caller is not the token contract");
        _;
    }

    function setToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_token != address(0), "Invalid token address");
        token = _token;
    }

    function setStakePool(address _stakePool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_stakePool != address(0), "Invalid stake pool address");
        stakePool = _stakePool;
    }

    function setOpenFreeTrade(bool _openFreeTrade) external onlyRole(DEFAULT_ADMIN_ROLE) {
        openFreeTrade = _openFreeTrade;
    }

    function getBetHash(address to, uint256 tokenAmount, uint256 usdtAmount) public view returns (bytes32) {
        return keccak256(abi.encodePacked(to, tokenAmount, usdtAmount, gasleft(), block.prevrandao, block.timestamp, blockhash(block.number - 1)));
    }

    function getTokenPrice() public view returns (uint256 price) {
        address _token = token;
        address pair = IToken(_token).pair();
        IUniswapV2Pair mainPair = IUniswapV2Pair(pair);
        (uint112 reserve0, uint112 reserve1, ) = mainPair.getReserves();
        address token1 = mainPair.token1();
        if (_token == token1) {
            // token1 is this token
            price = (uint256(reserve0) * 1e18) / uint256(reserve1); // USDT per token
        } else {
            // token0 is this token
            price = (uint256(reserve1) * 1e18) / uint256(reserve0); // USDT per token
        }
    }

    function allocSellFee(uint256 amount) external onlyRole(OPERATOR_ROLE) {
        // Allocate sell fee logic here
        require(stakePool != address(0), "Stake pool not set");
        uint256 totalSellFee = feeInfo.totalSellFee;
        uint256 allocatedFee = feeInfo.allocatedFee;
        require(amount <= totalSellFee - allocatedFee, "Insufficient unallocated fee");
        feeInfo.allocatedFee += amount;
        IERC20(token).safeIncreaseAllowance(stakePool, amount);
        IStakePool(stakePool).depositReward(amount);
        emit FeeAllocated(amount, allocatedFee + amount, totalSellFee, block.timestamp);
    }

    function addReward(uint256 lastDigit, uint256 amount) external {
        require(lastDigit == 8 || lastDigit == 9, "Invalid last digit");
        require(amount > 0, "Invalid amount");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        if (lastDigit == 8) {
            betPoolInfos[lastDigit].prizeAmount += amount;
        } else {
            uint256 specialAmount = (amount * 75) / 100; // 75%
            betPoolInfos[lastDigit].prizeAmount += (amount - specialAmount);
            betPoolInfos[lastDigit].specialPrizeAmount += specialAmount;
        }
    }

    function getRoundAmount(uint256 n) public pure returns (uint256) {
        return n / USDT_DECIMALS;
    }

    function processBuy(address from, address to, uint256 tokenAmount, uint256 usdtAmount) external onlyToken {
        require(tokenAmount > 0, "Invalid token amount");
        require(usdtAmount > 0, "Invalid USDT amount");

        uint256 roundAmount = getRoundAmount(usdtAmount);
        uint256 lastDigit = roundAmount % 10;
        // Not an integer or last digit not in 1-7, direct purchase
        if (usdtAmount % USDT_DECIMALS != 0 || lastDigit == 0) {
            require(openFreeTrade, "Free trade not open");
            IERC20(token).safeTransfer(to, tokenAmount);
            return;
        }

        if (lastDigit < 8) {
            uint256 roundId = roundIds[roundAmount];
            // Check if previous round is settled
            if (roundId > 0) {
                RoundInfo storage lastRoundInfo = roundInfos[roundAmount][roundId - 1];
                uint256 settleBlockNumber = lastRoundInfo.settleBlockNumber;
                if (lastRoundInfo.settleBlockHash == bytes32(0) && block.number > settleBlockNumber && block.number <= settleBlockNumber + 256) {
                    _playSettle(lastRoundInfo, roundAmount, roundId - 1, blockhash(settleBlockNumber));
                }
            }

            // Last digit 1-7, lock 50%
            uint256 lockAmount = (tokenAmount * 500) / 1000; // 50%
            BuyTransaction memory txData = BuyTransaction({
                isContributor: false,
                to: to,
                tokenAmount: tokenAmount,
                usdtAmount: usdtAmount,
                lockAmount: lockAmount,
                luckyAmount: 0 // Initial lucky amount is 0
            });
            RoundInfo storage roundInfo = roundInfos[roundAmount][roundId];
            uint8 txCount = roundInfo.txCount;
            require(txCount < ROUND_TX_COUNT, "Round full");

            // Fixed array assignment
            roundInfo.transactions[txCount] = txData;
            roundInfo.totalLockAmount += lockAmount;
            txCount += 1;
            roundInfo.txCount = txCount;

            IERC20(token).safeTransfer(to, tokenAmount - lockAmount);
            emit Play(to, roundId, txCount, tokenAmount, lockAmount, usdtAmount);

            if (txCount == ROUND_TX_COUNT) {
                uint256 settleBlockNumber = block.number + 1;
                roundInfo.settleBlockNumber = settleBlockNumber;
                emit RoundClosed(roundAmount, roundId, settleBlockNumber);
                // Update round
                roundIds[roundAmount] = roundId + 1; // open next round
            }
        } else {
            // Last digit is 8 or 9
            uint256 roundId = betRoundIds[lastDigit];
            // Check if previous round is settled
            if (roundId > 0) {
                BetRoundInfo storage lastBetRoundInfo = betRoundInfos[lastDigit][roundId - 1];
                uint256 settleBlockNumber = lastBetRoundInfo.settleBlockNumber;
                if (lastBetRoundInfo.settleBlockHash == bytes32(0) && block.number > settleBlockNumber && block.number <= settleBlockNumber + 256) {
                    _betSettle(lastBetRoundInfo, lastBetRoundInfo.roundAmount, roundId - 1, blockhash(settleBlockNumber));
                }
            }

            uint256 lockAmount = (tokenAmount * 500) / 1000; // 50%
            BetRoundInfo storage betRoundInfo = betRoundInfos[lastDigit][roundId];
            uint8 txCount = betRoundInfo.txCount;
            // Safety check: ensure txCount is within valid range to prevent array out of bounds
            require(txCount < ROUND_TX_COUNT, "Round full");
            if (txCount == 0) {
                betRoundInfo.roundAmount = roundAmount; // Record this round's amount
            } else {
                require(betRoundInfo.roundAmount == roundAmount, "Mismatched round amount");
            }
            bytes32 betHash = getBetHash(to, tokenAmount, usdtAmount);
            BetTransaction memory txData = BetTransaction({
                to: to,
                luckyLevel: 0, // Initial lucky level is 0
                tokenAmount: tokenAmount,
                usdtAmount: usdtAmount,
                lockAmount: lockAmount,
                luckyAmount: 0, // Initial lucky amount is 0
                betHash: betHash,
                betNumbers: getDigits(betHash, lastDigit == 8 ? 3 : 6)
            });
            // Safe array access: confirm index validity again
            require(txCount < ROUND_TX_COUNT, "Transaction index out of bounds");
            betRoundInfo.transactions[txCount] = txData;
            betRoundInfo.totalLockAmount += lockAmount;
            txCount += 1;
            betRoundInfo.txCount = txCount;

            if (lastDigit == 8) {
                betPoolInfos[lastDigit].prizeAmount += lockAmount;
            } else {
                // Last digit is 9, 75% goes to special prize pool
                uint256 specialAmount = (lockAmount * 75) / 100; // 75%
                betPoolInfos[lastDigit].prizeAmount += (lockAmount - specialAmount);
                betPoolInfos[lastDigit].specialPrizeAmount += specialAmount;
            }

            betPoolInfos[lastDigit].allocatePoint += roundAmount;

            IERC20(token).safeTransfer(to, tokenAmount - lockAmount);
            emit Bet(to, roundId, txCount, tokenAmount, lockAmount, usdtAmount, betHash);
            if (txCount == ROUND_TX_COUNT) {
                uint256 settleBlockNumber = block.number + 1;
                betRoundInfo.settleBlockNumber = settleBlockNumber;
                emit RoundClosed(roundAmount, roundId, settleBlockNumber);
                betRoundIds[lastDigit] = roundId + 1; // open next round
            }
        }
    }

    function _playSettle(RoundInfo storage roundInfo, uint256 roundAmount, uint256 roundId, bytes32 settleBlockHash) internal {
        // If blockhash returns 0 (timeout), allow caller to provide a non-zero settleBlockHash as fallback
        require(settleBlockHash != bytes32(0), "Invalid settle block hash");
        uint256 settleBlockNumber = roundInfo.settleBlockNumber;
        require(settleBlockNumber > 0, "Round not close");
        require(block.number > settleBlockNumber, "Block number limited");
        require(roundInfo.settleBlockHash == bytes32(0), "Round already settled");
        require(roundInfo.txCount == ROUND_TX_COUNT, "Round not full");

        roundInfo.settleBlockHash = settleBlockHash;

        uint256 lastDigit = roundAmount % 10;
        require(lastDigit > 0 && lastDigit < 8, "Invalid roundAmount");

        uint8[] memory orderedPosition = getDigitOrder1to8(settleBlockHash);
        // transactions index in order loss locked tokens, others win tokens by their locked amount share
        uint256 contributeAmount;
        uint256 length = orderedPosition.length;
        for (uint256 i = 0; i < lastDigit && i < length; i++) {
            uint8 position = orderedPosition[i];
            // if (position < 1 || position > 8) continue; // Skip invalid positions
            BuyTransaction storage txData = roundInfo.transactions[position - 1];
            txData.isContributor = true;
            contributeAmount += txData.lockAmount;
            // emit Contribute(txData.to, roundAmount, roundId, position, txData.lockAmount);
        }
        uint256 totalShare = roundInfo.totalLockAmount - contributeAmount;
        if (totalShare > 0) {
            for (uint256 i = 0; i < ROUND_TX_COUNT; i++) {
                BuyTransaction storage txData = roundInfo.transactions[i];
                if (!txData.isContributor) {
                    uint256 lockAmount = txData.lockAmount;
                    uint256 winAmount = (contributeAmount * lockAmount) / totalShare;
                    IERC20(token).safeTransfer(txData.to, lockAmount + winAmount);
                    emit Win(txData.to, roundAmount, roundId, i + 1, lockAmount + winAmount);
                }
            }
        }
        emit RoundSettled(roundAmount, roundId, settleBlockHash);
    }

    function _betSettle(BetRoundInfo storage betRoundInfo, uint256 roundAmount, uint256 roundId, bytes32 settleBlockHash) internal {
        uint256 lastDigit = roundAmount % 10;
        require(lastDigit > 7, "Invalid lastDigit");
        if (roundId > 0) {
            require(betRoundInfos[lastDigit][roundId - 1].settleBlockHash != bytes32(0), "Previous round not settled");
        }
        uint8[] memory winNumbers = getDigits(settleBlockHash, lastDigit == 8 ? 3 : 6);
        betRoundInfo.winNumbers = winNumbers;
        betRoundInfo.settleBlockHash = settleBlockHash;
        BetPoolInfo storage poolInfo = betPoolInfos[lastDigit];
        uint256 roundAllocatePoint = roundAmount * ROUND_TX_COUNT;
        if (lastDigit == 8) {
            // Handle 8-digit case
            bool hasWinner = false;
            for (uint8 i = 0; i < 8; i++) {
                BetTransaction storage txData = betRoundInfo.transactions[i];
                uint8 matches = countMatches(txData.betNumbers, winNumbers);
                if (matches > 0) {
                    txData.luckyLevel = 4 - matches;
                    betRoundInfo.levelWinners[4 - matches].push(i);
                    hasWinner = true;
                }
            }
            if (hasWinner) {
                uint256 normalPrizeAmount = (poolInfo.prizeAmount * roundAllocatePoint * 40) / (poolInfo.allocatePoint * 100);
                betRoundInfo.normalPrizeAmount = normalPrizeAmount;
                poolInfo.prizeAmount -= normalPrizeAmount;
                // Process winner logic
                distributePrizes8(betRoundInfo, roundAmount, roundId);
            }
            poolInfo.allocatePoint -= roundAllocatePoint;
        } else {
            // Handle 9-digit case
            bool hasLevel1Winner = false;
            bool hasWinner = false;
            for (uint8 i = 0; i < 8; i++) {
                BetTransaction storage txData = betRoundInfo.transactions[i];
                uint8 matches = countMatches(txData.betNumbers, winNumbers);
                if (matches > 0) {
                    txData.luckyLevel = 7 - matches;
                    betRoundInfo.levelWinners[7 - matches].push(i);
                    if (matches == 6) {
                        hasLevel1Winner = true;
                    } else {
                        hasWinner = true;
                    }
                }
            }
            uint256 normalPrizeAmount = 0;
            uint256 specialPrizeAmount = 0;
            if (hasWinner) {
                normalPrizeAmount = (poolInfo.prizeAmount * roundAllocatePoint) / (poolInfo.allocatePoint);
                betRoundInfo.normalPrizeAmount = normalPrizeAmount;
            }
            if (hasLevel1Winner) {
                specialPrizeAmount = (poolInfo.specialPrizeAmount * roundAllocatePoint * 65) / (poolInfo.allocatePoint * 100);
                uint256 specialPrizeCap = (MAX_REWARD_USDT * 1e18) / getTokenPrice();
                if (specialPrizeAmount > specialPrizeCap) {
                    specialPrizeAmount = specialPrizeCap;
                }
                betRoundInfo.specialPrizeAmount = specialPrizeAmount;
            }
            poolInfo.prizeAmount -= normalPrizeAmount;
            poolInfo.specialPrizeAmount -= specialPrizeAmount;
            poolInfo.allocatePoint -= roundAllocatePoint;
            if (hasWinner || hasLevel1Winner) {
                // Process winner logic
                distributePrizes9(betRoundInfo, roundAmount, roundId);
            }
        }
        emit RoundSettled(roundAmount, roundId, settleBlockHash);
    }

    // Distribute prizes
    function distributePrizes8(BetRoundInfo storage betRoundInfo, uint256 roundAmount, uint256 roundId) private {
        uint256 totalPrize = betRoundInfo.normalPrizeAmount;
        for (uint8 i = 1; i < 4; i++) {
            uint256 winnerCount = betRoundInfo.levelWinners[i].length;
            uint256 levelPrize = (totalPrize * betLevelPoints[8][i]) / 100;
            if (winnerCount > 0) {
                levelPrize = levelPrize / winnerCount;
                for (uint256 j = 0; j < winnerCount; j++) {
                    uint256 winnerId = betRoundInfo.levelWinners[i][j];
                    // Distribute prize to each winner
                    BetTransaction storage txData = betRoundInfo.transactions[winnerId];
                    txData.luckyAmount = levelPrize;
                    emit BetWin(txData.to, roundAmount, roundId, winnerId + 1, levelPrize, i);
                    IERC20(token).safeTransfer(txData.to, levelPrize);
                }
            } else {
                // No winners for this level, prize rolls over to next round
                betPoolInfos[8].prizeAmount += levelPrize;
            }
        }
    }

    function distributePrizes9(BetRoundInfo storage betRoundInfo, uint256 roundAmount, uint256 roundId) private {
        uint256 normalPrizeAmount = betRoundInfo.normalPrizeAmount;
        uint256 specialPrizeAmount = betRoundInfo.specialPrizeAmount;
        // Process first prize
        if (specialPrizeAmount > 0) {
            uint256 winnerCount = betRoundInfo.levelWinners[1].length;
            uint256 levelPrize = specialPrizeAmount / winnerCount;
            for (uint256 j = 0; j < winnerCount; j++) {
                uint256 winnerId = betRoundInfo.levelWinners[1][j];
                // Distribute prize to each first prize winner
                BetTransaction storage txData = betRoundInfo.transactions[winnerId];
                txData.luckyAmount = levelPrize;
                IERC20(token).safeTransfer(txData.to, levelPrize);
                emit BetWin(txData.to, roundAmount, roundId, winnerId + 1, levelPrize, 1);
            }
        }

        // Process 2nd-6th prizes
        for (uint8 i = 2; i < 7; i++) {
            uint256 winnerCount = betRoundInfo.levelWinners[i].length;
            uint256 levelPrize = (normalPrizeAmount * betLevelPoints[9][i]) / 100;
            if (winnerCount > 0) {
                levelPrize = levelPrize / winnerCount;
                for (uint256 j = 0; j < winnerCount; j++) {
                    uint256 winnerId = betRoundInfo.levelWinners[i][j];
                    // Distribute prize to each winner
                    BetTransaction storage txData = betRoundInfo.transactions[winnerId];
                    txData.luckyAmount = levelPrize;
                    IERC20(token).safeTransfer(txData.to, levelPrize);
                    emit BetWin(txData.to, roundAmount, roundId, winnerId + 1, levelPrize, i);
                }
            } else {
                // No winners for this level, prize rolls over to next round
                betPoolInfos[9].prizeAmount += levelPrize;
            }
        }
    }

    function settleRound(uint256 roundAmount, uint256 roundId, bytes32 settleBlockHash) external onlyRole(SETTLER_ROLE) {
        uint256 lastDigit = roundAmount % 10;
        require(lastDigit > 0, "Invalid lastDigit");
        if (lastDigit < 8) {
            RoundInfo storage roundInfo = roundInfos[roundAmount][roundId];
            uint256 settleBlockNumber = roundInfo.settleBlockNumber;
            require(settleBlockNumber > 0, "Round not closed");
            // If not yet exceeded 256 blocks, use on-chain blockhash
            if (block.number <= settleBlockNumber + 256) {
                settleBlockHash = blockhash(settleBlockNumber);
            }
            _playSettle(roundInfo, roundAmount, roundId, settleBlockHash);
        } else {
            BetRoundInfo storage betRoundInfo = betRoundInfos[lastDigit][roundId];
            uint256 settleBlockNumber = betRoundInfo.settleBlockNumber;
            require(settleBlockNumber > 0, "Round not closed");
            require(betRoundInfo.roundAmount == roundAmount, "Mismatched round amount");
            // If not yet exceeded 256 blocks, use on-chain blockhash
            if (block.number <= settleBlockNumber + 256) {
                settleBlockHash = blockhash(settleBlockNumber);
            }
            _betSettle(betRoundInfo, roundAmount, roundId, settleBlockHash);
        }
    }

    function processSellFee(address from, address to, uint256 feeAmount) external onlyToken {
        // Handle sell fee logic here
        feeInfo.totalSellFee += feeAmount;
        emit Sell(from, feeAmount);
    }

    // Return only 1-8 in order of first appearance, no duplicates (exclude 0 and 9)
    function getDigitOrder1to8(bytes32 data) public pure returns (uint8[] memory) {
        uint256 foundBits = 0; // Use bitmask instead of bool array for gas efficiency
        uint8[] memory result = new uint8[](8);
        uint256 count = 0;

        for (uint256 i = 0; i < 32 && count < 8; i++) {
            uint8 b = uint8(data[i]);

            // Process high 4 bits
            uint8 high = b >> 4;
            if (high > 0 && high < 9) {
                uint256 highMask = 1 << high;
                if ((foundBits & highMask) == 0) {
                    result[count++] = high;
                    foundBits |= highMask;
                    if (count == 8) break;
                }
            }

            // Process low 4 bits
            uint8 low = b & 0x0F;
            if (low > 0 && low < 9) {
                uint256 lowMask = 1 << low;
                if ((foundBits & lowMask) == 0) {
                    result[count++] = low;
                    foundBits |= lowMask;
                }
            }
        }

        // Resize result array to actual count using assembly
        assembly {
            mstore(result, count)
        }

        return result;
    }

    // Return digits up to maxCount
    function getDigits(bytes32 data, uint256 maxCount) public pure returns (uint8[] memory) {
        uint8[] memory temp = new uint8[](maxCount);
        uint256 count = 0;

        for (uint256 i = 0; i < 32; i++) {
            uint8 b = uint8(data[i]);

            // High 4 bits
            uint8 high = b >> 4;
            if (high < 10) {
                temp[count] = high;
                count++;
                if (count == maxCount) {
                    return temp;
                }
            }

            // Low 4 bits
            uint8 low = b & 0x0F;
            if (low < 10) {
                temp[count] = low;
                count++;
                if (count == maxCount) {
                    return temp;
                }
            }
        }
        return temp;
    }

    // Count matches between two arrays
    function countMatches(uint8[] memory digits1, uint8[] memory digits2) private pure returns (uint8 matches) {
        require(digits1.length == digits2.length, "Length mismatch");
        for (uint8 i = 0; i < digits1.length; i++) {
            if (digits1[i] == digits2[i]) {
                matches++;
            }
        }
    }

    function estimateRoundPrize(uint256 roundAmount) external view returns (uint256[] memory prizes) {
        uint256 lastDigit = roundAmount % 10;
        require(lastDigit == 8 || lastDigit == 9, "Invalid round amount");

        BetPoolInfo storage poolInfo = betPoolInfos[lastDigit];
        uint256 currentRoundId = betRoundIds[lastDigit];
        BetRoundInfo storage currentRound = betRoundInfos[lastDigit][currentRoundId];
        uint256 totalAllocatePoint = poolInfo.allocatePoint;
        uint256 roundAllocatePoint;

        if (currentRound.txCount == 0) {
            roundAllocatePoint = roundAmount * ROUND_TX_COUNT;
        } else {
            roundAllocatePoint = roundAmount * currentRound.txCount;
        }
        if (totalAllocatePoint == 0) {
            totalAllocatePoint = roundAllocatePoint;
        }

        if (lastDigit == 8) {
            // 8 digits: 40% allocated to normal prize pool, return 4 values
            prizes = new uint256[](4);
            uint256 normalPrizeAmount = (poolInfo.prizeAmount * roundAllocatePoint * 40) / (totalAllocatePoint * 100);
            prizes[0] = normalPrizeAmount;
            // Use for loop to calculate returns for each level (level 1-3)
            for (uint8 i = 1; i < 4; i++) {
                prizes[i] = (normalPrizeAmount * betLevelPoints[8][i]) / 100;
            }
        } else {
            // 9 digits: 8% allocated to normal prize pool, 65% to special prize pool, return 7 values
            prizes = new uint256[](7);
            uint256 normalPrizeAmount = (poolInfo.prizeAmount * roundAllocatePoint) / totalAllocatePoint;
            uint256 specialPrizeAmount = (poolInfo.specialPrizeAmount * roundAllocatePoint * 65) / (totalAllocatePoint * 100);
            uint256 specialPrizeCap = (MAX_REWARD_USDT * 1e18) / getTokenPrice();
            if (specialPrizeAmount > specialPrizeCap) {
                specialPrizeAmount = specialPrizeCap;
            }
            prizes[0] = normalPrizeAmount + specialPrizeAmount;
            prizes[1] = specialPrizeAmount;
            for (uint8 i = 2; i < 7; i++) {
                prizes[i] = (normalPrizeAmount * betLevelPoints[9][i]) / 100;
            }
        }
    }
}
