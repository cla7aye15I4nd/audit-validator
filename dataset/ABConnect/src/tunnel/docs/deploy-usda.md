
- install `nvm` and `node 16.14.0`

```bash
# install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source  ~/.bashrc

# clone and deploy https://github.com/circlefin/stablecoin-evm
git clone https://github.com/circlefin/stablecoin-evm.git -b release-2024-06-21T005221 && cd stablecoin-evm/
git switch -c release-2024-06-21T005221
nvm install 16.14.0
nvm use
npm i -g yarn@1.22.19 # Install yarn if you don't already have it
yarn install          # Install npm packages and other dependencies listed in setup.sh

# forge failed, install handle by download Foundry@f625d0f bin

# deploy
cp .env.example .env # edit .env and charge to deployer
# DEPLOYER_PRIVATE_KEY, The key to a pre-funded deployer address
# TOKEN_NAME: NewUSDT
# TOKEN_SYMBOL: NUSDT
# TOKEN_DECIMALS: 6
# OWNER_ADDRESS and PROXY_ADMIN_ADDRESS MUST difference
echo "[]" > blacklist.remote.json

# simulate
yarn forge:simulate scripts/deploy/deploy-fiat-token.s.sol --rpc-url https://rpc.core.testnet.ab.org/ --legacy

# onchain deploy
yarn forge:broadcast scripts/deploy/deploy-fiat-token.s.sol --rpc-url https://rpc.core.testnet.ab.org/ --legacy

# verify
yarn forge:simulate --verify --verifier blockscout --verifier-url https://explorer.core.testnet.ab.org/api --resume --private-key $(dotenv -p DEPLOYER_PRIVATE_KEY) scripts/deploy/deploy-fiat-token.s.sol --rpc-url https://rpc.core.testnet.ab.org/
```

0: contract FiatTokenV2_2 0x9849b116ce44B64643b9aDb7F8Ed362F7e686cB4
1: contract MasterMinter 0x7B806E58b0a1B27d53A60fa1Aef240b6EAbb7Fb4
2: contract FiatTokenProxy 0xdf72F39AB271ae7b13618468f4801Bb679e6b595

```bash
# config minter for nUSDT
export FiatTokenV2_2=0x9849b116ce44B64643b9aDb7F8Ed362F7e686cB4
export MasterMinter=0x7B806E58b0a1B27d53A60fa1Aef240b6EAbb7Fb4
export FiatTokenProxy=0xdf72F39AB271ae7b13618468f4801Bb679e6b595

# from .env
export PROXY_ADMIN_ADDRESS=0xf5cd557225C74e838E33CEc5A12F40067ec275E9
export OWNER_ADDRESS=0x8fe0b6978b0f6830821Ff2A44c63Cd2A72aee513
export MASTER_MINTER_OWNER_ADDRESS=0x8fe0b6978b0f6830821Ff2A44c63Cd2A72aee513

# config, ABCore_WithdrawMainAddress is for AB Bridge
export MINTER_CONTROLLER_ADDRESS=0x74A095fEcFe139B5dFfF1a73493d98dC910C319E
export ABCore_WithdrawMainAddress=0x89eFDd52af1795C9489a281639464878DB1Ca919

# check owner of MasterMinter
contractcommander -a $MasterMinter view owner -o address

# configureController(address _controller, address _worker)
contractcommander -a $MasterMinter call configureController address $MINTER_CONTROLLER_ADDRESS address $ABCore_WithdrawMainAddress --from $MASTER_MINTER_OWNER_ADDRESS
# configureMinter(uint256 _newAllowance)
contractcommander -a $MasterMinter call configureMinter uint256 1000000000000000000 --from $MINTER_CONTROLLER_ADDRESS

# Mint test
contractcommander -a $FiatTokenProxy call mint address $ABCore_WithdrawMainAddress uint256 1000000 --from $ABCore_WithdrawMainAddress
contractcommander -a $FiatTokenProxy call burn uint256 1000000 --from $ABCore_WithdrawMainAddress
```

== Return ==
0: contract FiatTokenV2_2 0x9849b116ce44B64643b9aDb7F8Ed362F7e686cB4
1: contract MasterMinter 0x7B806E58b0a1B27d53A60fa1Aef240b6EAbb7Fb4
2: contract FiatTokenProxy 0xdf72F39AB271ae7b13618468f4801Bb679e6b595

== Logs ==
  TOKEN_NAME: 'NewUSDT'
  TOKEN_SYMBOL: 'NUSDT'
  TOKEN_CURRENCY: 'USD'
  TOKEN_DECIMALS: '6'
  FIAT_TOKEN_IMPLEMENTATION_ADDRESS: '0x0000000000000000000000000000000000000000'
  PROXY_ADMIN_ADDRESS: '0xf5cd557225C74e838E33CEc5A12F40067ec275E9'
  MASTER_MINTER_OWNER_ADDRESS: '0x8fe0b6978b0f6830821Ff2A44c63Cd2A72aee513'
  OWNER_ADDRESS: '0x8fe0b6978b0f6830821Ff2A44c63Cd2A72aee513'
  PAUSER_ADDRESS: '0x8fe0b6978b0f6830821Ff2A44c63Cd2A72aee513'
  BLACKLISTER_ADDRESS: '0x8fe0b6978b0f6830821Ff2A44c63Cd2A72aee513'