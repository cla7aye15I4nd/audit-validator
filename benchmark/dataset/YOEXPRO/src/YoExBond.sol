// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IPancakeRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IYoexVault {
    function bondRewardTransfer(address _to, uint256 _amount) external;
}

contract YoExBond {
    address public owner;
    IERC20 public usdt;
    IERC20 public yoex;
    IPancakeRouter public router;
    IYoexVault public vault;
    address[] public path = new address[](2);
    uint256 public minBond = 1 * 1e18;
    uint256 public slippageBPS = 100; 

    struct Bond {
        uint256 amount;
        uint256 bonus;
        uint256 unlockTime;
        bool claimed;
    }

    mapping(address => Bond[]) public userBonds;
    mapping(address => uint256) public bondBalancesUSDT;
    mapping(address => uint256) public bondBalancesYOEX;
    mapping(address => uint256) public unbondBalancesYOEX;
    mapping(address => uint256) public unbondBalancesUSDT; 

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    event BondCreated(
        address indexed user,
        uint256 indexed index,
        uint256 indexed usdtAmount,
        uint256 yoexAmount,
        uint256 bonusAmount,
        uint256 lockDays,
        uint256 unlockTime
    );

    event BondUnstaked(
        address indexed user,
        uint256 indexed index,
        uint256 indexed totalWithdrawn,
        uint256 principal,
        uint256 bonus
    );

    event VaultUpdated(address oldVault, address newVault);
    event RouterUpdated(address oldRouter, address newRouter);
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);

    constructor(address _usdt, address _yoex, address _router, address _vault) {
        owner = msg.sender;
        usdt = IERC20(_usdt);
        yoex = IERC20(_yoex);
        router = IPancakeRouter(_router);
        vault = IYoexVault(_vault);
    }

    function bond(uint256 amount, uint256 lockDays) external {
        require(amount >= minBond, "Minimum bond is 1 USDT");
        require(lockDays != 0, "0 days lock not allowed");

        uint256 bonusPercent = getBonusPercent(lockDays);
        require(bonusPercent > 0, "Invalid bond duration");

        require(usdt.transferFrom(msg.sender, address(this), amount), "USDT transfer failed");
        require(usdt.approve(address(router), amount), "USDT approve failed");

        path[0] = address(usdt);
        path[1] = address(yoex);

        uint256 estimatedYoex = router.getAmountsOut(amount, path)[1];
        uint256 minYoex = (estimatedYoex * (10000 - slippageBPS)) / 10000;

        uint256 yoexReceived = router.swapExactTokensForTokens(
            amount,
            minYoex,
            path,
            address(this),
            block.timestamp + 600
        )[1];
        require(yoexReceived > 0, "Swap failed");

        uint256 burnedTokens = 0;
        if (estimatedYoex > yoexReceived) {
            burnedTokens = estimatedYoex - yoexReceived;
        }

        uint256 totalBondAmount = yoexReceived + burnedTokens;
        uint256 bonus = (totalBondAmount * bonusPercent) / 100;

        vault.bondRewardTransfer(address(this), bonus);

        uint256 unlockTime = block.timestamp + (lockDays * 1 days);

        userBonds[msg.sender].push(Bond({
            amount: totalBondAmount,
            bonus: bonus,
            unlockTime: unlockTime,
            claimed: false
        }));

        uint256 bondIndex = userBonds[msg.sender].length - 1;

        bondBalancesUSDT[msg.sender] += amount;
        bondBalancesYOEX[msg.sender] += totalBondAmount;

        emit BondCreated(
            msg.sender,
            bondIndex,
            amount,
            totalBondAmount,
            bonus,
            lockDays,
            unlockTime
        );
    }


    function unbond(uint256 index) external {
        require(index < userBonds[msg.sender].length, "Invalid index");

        Bond storage bondInfo = userBonds[msg.sender][index];
        require(!bondInfo.claimed, "Already claimed");
        require(block.timestamp >= bondInfo.unlockTime, "Bond still locked");

        bondInfo.claimed = true;
        uint256 total = bondInfo.amount + bondInfo.bonus;

        require(yoex.transfer(msg.sender, total), "YOEX transfer failed");

        path[0] = address(yoex);
        path[1] = address(usdt);

        uint[] memory amountsOut = router.getAmountsOut(total, path);
        uint256 expectedUsdtAmount = amountsOut[1];
        unbondBalancesUSDT[msg.sender] += expectedUsdtAmount;
        unbondBalancesYOEX[msg.sender] += total;

        emit BondUnstaked(
            msg.sender,
            index,
            total,
            bondInfo.amount,
            bondInfo.bonus
        );
    }

    function getBonusPercent(uint256 daysLocked) public pure returns (uint256) {
        if (daysLocked == 7) return 2;   
        if (daysLocked == 15) return 3;
        if (daysLocked == 30) return 4;
        if (daysLocked == 90) return 6;
        if (daysLocked == 180) return 7;
        if (daysLocked == 360) return 8;
        return 0;                       
    }

    function updateVault(address _vault) external onlyOwner {
        emit VaultUpdated(address(vault), _vault);
        vault = IYoexVault(_vault);
    }

    function updateRouter(address _router) external onlyOwner {
        emit RouterUpdated(address(router), _router);
        router = IPancakeRouter(_router);
    }

    function updateSlippage(uint256 bps) external onlyOwner {
        emit SlippageUpdated(slippageBPS, bps);
        slippageBPS = bps;
    }
}