# Sushi Exchange Protocol Specification

## Schema Definitions

### sushi-exchange.pact

```pact
(defschema leg
  token:module{fungible-v2}
  reserve:decimal
)

(defschema pair
  leg0:object{leg}
  leg1:object{leg}
  account:string
  mutex-locked:bool ;; whether the pair is currently locked or not (to prevent reentrancy)
)

(defschema alloc
  token:module{fungible-v2}
  amount:decimal
)
```

### sushi-exchange-tokens.pact

```pact
(defschema entry
  token:string
  account:string
  balance:decimal
  guard:guard
)

(defschema issuer
  guard:guard
)

(defschema supply
  supply:decimal
)
```

### fungible-v2.pact

```pact
(defschema account-details
  @doc "Schema for results of 'account' operation."
  @model [ (invariant (!= "" sender)) ]
  account:string
  balance:decimal
  guard:guard
)
```

### bootstrap/ns.pact

```pact
(defschema reg-entry
  guard:guard
)
```

## Guards

### ADMIN_GUARD

- Defined in constants.pact as `(keyset-ref-guard ADMIN_KEYSET)`
- Used to enforce governance capabilities

## Capabilities

### GOVERNANCE

```pact
(defcap GOVERNANCE ()
  (enforce-guard constants.ADMIN_GUARD))
```

Enforces administrative access control.

### SWAP

```pact
(defcap SWAP
  (sender:string receiver:string in:decimal token-in:module{fungible-v2} out:decimal token-out:module{fungible-v2})
  " Swap event debiting IN of TOKEN-IN from SENDER for OUT of TOKEN-OUT on RECEIVER."
  @event
  true)
```

### UPDATE

```pact
(defcap UPDATE
  (pair:string reserve0:decimal reserve1:decimal)
  "Private defcap updating reserves for PAIR to RESERVE0 and RESERVE1."
  @event
  true)
```

### MUTEX

```pact
(defcap MUTEX ()
  "Private defcap for obtaining pair mutex."
  true)
```

## Events

### Sushi Exchange Events

#### MINT_EVENT

```pact
(defcap MINT_EVENT
  (token:string
   account:string
   amount:decimal)
  @doc "Event emitted when tokens are minted"
  @event true)
```

Emitted when new tokens are minted in the system.

**Parameters:**

- `token:string` - The token being minted
- `account:string` - The account receiving the minted tokens
- `amount:decimal` - The amount of tokens being minted

#### PAIR_CREATED

```pact
(defcap PAIR_CREATED
  (token0:module{fungible-v2}
   token1:module{fungible-v2}
   key:string
   account:string)
  "Pair-created event for TOKEN0 and TOKEN1 pairs with KEY liquidity token and ACCOUNT on leg tokens."
  @event
  true)
```

Emitted when a new trading pair is created.

**Parameters:**

- `token0:module{fungible-v2}` - First token in the pair
- `token1:module{fungible-v2}` - Second token in the pair
- `key:string` - The liquidity token key
- `account:string` - The account for the pair

#### SWAP

```pact
(defcap SWAP
  (sender:string
   receiver:string
   in:decimal
   token-in:module{fungible-v2}
   out:decimal
   token-out:module{fungible-v2})
  "Swap event debiting IN of TOKEN-IN from SENDER for OUT of TOKEN-OUT on RECEIVER."
  @event
  true)
```

Emitted when a swap occurs between tokens.

**Parameters:**

- `sender:string` - The account sending the input tokens
- `receiver:string` - The account receiving the output tokens
- `in:decimal` - The amount of input tokens
- `token-in:module{fungible-v2}` - The input token module
- `out:decimal` - The amount of output tokens
- `token-out:module{fungible-v2}` - The output token module

#### UPDATE

```pact
(defcap UPDATE
  (pair:string
   reserve0:decimal
   reserve1:decimal)
  "Private defcap updating reserves for PAIR to RESERVE0 and RESERVE1."
  @event
  true)
```

Emitted when the reserves of a trading pair are updated.

**Parameters:**

- `pair:string` - The trading pair identifier
- `reserve0:decimal` - The new reserve amount for the first token
- `reserve1:decimal` - The new reserve amount for the second token

### Coin Module Events

#### TRANSFER

```pact
(defcap TRANSFER
  (sender:string
   receiver:string
   amount:decimal
   source-chain:string)
  @event true
)
```

Emitted when a transfer occurs between accounts.

**Parameters:**

- `sender:string` - The account sending the coins
- `receiver:string` - The account receiving the coins
- `amount:decimal` - The amount being transferred
- `source-chain:string` - The source chain identifier

#### RELEASE_ALLOCATION

```pact
(defcap RELEASE_ALLOCATION
  (account:string
   amount:decimal)
  @doc "Event for allocation release, can be used for sig scoping."
  @event true
)
```

Emitted when an allocation is released.

**Parameters:**

- `account:string` - The account releasing the allocation
- `amount:decimal` - The amount being released

### Fungible XChain Events

#### RECEIVE

```pact
(defcap RECEIVE
  (sender:string
   receiver:string
   amount:decimal
   source-chain:string)
  @doc "Event emitted on receipt of cross-chain transfer."
  @event
)
```

Emitted when a cross-chain transfer is received.

**Parameters:**

- `sender:string` - The account sending the tokens
- `receiver:string` - The account receiving the tokens
- `amount:decimal` - The amount being transferred
- `source-chain:string` - The source chain identifier

## Constants

### MINIMUM_LIQUIDITY

```pact
(defconst MINIMUM_LIQUIDITY 0.1)
```

Minimum liquidity required to initialize a pool

### FEE

```pact
(defconst FEE 0.003)
```

Trading fee of 0.3%

## Implementation Notes

The contract implements an automated market maker (AMM) with:

- Pair creation and liquidity management
- Constant product formula (x \* y = k)
- Trading fee of 0.3%
- Reentrancy protection via mutex
- Event emission for swaps and reserve updates
- Support for fungible token standard

## Function Documentation

### Sushi Exchange Tokens Module

#### Account Management Functions

<details>
<summary>create-account</summary>

```pact
(defun create-account:string (token:string account:string guard:guard))
```

Creates a new token account with the specified guard.

**Arguments:**

- `token:string` - The token identifier
- `account:string` - The account name
- `guard:guard` - The guard to protect the account

**Returns:** string - The created account name

</details>

<details>
<summary>rotate</summary>

```pact
(defun rotate:string (token:string account:string new-guard:guard))
```

Rotates the guard for an existing account.

**Arguments:**

- `token:string` - The token identifier
- `account:string` - The account name
- `new-guard:guard` - The new guard to set

**Returns:** string - The account name

</details>

<details>
<summary>details</summary>

```pact
(defun details (token:string account:string))
```

Gets the details of a token account.

**Arguments:**

- `token:string` - The token identifier
- `account:string` - The account name

**Returns:** object containing account details

</details>

#### Token Operations

<details>
<summary>init-issuer</summary>

```pact
(defun init-issuer (guard:guard))
```

Initializes the token issuer with the specified guard.

**Arguments:**

- `guard:guard` - The guard for the issuer

**Returns:** void

</details>

<details>
<summary>override-issuer</summary>

```pact
(defun override-issuer (guard:guard))
```

Overrides the existing token issuer guard.

**Arguments:**

- `guard:guard` - The new guard for the issuer

**Returns:** void

</details>

<details>
<summary>key</summary>

```pact
(defun key (token:string account:string))
```

Gets the key for a token account.

**Arguments:**

- `token:string` - The token identifier
- `account:string` - The account name

**Returns:** string - The account key

</details>

<details>
<summary>total-supply</summary>

```pact
(defun total-supply:decimal (token:string))
```

Gets the total supply of a token.

**Arguments:**

- `token:string` - The token identifier

**Returns:** decimal - The total supply

</details>

<details>
<summary>precision</summary>

```pact
(defun precision:integer (token:string))
```

Gets the precision of a token.

**Arguments:**

- `token:string` - The token identifier

**Returns:** integer - The token precision

</details>

<details>
<summary>get-tokens</summary>

```pact
(defun get-tokens ())
```

Gets the list of all tokens.

**Arguments:** None

**Returns:** [string] - List of token identifiers

</details>

#### Transfer Operations

<details>
<summary>transfer</summary>

```pact
(defun transfer:string (token:string from:string to:string amount:decimal))
```

Transfers tokens between accounts.

**Arguments:**

- `token:string` - The token identifier
- `from:string` - The source account
- `to:string` - The destination account
- `amount:decimal` - The amount to transfer

**Returns:** string - Transaction result

</details>

<details>
<summary>transfer-create</summary>

```pact
(defun transfer-create:string (token:string from:string to:string to-guard:guard amount:decimal))
```

Transfers tokens to a new account, creating it if it doesn't exist.

**Arguments:**

- `token:string` - The token identifier
- `from:string` - The source account
- `to:string` - The destination account
- `to-guard:guard` - The guard for the new account
- `amount:decimal` - The amount to transfer

**Returns:** string - Transaction result

</details>

<details>
<summary>transfer-crosschain</summary>

```pact
(defpact transfer-crosschain:string (token:string from:string to:string amount:decimal))
```

Transfers tokens across chains.

**Arguments:**

- `token:string` - The token identifier
- `from:string` - The source account
- `to:string` - The destination account
- `amount:decimal` - The amount to transfer

**Returns:** string - Transaction result

</details>

<details>
<summary>TRANSFER-mgr</summary>

```pact
(defun TRANSFER-mgr:decimal (token:string from:string to:string amount:decimal))
```

Transfer capability manager function.

**Arguments:**

- `token:string` - The token identifier
- `from:string` - The source account
- `to:string` - The destination account
- `amount:decimal` - The amount to transfer

**Returns:** decimal - The transfer amount

</details>

#### Minting and Burning

<details>
<summary>mint</summary>

```pact
(defun mint:string (token:string to:string amount:decimal))
```

Mints new tokens.

**Arguments:**

- `token:string` - The token identifier
- `to:string` - The recipient account
- `amount:decimal` - The amount to mint

**Returns:** string - Transaction result

</details>

<details>
<summary>burn</summary>

```pact
(defun burn:string (token:string account:string amount:decimal))
```

Burns tokens from an account.

**Arguments:**

- `token:string` - The token identifier
- `account:string` - The account to burn from
- `amount:decimal` - The amount to burn

**Returns:** string - Transaction result

</details>

<details>
<summary>update-supply</summary>

```pact
(defun update-supply (token:string amount:decimal))
```

Updates the token supply.

**Arguments:**

- `token:string` - The token identifier
- `amount:decimal` - The new supply amount

**Returns:** void

</details>

#### Balance Operations

<details>
<summary>get-balance</summary>

```pact
(defun get-balance:decimal (token:string account:string))
```

Gets the token balance of an account.

**Arguments:**

- `token:string` - The token identifier
- `account:string` - The account name

**Returns:** decimal - The account balance

</details>

<details>
<summary>debit</summary>

```pact
(defun debit:string (token:string account:string amount:decimal))
```

Debits tokens from an account.

**Arguments:**

- `token:string` - The token identifier
- `account:string` - The account to debit from
- `amount:decimal` - The amount to debit

**Returns:** string - Transaction result

</details>

<details>
<summary>credit</summary>

```pact
(defun credit:string (token:string account:string amount:decimal))
```

Credits tokens to an account.

**Arguments:**

- `token:string` - The token identifier
- `account:string` - The account to credit
- `amount:decimal` - The amount to credit

**Returns:** string - Transaction result

</details>

#### Utility Functions

<details>
<summary>enforce-unit</summary>

```pact
(defun enforce-unit:bool (token:string amount:decimal))
```

Enforces that an amount is a valid unit for the token.

**Arguments:**

- `token:string` - The token identifier
- `amount:decimal` - The amount to validate

**Returns:** bool - True if amount is valid

</details>

<details>
<summary>truncate</summary>

```

```

</details>

## Deployment Process

This section outlines the step-by-step process for deploying the Sushi Exchange contracts to the Kadena blockchain.

### Prerequisites

Before starting the deployment process, ensure you have the following environment variables configured in your `.env` file:

```bash
# Namespace (will be created during deployment)
NS=n_82274f03ce7df5c0ea6c3d5766b535a7a748a552

# Keys for deployment and account creation
ADMIN_KEYSET=b636f3b3ed301ea9c76d46334be4e1ded94293e2b2ad0ca4e2f8649d20b64ef9
PUB_KEY=b636f3b3ed301ea9c76d46334be4e1ded94293e2b2ad0ca4e2f8649d20b64ef9

# Secret key for contract deployment
SECRET_KEY=6b514a5e6b3b8b37197f73cf3e68c96edf141cd7f9cf9830d0afb8e910798fa6

# Network configuration
NETWORK_ID=mainnet01
CHAIN_ID=2
IS_MAINNET=true
```

**Important Notes:**

- `ADMIN_KEYSET` and `PUB_KEY` are the public keys used for deploying contracts and creating accounts
- `SECRET_KEY` is the secret key used for contract deployment
- `CHAIN_ID` determines which chain the contracts will be deployed on (1 or 2)
- The deployment process involves deploying to both chains sequentially

### Deployment Steps

#### Step 1: Create Namespace

Start the deployment process by creating a namespace:

```bash
npm run deploy:ns
```

This command will:

- Create a new namespace for your contracts
- Return the created namespace identifier
- Update the `NS` value in your `.env` file with the new namespace

#### Step 2: Deploy Utility Modules

Deploy the necessary utility modules that the main contracts depend on:

```bash
npm run deploy:utilities
```

This deploys foundational modules required by the exchange contracts.

#### Step 3: Deploy Exchange Tokens Contract

Deploy the exchange tokens contract:

```bash
npm run deploy:exchange-tokens
```

This contract handles token management for the exchange. The deployment script automatically creates the necessary tables within the contract.

#### Step 4: Deploy Main Exchange Contract

Deploy the main exchange contract:

```bash
npm run deploy:exchange
```

This is the core exchange contract that handles trading pairs and swaps. The deployment script automatically creates the required tables within the contract.

### Multi-Chain Deployment

The contracts need to be deployed on both chains (Chain 1 and Chain 2). Follow these steps:

#### Initial Deployment (Chain 1)

1. Set `CHAIN_ID=1` in your `.env` file
2. Run all deployment steps (Steps 1-4 above)

#### Secondary Deployment (Chain 2)

1. Update `CHAIN_ID=2` in your `.env` file
2. Re-run the utility and contract deployments:
   ```bash
   npm run deploy:utilities
   npm run deploy:exchange-tokens
   npm run deploy:exchange
   ```

**Note:** The namespace creation (`npm run deploy:ns`) only needs to be done once, as namespaces are shared across chains.

### Available Scripts

The following npm scripts are available for deployment and management:

```json
{
	"scripts": {
		"deploy:ns": "tsx deploy/ns.ts",
		"deploy:utilities": "tsx deploy/utilities.ts",
		"deploy:exchange-tokens": "tsx deploy/sushi-exchange-tokens.ts",
		"deploy:exchange": "tsx deploy/sushi-exchange.ts",
		"create:account": "tsx deploy/create-account.ts",
		"add:liquidity": "tsx deploy/add-liquidity.ts",
		"set:pair-open-date": "tsx deploy/set-pair-open-date.ts",
		"swap": "tsx deploy/swap.ts"
	}
}
```

### Post-Deployment

After successful deployment, you can use the additional scripts for:

- **Account Creation**: `npm run create:account` - Create new accounts
- **Liquidity Management**: `npm run add:liquidity` - Add liquidity to trading pairs
- **Pair Configuration**: `npm run set:pair-open-date` - Set opening dates for trading pairs
- **Trading**: `npm run swap` - Execute token swaps

### Troubleshooting

- Ensure all environment variables are properly set before running deployment scripts
- Verify that your keys have sufficient permissions for the target network
- Check that the namespace is created successfully before proceeding with contract deployments
- Monitor transaction logs for any deployment errors
- Ensure you have sufficient KDA balance for deployment gas fees
