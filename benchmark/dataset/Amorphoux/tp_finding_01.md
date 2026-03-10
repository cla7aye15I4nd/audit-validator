# Unauthorized Minting of XFAN Tokens Drains USDT Balance


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `125b80a0-673c-11ef-a5cd-fb3ecf7b1c26` |
| Commit | `f97cff8bf35c3a4201710d0ab880b86a760fc3f8` |

## Location

- **Local path:** `./source_code/github/CertiKProject/certik-audit-projects/0295b7689e688334b6d4780c6438c907b9362b08/03092024_XFAN.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/125b80a0-673c-11ef-a5cd-fb3ecf7b1c26/source?file=$/github/CertiKProject/certik-audit-projects/0295b7689e688334b6d4780c6438c907b9362b08/03092024_XFAN.sol
- **Lines:** 313–317

## Description

The XFAN staking contract contains a critical vulnerability in the way the minting of tokens is handled. The contract's invest function allocates user-staked USDT into three categories:

- 20% is used for instant mining and swapped to aETH.
- 40% is designated for 40 days mining, stored in the contract without being swapped.
- The remaining 40% is effectively a fee, which is also stored in the contract.

This process creates a problem within the `mintXFAN()` function, where any user can trigger the minting of XFAN tokens. This function doesn't restrict minting to the specific USDT balance of the caller. Instead, it allows access to the entire contract balance of USDT, presenting a vulnerability that can be exploited by malicious actors.

```solidity
  function invest(uint256 investId, uint256 amount) external 
     whenNotPaused nonReentrant notBlacklisted(msg.sender) {
         usdt.transferFrom(msg.sender, address(this), amount);
  
         uint256 instantAmount = (_amount * 20) / 100; 
         uint256 miningAmount  = (_amount * 40) / 100; 
  
         _mintXFAN(msg.sender, instantAmount, IMintROI.ROIType.DIRECT);
         MintROI.addCapital(msg.sender, miningAmount, 40, 250, IMintROI.ROIType.STM);
     }
```

**Root Cause**

The contract does not sufficiently restrict access to the `mintXFAN()` function. Any not blacklisted user is allowed to call this function directly and trigger the internal `_mintXFAN()` function. This function mints XFAN tokens using the contract’s overall balance of USDT instead of restricting it to the rightful portion of the caller’s staked amount. This flaw enables users to mint XFAN tokens by utilizing the contract's entire USDT holdings, thus draining the contract of its assets.

The `mintXFAN()` function can be called by any user as shown here:
```solidity
    function mintXFAN(address miner, uint256 amount, IMintROI.ROIType roiType)
       external whenNotPaused notBlacklisted(miner) {
       _mintXFAN(miner, amount, roiType);
    }

    function _mintXFAN(address miner, uint256 amount, IMintROI.ROIType roiType) internal 
    {
        uint256 bln = getUSDCBalance();
        uint256 _tokenAmount = amount.from18Decimals(usdtDecimals);
        require(bln >= _tokenAmount, "insuffient balance");
    ...
    }
```

The internal `_mintXFAN()` function does not check if the amount of USDT corresponds to the calling user’s balance but instead checks the contract’s entire balance, leading to potential abuse.

## Recommendation

**To prevent unauthorized access to minting XFAN tokens**

Limit the function so that only the MintROI contract is authorized to call the `mintXFAN` function. This will ensure that users can only mint XFAN tokens through the legitimate invest function.

```solidity
contract MintROI is Pausable, Ownable, ReentrancyGuard {

   function claimDividend(ROIType _roiType) public whenNotPaused nonReentrant {
      ...
      XFAN.mintXFAN(msg.sender, unclaimed, _roiType);
      ...
   }
}
```

## Vulnerable Code

```
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
```
