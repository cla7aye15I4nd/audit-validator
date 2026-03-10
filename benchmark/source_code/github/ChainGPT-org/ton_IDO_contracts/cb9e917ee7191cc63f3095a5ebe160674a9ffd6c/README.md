# ton_IDO_contracts

## Project structure

-   `contracts` - source code of all the smart contracts of the project and their dependencies.
-   `wrappers` - wrapper classes (implementing `Contract` from ton-core) for the contracts, including any [de]serialization primitives and compilation functions.
-   `tests` - tests for the contracts.
-   `scripts` - scripts used by the project, mainly the deployment scripts.

## How to use

### Build

`npx blueprint build` or `yarn blueprint build`

### Test

`npx blueprint test` or `yarn blueprint test`

### Deploy or run another script

`npx blueprint run` or `yarn blueprint run`

### Add a new contract

`npx blueprint create ContractName` or `yarn blueprint create ContractName`

# Notes

## Storage Structure
__cell0__:
id: uint: 32,
factory: address: 267,
owner: address: 267,
signer: uint: 256,
openTime: uint: 32,
closeTime: uint: 32

__cell000__:
sellTokenAccountAddr: address: 267,
sellTokenMint: address: 267,
sellTokenAccountBalance: uint: 132
fundingWallet: address: 267,

__cell001__:
tokenSold: uint: 132
totalUnclaimed: uint: 132,
totalRefunded: uint: 132
zeroAddress: address: 267

__cell01__:
per user, per buy: dict: 1 ref
	sellCurrBought: uint: 132,
	buyCurrSold: uint: 132,
	refundAmount: uint: 132,
	isClaimed: int: 1

__cell02__:
per user: dict: 1 ref
	sellCurrBought: uint: 132,
	sellCurrClaimed: uint: 132

__cell03__:
per buy: dict: 1 ref
	buyCurrRaised: uint: 132,
	buyCurrRefundedTotal: uint: 132,
	buyCurrRefundedLeft: uint: 132,
__cell030__:
	buyCurrMintAddr: Addr: 267
	buyCurrDecimals: uint: 8,
	buyCurrRate: uint: 132,
	buyCurrBalance: uint: 132,
	buyCurrTokenAccountAddr: Addr: 267


## TODO
- Token by ton swap. Done
- Event emission methods. TODO on methods to be added
- Error handling proper. NEED TO CHECK THIS ONCE AT END
- Change isClaimed name to isRefundClaimed. Done
- Manage gas cost. manage the case where ton gets added to balance when excessive (more than the amount used for gas) ton are sent to contract. DONE
- Add change sale token + refund remaining tokens + refund remaining ton with events. DONE
- Set perbuycurr should update token account as well. Done