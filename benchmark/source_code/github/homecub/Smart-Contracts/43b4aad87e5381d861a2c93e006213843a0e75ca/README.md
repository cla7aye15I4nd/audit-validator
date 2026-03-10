
# Homecubes Trade and stake contracts

## Environment 
```js
    Node v20.10.0 (npm v10.2.3)
```

Add RPC urls and etherscan apikey on hardhat.config.js

## Todo

```js
    #First run "npm install --exact"
```
## Structure
 - Trade contract : contracts/Trade.sol
 - Stake contract : contracts/homecubesStake.sol

 ## Deploy script running command
 - Trade : npx hardhat run scripts/tradeDeploy.js
 - Stake : npx hardhat run scripts/stakeDeploy.js

## Do not verify the smart contract due to security reason !!!

 ## Upgrate script running command
 - Trade : npx hardhat run scripts/upgradeProxyTrade.js
 - Stake : npx hardhat run scripts/upgradeProxyStake.js

```js
    Note : Need to change deployed contract address in these files
```

## Deployer contract deploy

```js
    Deploy deployer contract in remix
    File : DeployerHome.sol
```

Trade contract setup
    * Set setDeployerAddress (0x92152f18) -> Deployed DeployerHome.sol address.
    * Set changeExeAddress (0xb0884592) -> Executor address for bid cancellation admin address.
    * Add addTokenType (0x684d76fc) -> Tokens that we gonna use for platform. 
    * Set whitlistAdmin (0xb49e1bba) -> Set contract owner as a whitelist admin.

Stake contract setup
    * For security purpose. This contract strictly not verified. 
    * Once contract deployed, trigger initialize (0x8129fc1c).
    * Set addRewardToken (0x1c03e6cc) -> Reward token address.
    * Add editPool (0xc6a0cf2f) -> Set poolid as 0 to add new pool.
    * Set editTradeAddress (0x98ec9d07) -> Set Trade address.
    * Set setMessage (0x368b8772) -> Set message to claim verification.

Deployer contract setup
    * When deploy this contract. Use trade address as a owner.
