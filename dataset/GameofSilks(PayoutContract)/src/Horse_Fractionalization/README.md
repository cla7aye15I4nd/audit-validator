# Horse Fractionalization
Folder contains code for the horse fractionalization/partnerships contract and it's test cases. The HorsePartnerships contract was developed using the Diamond pattern. Please see the links below for any further information on this design pattern.
## Setup
1. Install Node Package Manager
   1. https://www.npmjs.com/package/npm
2. Run ```npm install``` in contract folder
## Test
1. To run Harhat coverate test cases execute the following.<br>
   `npm run coverage-tests`
2. To get estimated contract sizes before deployment execute the following.<br>
   `npm run size-contracts`
## Diamond Pattern
### Articles
1. https://medium.com/derivadex/the-diamond-standard-a-new-paradigm-for-upgradeability-569121a08954
2. https://soliditydeveloper.com/eip-2535
3. https://eip2535diamonds.substack.com/p/introduction-to-the-diamond-standard

## Deployment
Perform the following to deploy the contract to the proper environment
1. Create .env file in same folder as hardhat.config.js
2. Add the following to the file<br>
```
ROPSTEN_PRIVATE_KEY={KEY FOR WALLET USED FOR DEPLOYMENT TO TEST NET}   
SILKS_KEY={KEY FOR WALLET USED FOR DEPLOYMENT TO MAIN NET}  
ETHERSCAN_TOKEN={ETHERSCAN API KEY}
```
3. Run deploy command
   1. Dev
      1. Goerli - `npm run deploy-horse-partnerships-dev-goerli`
      2. Sepolia - `npm run deploy-horse-partnerships-dev-sepolia`
   2. QA
      1. Goerli - `npm run deploy-horse-partnerships-qa-goerli`
   3. UAT
      1. Goerli - `npm run deploy-horse-partnerships-uat-goerli`
   4. Prod
      1. Mainnet - `npm run deploy-horse-partnerships-mainnet`

