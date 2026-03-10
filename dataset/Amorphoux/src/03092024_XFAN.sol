// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);
}

interface IUniswapV2Router {
    function WETH() external view returns (address);
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts);
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts);    
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);    
}


interface IPancakeRouter{
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint[] memory amounts);
}

interface ISmartRouter{
    function swapExactTokensForTokens(uint256 amountIn,uint256 amountOutMin,address[] calldata path,address to) external payable returns (uint256 amountOut);
}

interface IMintROI {
    // ATM(0)=active reward, STM(1)=passive reward, ACCUMALATOR(2)=queue games reward, DIRECT(3)=direct mining
    enum ROIType { ATM, STM, ACCUMALATOR, DIRECT }    
    function addCapital(address _to, uint256 _amount, uint256 _maxClaimCount, uint256 _roi, ROIType _roiType) external;
    function getTotalUnclaimedROI(ROIType _roiType) external view returns (uint256);
}

interface IPriceContract {
    function currentPrice() external view returns (uint256);
}

interface IStargateCrossChainSwap{
    function swap(uint16 _dstChainId, uint256 _srcPoolId, uint256 _dstPoolId, 
        uint256 _amountLD, uint256 _minAmountLD) external payable;
    
}

library DecimalUtils {
    function to18Decimals(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return amount;
        } else if (decimals < 18) {
            return amount * (10 ** (18 - decimals));
        } else {
            return amount / (10 ** (decimals - 18));
        }
    }

    function from18Decimals(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return amount;
        } else if (decimals < 18) {
            return amount / (10 ** (18 - decimals));
        } else {
            return amount * (10 ** (decimals - 18));
        }
    }
}

contract XFAN is Pausable, IERC20, Ownable, ReentrancyGuard {

    string public constant name = "AMORPHOUX COIN";
    string public constant symbol = "AMOR";
    string private constant _chainName = "bsc_testnet";
    uint8 public usdtDecimals = 0;
    uint8 private constant decimals = 18;
    uint256 private _totalSupply = 90000000000000000 * (10 ** 18);
    uint256 private _releasedSupply;
    uint256 public _directMint;

    uint256 public xfanPrice = 10000000000000; // 0.00001
    uint256 public totalEthPool; // Total ETH Minting Pool Balance
    uint256 public totalXFANPool; // Total XFAN Minting Pool Balance
    uint256 public lastAccessTs = 0;
    uint256 public constant LOCK_PERIOD = 5 minutes; // 5 minutes; 365 days; // todo : change to 365 days on mainnet

    mapping(address => uint256) private _balances; // XFAN balances holder
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _blacklist;

    address private constant stakeAddress = 0x8e5664e76D4d285BEAAd88af3243f4510CE25CFd; 
    address private constant feeAddress = 0xc15F473Cb656f78eABe4d175B092A78DA2f87Fd5;

    /**
        uniswap router v2 address:
        1. ETH (eth) Sepolia testnet : 0x86dcd3293C53Cf8EFd7303B57beb2a3F671dDE98
        2. ETH (arb) sepolia testnet : 0xAc0f6eDD992fc451e3C880ae72392Bad3502403a
        3. BSC testnet               : 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
    **/
    address private constant UNISWAP_ROUTER_ADDRESS = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address private constant PANCAKE_ROUTER_ADDRESS = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1; // bsc testnet
    address private constant PANCAKE_SMART_ROUTER_ADDRESS = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4; // bsc mainnet
    
    /**
        USDC / USDC address
        1. ETH (eth) Sepolia testnet : 0xbe72E441BF55620febc26715db68d3494213D8Cb (USDC)
        2. ETH (arb) Sepolia testnet : 0x30fA2FbE15c1EaDfbEF28C188b7B8dbd3c1Ff2eB (USDT)
        3. BSC testnet               : 0x5685531bCbD333c777bAf6AC339de35ccfC333Cf (USDT)
        4. BSC testnet (test)        : 0xe75A212aD272022e794c2bDf090719C54F2acE66 (aUSDT)
    **/    
    address private constant USDT_ADDRESS = 0xe75A212aD272022e794c2bDf090719C54F2acE66;
    address private constant ETH_ADDRESS = 0x788149f58c6aDaD162875a65CF18C2dF758c901A; // test token (bsc testnet)
    address private constant usdcTokenAddress = 0x3253a335E7bFfB4790Aa4C25C4250d206E9b9773; // cross-chain : USDC for stargate

    /**
        Chainlink Aggregator ETH/USD price feed
        1. ETH (eth) Sepolia testnet : 0x694AA1769357215DE4FAC081bf1f309aDC325306
        2. BSC testnet (BNB/USD)     : 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526
        3. BSC mainnet (ETH/USD)     : 0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e
    **/
    address private constant CHAINLINK_AGGREGATOR_ADDRESS = 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526;

    address private _miningContract;
    address private _priceContract;
    address private _crossChainContract;
    address private _contractAddress;
    address private _contractMintROI;
    uint256 private constant AMOUNT_OUT_MIN = 0; // Minimum amount of swap token
    
    IUniswapV2Router private uniswapRouter;
    IPancakeRouter private pancakeRouter;
    ISmartRouter private pancakeSmartRouter;

    using DecimalUtils for uint256;

    IERC20 public usdt;
    IMintROI private MintROI;
    IPriceContract private PriceContract;
    IStargateCrossChainSwap private StargateCrossChainSwap;
    AggregatorV3Interface internal priceFeed;

    event Mint(address indexed miner, uint256 mintUsdAmount, uint256 mintedXFAN, uint256 minerXFAN, uint256 feeXFAN, uint256 totalXFANPool, uint256 XFANPrice, IMintROI.ROIType mintType);
    event SwapUsdtForXFAN(uint256 mintUsdAmount, uint256 ethReceived, uint256 ethPrice, uint256 swapETHAmountUsd, uint256 mint80AmountUsd, uint256 mintedXFAN, uint256 totalEthPool, uint256 oldXFANPrice, uint256 newXFANPrice, uint256 totalEthPoolUSD);
    event Unstake(address indexed miner, uint256 unstakeAmount, uint256 ethTransferred, uint256 ethPrice, uint256 unstakeUsdAmount, uint256 unstakeUsd85Amount, uint256 totalEthPool, uint256 totalXFANPool, uint256 oldXFANPrice, uint256 newXFANPrice, uint256 totalEthPoolUSD);
    event UsdtSwapETH(uint256 usdtAmount, uint256 ethReceived);
    event SwapETHForUSDTSuccessful(uint256 ethAmount);
    event Invest(uint256 investId, uint256 amount);
    event GetPrice(string status, uint256 _price, uint256 _xfan_price);
    event logEventMessage(string status, uint256 data);
    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);
    event BurnedBlacklistedFunds(address indexed account, uint256 amount);
    event WithdrawToken(uint256 amount, uint256 workingAmount, uint256 outAmount);

    constructor() Ownable(msg.sender){
        _contractAddress = address(this);
        _balances[_contractAddress] = _totalSupply;
        usdt = IERC20(USDT_ADDRESS);
        usdtDecimals = IERC20Extended(USDT_ADDRESS).decimals(); // 6
        uniswapRouter = IUniswapV2Router(UNISWAP_ROUTER_ADDRESS);
        priceFeed = AggregatorV3Interface(CHAINLINK_AGGREGATOR_ADDRESS);
        pancakeRouter = IPancakeRouter(PANCAKE_ROUTER_ADDRESS);
        pancakeSmartRouter = ISmartRouter(PANCAKE_SMART_ROUTER_ADDRESS);
        emit Transfer(address(0), _contractAddress, _totalSupply);
    }

    function getUSDCBalance() private view returns (uint256){
        uint256 balance = usdt.balanceOf(address(this));
        return balance;
    }

    function updateMintRContract(address _contract) external onlyOwner{
        MintROI = IMintROI(_contract);
        _miningContract = _contract;
    }

    function updatePriceContract(address _contract) external onlyOwner{
        PriceContract = IPriceContract(_contract);
        _priceContract = _contract;
    }

    function updateCrossContract(address _contract) external onlyOwner{
        StargateCrossChainSwap = IStargateCrossChainSwap(_contract);
        _crossChainContract = _contract;
    }    

    function getMiningContract() public view returns (address){
        return _miningContract;
    }  
    function getPriceContract() public view returns (address){
        return _priceContract;
    }
    function getCrossChainContract() public view returns (address){
        return _crossChainContract;
    }

    modifier notBlacklisted(address account) {
        require(!_blacklist[account], "Address is blacklisted");
        _;
    }    

    // IERC20 implementation
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function circulatingSupply() public view returns (uint256){
        return _releasedSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        require(recipient != address(0), "Transfer to the zero address");
        require(_balances[msg.sender] >= amount, "Insufficient balance");        
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner1, address spender) external view override returns (uint256) {
        return _allowances[owner1][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        require(spender != address(0), "Approve to the zero address");
        _approve(msg.sender, spender, amount);
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, msg.sender, currentAllowance - amount);
        _transfer(sender, recipient, amount);
        return true;
    }    

    function _transfer(address sender, address recipient, uint256 amount) internal whenNotPaused {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        
        uint256 fee = amount / 100; // Calculate the fee amounts : 1% fee
        uint256 burnAmount = fee / 2; // Half of the fee for burning
        uint256 amountToTransfer = amount - fee;
        _balances[sender] = _balances[sender] - amount; // Update balances
        _balances[recipient] = _balances[recipient] + amountToTransfer; // 99%
        _balances[stakeAddress] = _balances[stakeAddress] + burnAmount; // 0.5% fee

        require(burnAmount <= _totalSupply, "Burn amount exceeds total supply");
        _totalSupply = _totalSupply - burnAmount; // 0.5% burn
        
        emit Transfer(sender, recipient, amountToTransfer);
        emit Transfer(sender, stakeAddress, burnAmount);
        emit Transfer(sender, address(0), burnAmount); // Burn event
    }

    function _approve(address ownerx, address spender, uint256 amount) internal whenNotPaused {
        require(ownerx != address(0), "ERC20: approve from the zero address");
        _allowances[ownerx][spender] = amount;
        emit Approval(ownerx, spender, amount);
    }

    receive() external payable {}

    function invest(uint256 investId, uint256 amount) external whenNotPaused nonReentrant notBlacklisted(msg.sender) {
        require(amount > 0, "Amount must be greater than 0");
        uint256 _amount = amount.to18Decimals(usdtDecimals);  // to 18 decimals
        usdt.transferFrom(msg.sender, address(this), amount);

        uint256 instantAmount = (_amount * 20) / 100; // 20% instant mining
        uint256 miningAmount  = (_amount * 40) / 100; // 40% for 40 days mining

        _mintXFAN(msg.sender, instantAmount, IMintROI.ROIType.DIRECT);
        MintROI.addCapital(msg.sender, miningAmount, 40, 250, IMintROI.ROIType.STM); // 40 days , 2.5% per day
        emit Invest(investId, amount);
    }

    function swapUsdtXFAN(uint256 tokenAmount, uint256 usdtAmount) private returns (uint256){
  
        uint256 ethReceived = _swapUSDTForETH(tokenAmount,address(this)); // token swap eth
        require(ethReceived > 0, "swap eth is less than 0");

        emit UsdtSwapETH(usdtAmount, ethReceived);

        uint256 ethPrice = _getETHPrice();
        uint256 usdN = (ethReceived * ethPrice) / (10 ** 18); // 18 decimals

        totalEthPool += ethReceived; // update pool balance
        uint256 totalEthValue = (totalEthPool * ethPrice) / (10 ** 18);

         uint256 oldprice = xfanPrice;
         uint256 _xprice = getXFanPrice();
         uint256 usd80 = (usdN * 80) / 100;
         uint256 xfanToMint = (usd80 * (10 ** 18)) / _xprice;

         emit SwapUsdtForXFAN(usdtAmount, ethReceived, ethPrice, usdN, usd80, 
             xfanToMint, totalEthPool, oldprice, _xprice, totalEthValue);
        
        return xfanToMint;
    }

    function mintXFAN(address miner, uint256 amount, IMintROI.ROIType roiType)
        external whenNotPaused notBlacklisted(miner) 
    {
        _mintXFAN(miner, amount, roiType);
    }

    function _mintXFAN(address miner, uint256 amount, IMintROI.ROIType roiType) internal 
    {
        uint256 bln = getUSDCBalance();
        uint256 _tokenAmount = amount.from18Decimals(usdtDecimals);
        require(bln >= _tokenAmount, "insuffient balance");

        uint256 xfanToMint = swapUsdtXFAN(_tokenAmount, amount);        
        require(xfanToMint <= _balances[_contractAddress], "XFAN: mint amount exceeds balance");

        totalXFANPool += xfanToMint;
        _releasedSupply += xfanToMint;        

        _balances[_contractAddress] -= xfanToMint; // reduce from mining pool

        uint256 feeAmount = (xfanToMint * 10) / 100; // 10% fees
        uint256 depositAmount = (xfanToMint * 90) / 100; // 90% to miner
        _balances[feeAddress] += feeAmount; // add to fee address
        _balances[miner] += depositAmount; // add to miner

        if (roiType == IMintROI.ROIType.DIRECT) {
            _directMint += xfanToMint;
        }
        
        lastAccessTs = block.timestamp;
        emit Transfer(_contractAddress, miner, depositAmount);
        emit Transfer(_contractAddress, feeAddress, feeAmount);
        emit Mint(miner, amount, xfanToMint, depositAmount, feeAmount, totalXFANPool, xfanPrice, roiType);
    } 

    function unstakeXFAN(address miner, uint256 amount) 
        public whenNotPaused nonReentrant notBlacklisted(miner) 
    {
        require(amount <= _balances[miner], "XFAN: unstake amount exceeds balance");

        uint256 oldXfanPrice = xfanPrice; // old xfanPrice
        getXFanPrice();
        uint256 usdtAmount = (amount * xfanPrice) / (10 ** 18);
        require(usdtAmount > 10000000000000, "unstake failed 1"); // 0.00001

        uint256 usdtAmount85 = (usdtAmount * 85) / 100;
        require(usdtAmount85 > 10000000000000, "unstake failed 2"); // 0.00001

        uint256 ethPrice = _getETHPrice(); // Calculate ETH amount
        uint256 ethToTransfer = (usdtAmount85 * (10 ** 18)) / ethPrice;
        require(ethToTransfer > 0, "unstake failed 3");

        totalEthPool -= ethToTransfer;
        totalXFANPool -= amount;

        _balances[miner] -= amount;
        _balances[_contractAddress] -= amount; // burn token
        _totalSupply -= amount; // burn token
        _releasedSupply -= amount;

        require(address(this).balance >= ethToTransfer, "Insufficent eth balance");

        uint256 totalEthValue = (totalEthPool * ethPrice) / (10 ** 18);
        lastAccessTs = block.timestamp;

        payable(miner).transfer(ethToTransfer);
        
        emit Transfer(_contractAddress, miner, ethToTransfer);
        emit Unstake(miner, amount, ethToTransfer, ethPrice, usdtAmount, usdtAmount85, totalEthPool, 
            totalXFANPool, oldXfanPrice, xfanPrice, totalEthValue);
    }

    function getEstimatedETHForUnstake(uint256 amount) public view returns (uint256) {
        uint256 usdtAmount = (amount * xfanPrice) / (10 ** 18);
        uint256 usdtAmount85 = (usdtAmount * 85) / 100;

        uint256 ethPrice = _getETHPrice(); // get eth price
        uint256 ethToTransfer = (usdtAmount85 * (10 ** 18)) / ethPrice;
        return ethToTransfer;
    }

    function _swapUSDTForETH(uint256 amountIn, address to) public returns (uint256) {
        bytes32 chainByte = keccak256(abi.encodePacked(_chainName));
        if (chainByte == keccak256(abi.encodePacked("bsc_testnet")))
        {
            return swapUSDTForETH_BSC_TESTNET(amountIn, to);
        }
        else if (chainByte == keccak256(abi.encodePacked("bsc_mainnet")))
        {
            return swapUSDTForETH_BSC_MAINNET(amountIn, to);
        }
        else if (chainByte == keccak256(abi.encodePacked("eth_arb_mainnet")) || 
                 chainByte == keccak256(abi.encodePacked("eth_arb_testnet")))
        {
            return swapUSDTForETH_ETH(amountIn, to);
        }
        else
        {
            return 0;
        }
    }

    // uniswap for ETH chain
    function swapETHForUSDT() external onlyOwner payable {
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH(); // WETH address
        path[1] = USDT_ADDRESS; //USDT

        uniswapRouter.swapExactETHForTokens{value: msg.value}(
            AMOUNT_OUT_MIN,
            path,
            address(this),
            block.timestamp + 300 // Deadline for the swap transaction
        );
        emit SwapETHForUSDTSuccessful(msg.value);        
    }

    // todo : put public back to private, temp open for public
    function swapUSDTForETH_ETH(uint256 amountIn, address to) private returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = USDT_ADDRESS; // USDT
        path[1] = uniswapRouter.WETH();

        require(IERC20(USDT_ADDRESS).approve(UNISWAP_ROUTER_ADDRESS, amountIn), "USDT approve failed"); // approve contract
        uint256[] memory amounts = uniswapRouter.swapExactTokensForETH(
            amountIn,
            AMOUNT_OUT_MIN,
            path,
            to,
            block.timestamp + 300 // Deadline for the swap transaction
        );

        uint256 ethReceived = amounts[amounts.length - 1];
        return ethReceived; // Return ETH swapped
    }

    // bsc testnet
    function swapUSDTForETH_BSC_TESTNET(uint256 amountIn, address to) private returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = USDT_ADDRESS; // USDT
        path[1] = ETH_ADDRESS;

        require(IERC20(USDT_ADDRESS).approve(PANCAKE_ROUTER_ADDRESS, amountIn), "USDT approve failed"); // approve contract
        uint[] memory amounts = pancakeRouter.swapExactTokensForTokens(
            amountIn,
            AMOUNT_OUT_MIN,
            path,
            to,
            block.timestamp + 300 // Deadline for the swap transaction
        );
        uint256 ethReceived = amounts[amounts.length - 1];
        return ethReceived; // Return ETH swapped
    }

    // bsc mainnet
    function swapUSDTForETH_BSC_MAINNET(uint256 amountIn, address to) private returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = USDT_ADDRESS; // USDT
        path[1] = ETH_ADDRESS;

        require(IERC20(USDT_ADDRESS).approve(PANCAKE_SMART_ROUTER_ADDRESS, amountIn), "USDT approve failed"); // approve contract
        uint256 ethReceived = pancakeSmartRouter.swapExactTokensForTokens(
            amountIn,
            AMOUNT_OUT_MIN,
            path,
            to
        );
        return ethReceived; // Return ETH swapped
    }

    // todo: remove fix return at main-net : public view returns (uint256)
    function _getETHPrice() public pure returns (uint256) {
        // (
        //     /* uint80 roundID */,
        //     int256 answer,
        //     /*uint startedAt*/,
        //     /*uint timeStamp*/,
        //     /*uint80 answeredInRound*/
        // ) = priceFeed.latestRoundData();
        // uint256 _p = uint256(answer);
        // return _p.to18Decimals(usdtDecimals); // Amount of USDT received for 1 WETH, return 18 decimals
        return 2800 * (10 ** 18);
    }   
 

    function getXFanPrice() public whenNotPaused returns (uint256) {
        uint256 _price = PriceContract.currentPrice();
        if (_price == 0) {
            return xfanPrice;
        }
        if (xfanPrice != _price){
            xfanPrice = _price;
            return _price;
        }
        return _price;
    }

    function addToBlacklist(address account) external onlyOwner {
        _blacklist[account] = true;
        emit AddedToBlacklist(account);
    }
    
    function removeFromBlacklist(address account) external onlyOwner {
        _blacklist[account] = false;
        emit RemovedFromBlacklist(account);
    }

    function isBlacklisted(address account) public view returns (bool) {
        return _blacklist[account];
    }

    function burnBlacklistedFunds(address account) external onlyOwner {
        require(_blacklist[account], "Address not blacklisted");
        uint256 balance = _balances[account];
        _burn(account, balance);
        // remain burn xfan at stake pool. never burn from stake pool boz will impact price
        emit BurnedBlacklistedFunds(account, balance);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "Burn from zero address");
        require(_balances[account] >= amount, "Burn amount exceeds balance");
        _balances[account] -= amount;
        _totalSupply -= amount;
        _releasedSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }        

    function withdrawETH() external onlyOwner{
        require(block.timestamp >= lastAccessTs + LOCK_PERIOD, "Withdraw only allowed after 365 days from last access");
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawToken(address token, uint256 amount) external onlyOwner{
        require(block.timestamp >= lastAccessTs + LOCK_PERIOD, "Withdraw only allowed after 365 days from last access");
        require(token != uniswapRouter.WETH(), "Cannot withdraw WETH using this function");
        require(IERC20(token).transfer(msg.sender, amount), "Transfer failed");
    }

    function withdrawTokenLimit(address token, uint256 amount) external onlyOwner{
        require(block.timestamp >= lastAccessTs + LOCK_PERIOD, "Withdraw only allowed after 365 days from last access");
        require(token != uniswapRouter.WETH(), "Cannot withdraw WETH using this function");

        uint256 workingAmount = 0;
        if (token == USDT_ADDRESS){
            uint256 amountATM = MintROI.getTotalUnclaimedROI(IMintROI.ROIType.ATM);
            uint256 amountSTM = MintROI.getTotalUnclaimedROI(IMintROI.ROIType.STM);
            uint256 amountACCUMALATOR = MintROI.getTotalUnclaimedROI(IMintROI.ROIType.ACCUMALATOR);
            workingAmount = amountATM + amountSTM + amountACCUMALATOR;
        }

        uint256 outAmount = amount - workingAmount;
        emit WithdrawToken(amount, workingAmount, outAmount);        
        require(IERC20(token).transfer(msg.sender, outAmount), "Transfer failed");
    }
    
    function swapTokens(uint16 _dstChainId, uint256 _srcPoolId, uint256 _dstPoolId, 
         uint256 _amountLD, uint256 _minAmountLD) external onlyOwner payable {
        
        require(IERC20(usdcTokenAddress).balanceOf(address(this)) >= _amountLD, "Insufficient balance in contract");
        IERC20(usdcTokenAddress).approve(_crossChainContract, _amountLD);
        StargateCrossChainSwap.swap{
            value: msg.value
        }(
            _dstChainId,
            _srcPoolId, 
            _dstPoolId,
            _amountLD,
            _minAmountLD
        );
    }
}