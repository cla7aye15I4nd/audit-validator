# Blockchain Contract Overview
This project provides ethereum compatible smart contracts written in Solidity

## Primary Contracts

Contracts:
* `Vault` - Primary contract for proposal creation and access control management via roles
* `Crt`   - An ERC-1155 token for asset ownership per instrument - 1 contract instance for all instruments

## Utility Contracts

### Managers
These solve 2 goals:
1) *Primary*: Ensure each contract is within the 24 KiB bytecode limit by distributing size
2) *Secondary*: Modularize functionality

Manager Contracts:
* `TransferMgr` - Transfer proposal
* `RevMgr` - Ledgering of revenue per stream, instrument name and/or earn date, and manages revenue claims per owner
* `InstRevMgr` - Instrument revenue proposal
* `BalanceMgr` - Focuses on instrument revenue proposals and management of inst revenue and ownership per inst earn date
* `EarnDateMgr` - Allows a caller to enumerate instruments, earn dates, and combinations of each
* `BoxMgr` - Manages box CRUD and approvals, allows many revenue streams with separate inbound addresses

Because these contracts are co-dependent, each has a reference to the others (like a mesh) although the on-chain call-graph between is mostly top-down from Vault or exercised from off-chain calls (mostly via Vault but some direct manager accesses for contract-size reasons).

Other Contracts:
* `ContractUser` - Abstract contract to ensure each contract has manager references
* `Box` - Allows a separate deposit address per revenue stream managed by the owner (aka drop box or deposit address)
* `DeployerVault` - Used during deploy for contract setup

## More Solidity Docs
To get an [HTML markup](./doc/how-to-gen-sol-doc.png) version of the documentation, [example doc](./doc/sol-doc-example.png):
```bash
cd bd/bc-contract
script/gen-sol-doc.sh
```

## File structure
```bash
bc-contract/
├── abi/                   # Generated Application Binary Interface files
├── contract/              # Solidity core contracts
├── lib/                   # Downloaded solidity contract depends
├── ut/                    # Solidity unit tests using Foundry
└── script/                # Scripts to be run from the project dir
    ├── build.sh           # Builds solidity code
    ├── gen-sol-doc.sh     # Generates HTML documentation and runs a server for web-browser exploration
    ├── sa.sh              # Run static analysis
    ├── ut.sh              # Run all unit tests
    └── it.sh              # Run all integration tests
```

## Client
`ts-vault` is a related project that provides a TypeScript (TS) API mostly generated from solidity contracts.

See `ts-vault/script/deploy.ts` for deploy info

# Install depends

Solidity:
* Ensure solidity compiler (solc) is installed (no script yet)
* Install Foundry (contains Anvil): `./script/install-foundry.sh`

The following versions may move beyond this file but for now:
```bash
$ bash --version
GNU bash, version 5.2.21(1)-release (x86_64-pc-linux-gnu)

$ bash --version
GNU bash, version 5.3.3(1)-release (aarch64-apple-darwin25.0.0)

$ solc --version
solc, the solidity compiler commandline interface
Version: 0.8.30 ...Linux... (Version 0.8.31 is available now but the checksum is broken)

$ solc --version
solc, the solidity compiler commandline interface
Version: 0.8.30 ...Darwin...

$ anvil --version
anvil Version: 1.3.6-v1.3.6

$ pnpm --version
10.25.0

$ pnpm tsx --version
tsx v4.20.6
node v25.1.0
```

## Solidity install notes
Overview at https://docs.soliditylang.org/en/v0.8.30/installing-solidity.html

### Tools
Links:
* https://docs.soliditylang.org/en/latest/installing-solidity.html

### Mac
```bash
brew update
brew upgrade
brew tap ethereum/ethereum
brew install solidity
```

### Linux
These would be better wrapped with docker:
```bash
sudo apt upgrade
sudo apt install python3-pip
pip3 install solc-select --break-system-packages
# pip3 install slither-analyzer --break-system-packages
```

## Building

```bash
$ pnpm build

> @gs/bc-contract@1.0.0 build ~/code/gs/bd/bc-contract
> ./script/build.sh


2025-12-11T10:18:00Z: INFO : build started with args:
2025-12-11T10:18:00Z: INFO : ensuring libs...
lib found, skipping clone: lib/forge-std
lib found, skipping clone: lib/openzeppelin-contracts
lib found, skipping clone: lib/openzeppelin-contracts-upgradeable
2025-12-11T10:18:00Z: INFO : solidity build...
2025-12-11T10:18:00Z: INFO : building release contracts for size
[⠊] Compiling...
[⠒] Files to compile:
...
[⠊] Compiling 80 files with Solc 0.8.30
[⠆] Solc 0.8.30 finished in 14.89s
Compiler run successful!
...

2025-12-11T10:18:15Z: INFO : build completed in 15s
```

## Running Tests
Contracts have unit tests using Foundry/Anvil written in Solidity

```bash
$ pnpm test

> @gs/bc-contract@1.0.0 test ~/code/gs/bd/bc-contract
> ./script/ut.sh


2025-12-11T10:22:22Z: INFO : build started with args:
2025-12-11T10:22:22Z: INFO : ensuring libs...
lib found, skipping clone: lib/forge-std
lib found, skipping clone: lib/openzeppelin-contracts
lib found, skipping clone: lib/openzeppelin-contracts-upgradeable
2025-12-11T10:22:22Z: INFO : solidity build...
2025-12-11T10:22:22Z: INFO : building release contracts for size
[⠊] Compiling...
No files changed, compilation skipped
...

2025-12-11T10:22:23Z: INFO : build completed in 1s

2025-12-11T10:22:23Z: INFO : unit tests:
2025-12-11T10:22:23Z: INFO : building test contracts concurrently
[⠊] Compiling...
[⠒] Compiling 91 files with Solc 0.8.30
[⠃] Solc 0.8.30 finished in 43.13s
Compiler run successful!

Ran 1 test for test/LogicDeployer.t.sol:LogicDeployerTest
[PASS] test_LogicDeployer() (gas: 164196)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 286.51µs (88.01µs CPU time)

Ran 3 tests for test/LibraryUtil.t.sol:UtilTest
[PASS] test_Util_getRangeLen() (gas: 12566)
[PASS] test_Util_requireSameArrayLength() (gas: 1153)
[PASS] test_Util_resolveAddr() (gas: 17112)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 390.87µs (156.24µs CPU time)

Ran 2 tests for test/LibraryOI.t.sol:OI_OwnSnap_Test
[PASS] test_OI_OwnSnap_addOwnerToSnapshot() (gas: 271448)
[PASS] test_OI_OwnSnap_initialized() (gas: 4467)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 465.97µs (211.04µs CPU time)

Ran 1 test for test/ProxyDeployer.t.sol:ProxyDeployerTest
[PASS] test_ProxyDeployer() (gas: 1607570)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 370.83µs (222.51µs CPU time)

Ran 1 test for test/ContractUser.t.sol:CachedRoleContractUserTest
[PASS] test_CachedRoleContractUser() (gas: 84732)
Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 859.54µs (123.07µs CPU time)

Ran 2 tests for test/LibraryEMAP.t.sol:EmapBytes32Bytes32Test
[PASS] test_Emap_BB_add_remove() (gas: 496921)
[PASS] test_Emap_BB_initialized() (gas: 6904)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 1.22ms (961.96µs CPU time)

Ran 2 tests for test/String.t.sol:StringTest
[PASS] test_String_bytes32_string_roundtrip() (gas: 331097)
[PASS] test_String_toBytes32_roundtrip() (gas: 188395)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 1.50ms (1.44ms CPU time)

Ran 2 tests for test/LibraryARI.t.sol:ARI_AccountRoleInfo_Test
[PASS] test_ARI_ari_add_remove() (gas: 817872)
[PASS] test_ARI_ari_reverts() (gas: 940067)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 1.86ms (1.50ms CPU time)

Ran 7 tests for test/LibraryAC.t.sol:AC_AccountMgr_Test
[PASS] test_AC_adminGrantStep2_accept() (gas: 2637922)
[PASS] test_AC_adminGrantStep2_reject() (gas: 2514728)
[PASS] test_AC_mgr_add_remove_account_calldata() (gas: 2581069)
[PASS] test_AC_mgr_add_remove_account_storage() (gas: 2658628)
[PASS] test_AC_mgr_duplicate_admin_add() (gas: 2598568)
[PASS] test_AC_mgr_init() (gas: 3131551)
[PASS] test_AC_mgr_setQuorum() (gas: 2497872)
Suite result: ok. 7 passed; 0 failed; 0 skipped; finished in 3.06ms (5.62ms CPU time)

Ran 3 tests for test/ContractUser.t.sol:ContractUserTest
[PASS] test_ContractUser_false() (gas: 373171)
[PASS] test_ContractUser_getContract() (gas: 333688)
[PASS] test_ContractUser_requireVaultOrAdminOrCreator() (gas: 240713)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 4.48ms (1.78ms CPU time)

Ran 2 tests for test/LibraryEMAP.t.sol:EmapUintUintTest
[PASS] test_Emap_UU_add_remove() (gas: 443325)
[PASS] test_Emap_UU_initialized() (gas: 6942)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 4.72ms (636.28µs CPU time)

Ran 2 tests for test/LibraryBI.t.sol:BI_Emap_Test
[PASS] test_BI_emap_add_remove() (gas: 2889181)
[PASS] test_BI_emap_initialized() (gas: 1567080)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 6.07ms (5.71ms CPU time)

Ran 10 tests for test/Crt.t.sol:CrtTest
[PASS] test_Crt_initialize_again() (gas: 4524987)
[PASS] test_Crt_isApprovedForAll_setApprovalForAll() (gas: 161303)
[PASS] test_Crt_proxy_initialize() (gas: 4699462)
[PASS] test_Crt_requireXferAuth() (gas: 101840)
[PASS] test_Crt_safeBatchTransferFrom() (gas: 414796)
[PASS] test_Crt_safeTransferFrom() (gas: 818420)
[PASS] test_Crt_setUri() (gas: 188433)
[PASS] test_Crt_supply_and_balance_no_tokens() (gas: 72462)
[PASS] test_Crt_supportsInterface() (gas: 13407)
[PASS] test_Crt_upgrade() (gas: 9123881)
Suite result: ok. 10 passed; 0 failed; 0 skipped; finished in 6.43ms (6.02ms CPU time)

Ran 16 tests for test/Box.t.sol:BoxTest
[PASS] test_Box_IERC165() (gas: 3435401)
[PASS] test_Box_addOwner() (gas: 3534750)
[PASS] test_Box_approve_erc20_fail() (gas: 3568969)
[PASS] test_Box_approve_erc20_success() (gas: 3952022)
[PASS] test_Box_approve_fail_tokType() (gas: 3499170)
[PASS] test_Box_create() (gas: 3486709)
[PASS] test_Box_fallback() (gas: 3437113)
[PASS] test_Box_getOwners() (gas: 3519341)
[PASS] test_Box_initialize() (gas: 3218422)
[PASS] test_Box_push_erc20() (gas: 3629245)
[PASS] test_Box_push_fail_caller_burn() (gas: 3497874)
[PASS] test_Box_push_fail_tokType() (gas: 3474499)
[PASS] test_Box_push_nativeCoin() (gas: 3545277)
[PASS] test_Box_receive_1155() (gas: 3436037)
[PASS] test_Box_receive_native() (gas: 3434854)
[PASS] test_Box_removeOwner() (gas: 3519501)
Suite result: ok. 16 passed; 0 failed; 0 skipped; finished in 3.00ms (8.06ms CPU time)

Ran 3 tests for test/BalanceMgr.t.sol:BalanceMgrTest
[PASS] test_BalanceMgr_initialize() (gas: 22687)
[PASS] test_BalanceMgr_misc() (gas: 532264)
[PASS] test_BalanceMgr_upgrade() (gas: 3264113)
Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 3.52ms (2.03ms CPU time)

Ran 4 tests for test/BoxMgr.t.sol:BoxMgrTest
[PASS] test_BoxMgr_addBoxLogic() (gas: 7209218)
[PASS] test_BoxMgr_addBox_misc() (gas: 11771045)
[PASS] test_BoxMgr_initialize() (gas: 84109)
[PASS] test_BoxMgr_upgrade() (gas: 5967019)
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 10.60ms (9.48ms CPU time)

Ran 7 tests for test/LibraryIR.t.sol:IR_Emap_Test
[PASS] test_IR_emap_add_prevent_dups() (gas: 3954217)
[PASS] test_IR_emap_add_remove_cd() (gas: 7676995)
[PASS] test_IR_emap_add_remove_store() (gas: 8019233)
[PASS] test_IR_emap_initialized() (gas: 3670193)
[PASS] test_IR_getInstRevs() (gas: 6223970)
[PASS] test_IR_getInstRevsLen_cd() (gas: 5451361)
[PASS] test_IR_getInstRevsLen_store() (gas: 5678978)
Suite result: ok. 7 passed; 0 failed; 0 skipped; finished in 14.50ms (31.47ms CPU time)

Ran 9 tests for test/XferMgr.t.sol:XferMgrTest
[PASS] test_XferMgr_empty_state() (gas: 84260)
[PASS] test_XferMgr_getTokenBalances() (gas: 219655)
[PASS] test_XferMgr_initialize() (gas: 23171)
[PASS] test_XferMgr_prop_create_basic() (gas: 237569)
[PASS] test_XferMgr_prop_create_crt() (gas: 3531259)
[PASS] test_XferMgr_prop_create_native() (gas: 1437436)
[PASS] test_XferMgr_prop_create_usdc() (gas: 3050689)
[PASS] test_XferMgr_upgrade() (gas: 6271122)
[PASS] test_XferMgr_xferFieldsCheck() (gas: 6267821)
Suite result: ok. 9 passed; 0 failed; 0 skipped; finished in 15.87ms (13.24ms CPU time)

Ran 4 tests for test/LibraryOI.t.sol:OI_Emap_Test
[PASS] test_OI_emap_add_and_upsert() (gas: 375375)
[PASS] test_OI_emap_initialized() (gas: 4201)
[PASS] test_OI_emap_remove() (gas: 765312)
[PASS] test_OI_getSnapshot() (gas: 329606)
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 16.68ms (1.85ms CPU time)

Ran 5 tests for test/RevMgr.t.sol:RevMgrTest
[PASS] test_RevMgr_empty_state() (gas: 100626)
[PASS] test_RevMgr_initialize() (gas: 22797)
[PASS] test_RevMgr_prop_create() (gas: 7330270)
[PASS] test_RevMgr_prop_prune() (gas: 5911192)
[PASS] test_RevMgr_upgrade() (gas: 6499530)
Suite result: ok. 5 passed; 0 failed; 0 skipped; finished in 18.20ms (14.94ms CPU time)

Ran 7 tests for test/InstRevMgr.t.sol:InstRevMgrTest
[PASS] test_InstRevMgr_empty_state() (gas: 156149)
[PASS] test_InstRevMgr_initialize() (gas: 23192)
[PASS] test_InstRevMgr_prop_create() (gas: 6121288)
[PASS] test_InstRevMgr_prop_fixes() (gas: 3826082)
[PASS] test_InstRevMgr_prop_prune() (gas: 1926204)
[PASS] test_InstRevMgr_upgrade() (gas: 7044711)
[PASS] test_InstRevMgr_validateInstRev() (gas: 18459388)
Suite result: ok. 7 passed; 0 failed; 0 skipped; finished in 18.78ms (17.54ms CPU time)

Ran 15 tests for test/Vault.t.sol:VaultTest
[PASS] test_Vault_IPausable() (gas: 183673)
[PASS] test_Vault_IRoleMgr() (gas: 80600)
[PASS] test_Vault_fixDeposit_prop() (gas: 2100951)
[PASS] test_Vault_initial_state() (gas: 331712)
[PASS] test_Vault_initialize() (gas: 23470)
[PASS] test_Vault_instRev_prop() (gas: 1412930)
[PASS] test_Vault_offChainSig() (gas: 121225)
[PASS] test_Vault_quorum_prop() (gas: 3131833)
[PASS] test_Vault_role_prop() (gas: 1443376)
[PASS] test_Vault_upgrade() (gas: 8970373)
[PASS] test_Vault_xfer_1155() (gas: 1418568)
[PASS] test_Vault_xfer_crt() (gas: 1418854)
[PASS] test_Vault_xfer_eth() (gas: 1373907)
[PASS] test_Vault_xfer_eurc() (gas: 1396638)
[PASS] test_Vault_xfer_usdc() (gas: 1394045)
Suite result: ok. 15 passed; 0 failed; 0 skipped; finished in 27.39ms (30.20ms CPU time)

Ran 4 tests for test/EarnDateMgr.t.sol:EarnDateMgrTest
[PASS] test_EarnDateMgr_getInstNames_gas() (gas: 11217321)
[PASS] test_EarnDateMgr_initialize() (gas: 22858)
[PASS] test_EarnDateMgr_misc() (gas: 1822200)
[PASS] test_EarnDateMgr_upgrade() (gas: 3901335)
Suite result: ok. 4 passed; 0 failed; 0 skipped; finished in 122.99ms (125.63ms CPU time)

Ran 23 test suites in 123.98ms (283.24ms CPU time): 112 tests passed, 0 failed, 0 skipped (112 total tests)
2025-12-11T10:23:08Z: INFO : runtime: 45s
```

Unit test code coverage insights at:
* `~/code/gs/bd/bc-contract/test/forge-coverage-html/contract/v1_0/contracts/v1_0/index.html`
generated via
```bash
./script/ut.sh coverage
```

Integration tests are provided by `ts-vault` tests

# Comment labels
The following labels are referenced in the code but moved here to keep the code more concise:

## From Vault:
**UUPS_UPGRADE_SEQ**: To upgrade a UUPSUpgradeable contract, follow the sequence:
  1) Increase `Version` (eg 10 => 11 - does not have to be monotonic but must increase)
  2A) If state needs to be initialized during upgrade:
     Add a new func, optionally with inputs, and the version in 2 places (name suffix, modifier):
         function initV11(uint newParam1, uint newParam2) external reinitializer(Version) {}
     NOTE: The previous line has 'reinitializer' not 'initializer'
     Remove prior upgrade init funcs, if any
     Deploy the new logic contract and then on the proxy call:
        upgradeToAndCall(address logicAddr, bytes calldata data)
  2B) If no state to update, do not add a new init func
     Deploy the new logic contract and then on the proxy call: upgradeTo(address logicAddr)
For more info see comments in 'Initializable.sol'

**STRING_NOTE**: Having a `string note` field on Proposal with related func params and a 31 byte limit was 0.947 KiB

**STRING_SLOTS**: String lengths based on slots used:
* 1 slot  [0-31] chars - Slot 0 has char [0-31]
* 3 slot [32-63] chars - Slot 0 has length and data pointer, Slot 1 has char [0-31], Slot 2 has char [32-63]
* 4 slot [64-95] chars - Same as prev but Slot 3 has char [64-95]

**MEM_LAYOUT**: Fields are tightly packed to minimize slot use where possible for efficiency with respect to both
contract size and gas usage - sometimes competing goals where contract size generally takes priority. Because a
the native EVM word size is a slot, attempts to use less memory are often thwarted by wrap/unwrap costs and often
not obvious in the contract directly. Memory for common types:
* 1 byte: uint8, enum, bool, bytes8
* 8 byte: uint64, bytes64
* 20 bytes: address
* 1 slot (32 bytes, 256 bits): int, uint, mapping, bytes32, string (if < 32 bytes)

**UINT_ROLLOVER**: At 1 increment/sec,  uint.max = 2^256 ≈ 1.158e+77 sec ÷ (60 × 60 × 24 × 365.25) ≈ 3.67e+69 years
which is effectively infinite compared to the current age of the universe ≈ 13.8 Billion years ≈ 1.38e+10 years
This also justifies `unchecked` being used on all uint ++ increments

**NONCE_SEED**: The seed is important to prevent replay attacks by preventing duplicate seeds.
1) If seed is 0 then an account add/replace/add has an overlapping nonce range
2) If seed is block.timestamp then its fitness depends on whether the nonce consumption rate > 1 Hz.
3) If seed is 0 and persists across add/replace/add then an overlapping range is not possible, see UINT_ROLLOVER.
   This technique's fitness depends on whether the unbounded nonces to track is practically low.
4) A combination of techniques 2 and 3 with a limit on nonces to track is also possible but getting heavy.
5) If seed is always the 'peak value' used then there is no possibility for overlap and minimal resource usage.

**SENTINEL_ADDRESS**: A sentinel address translation layer exists for multiple reasons.
* The native mint/burn AddrZero is a bad design choice since it corresponds to a zero-init value in most langs
   and adds risk of both unintended asset loss and resulting asset value inflation. Consequently ERC20 standards
   introduce mint/burn functions to make such actions more explicit - complicating designs.
   A max value for an address (`MaxAddress`) is otherwise better for a mint/burn address:
   address(0xffffffffffffffffffffffffffffffffffffffff)

**PROP_STATUS**: Final/terminal states occur first in the enum, basically in reverse-chrono order to ensure:
* The finality of a Status can be determined based on a PropStatus.FinalPartition value (less code/gas)
* A zero-value of None - If the values were in chrono order then None would be in the transient group
`Deleting` is an awkward case, more terminal than final

**LOGICAL_ERROR_Ok**: Reverts lose all gas so in some cases it's better to not revert with a no-op or return code. This
can happen in cases where idempotency is provided via no-op to allow for a lost return code due to a retry after
a network error where an operation was successful on-chain but the response was lost or misreported as failure.

**PAGE_REQUESTS**: Caller should page requests as needed. This comment applies to functions with loops that
could cause high gas usage if allowed to scan to a high upper bound relative to the cost of an iteration. The
caller must page such requests to avoid out-of-gas usage errors or memory pool filtering associated with high gas.
Some functions may self-throttle and cleanup when low on gas to make best-effort progress and avoid wasted gas

**BLOCK_TIMESTAMP**: block.timestamp is used only for governance proposal expiration, not funds or pricing. EIP-712
also relies on this in secure protocols. Validators can only skew the time by about 15 seconds which is
insignificant in this contract.

**ACCOUNT_ACCESS_LIST**: Account vetting (roles, sender, recipient) are enforced upstream/offchain.
This reduces on-chain complexity and includes checks such as KYC, AML, OFAC, etc

**MALICIOUS_TRANSFERS**: relate to effects from malicious contract-wallets (MCW) or tokens via external transfer
   calls like (.transfer .safeTransferFrom .call) and may be grouped into 3 risks:
1) Reentrancy risk: eliminated via access control modifiers. This risk depends on several factors such as:
   A) Token code, B) Token usage, C) contract-wallet with malicious code. Currently the USDC contract does not
   invoke recipient code so that's a substantial benefit but that could change in the future or another token
   could be used to transfer assets, so mitigation is required.
2) An intentional revert: Reverts are handled by try/catch
3) Intentional max gas usage will fail a tx and must be mitigated off-chain by the caller. Strategies:
   A) Preemptively: Simulate a batch to bad transfers and take avoiding actions
   B) Reactively: After a tx fails progress can be made via:
       A) Remove bad xfer(s) from the execution path and retry. Identifying bad transfers has many strategies:
          i) Offline simulation could isolate the issue via search or iterative single transfers.
          ii) An account reputation heuristic could possibly optimize the search such as by focusing the search on
              accounts with the least number of successful transfers.
       B) Log bad transfers and pursue off-chain remedies asynchronously
See TRANSFER_FAILURE for more.

**TRANSFER_FAILURE**: There are many reasons why a transfer may fail, some specific to the token standard:
* A low-level `.call` will return a boolean generally
* Insufficient token balance
* Sender not authorized to transfer on-behalf of an owner, should seek approval first
* Invalid recipient: eg contract wallet that either reverts or is missing both `receive` and `fallback` functions
* Paused contract (revert during pause)
* Address access list (common in regulated tokens)
* Malicious or broken token
* Out-of-gas (OOG) from PAGE_REQUESTS or a malicious token/recipient, error cannot be caught in contract
See MALICIOUS_TRANSFERS for more.

**GAS_TARGET**: When submitting a transaction on Polygon there is a max gas for the block of ~45M (as of 2025-07-01,
previously 30M) but the effective cap is lower as there are selection algos related to an intermediary and miners.
There are also concerns of throughput and cost stability. ~2M was once a common target for contracts like OpenSea
and Gnosis when the cap was 30M.

**GAS_PER_TRANSFER**: This depends on many factors but rough conservative estimates per token type:
    * Native: ~25k
    * ERC20: USDC specifically: ~55k for a new address, ~40k for an existing address
    * ERC-1155: ~55k in general
* Estimate accuracy varies widely with factors like: if tokens may invoke contract-wallet code (USDC does not),
  generate events, involve warm vs cold addresses, sender final balance is 0, recipient start balance is 0,
  how the transfers are requested (avoid approve/pull), custom/non-standard features.
* These estimates can be simulated to get a more accurate and holistic understanding of fees that can also be
  influenced by misc items like tx startup/tracking/events/cleanup as well as a margin of error if attempting to
  run a fixed number of transfers (perhaps better to dynamically check gas remaining and allow a cleanup margin).

**GAS_FEES**: Givens:
* Polygon uses an EIP-1559-style model where Total fee per gas unit = Base Fee + Priority Fee
* Given a target of 2M gas/tx, POL/USD rates: $0.25 or $1.00, Priority fees: 25-150 Gwei, Base fees: 0 (common):
      PriorityFee     $0.25/POL      $1.00/POL
        ------        ---------      ---------
        25 GWei       $0.0125        $0.0500
        50 GWei       $0.0250        $0.1000
        75 GWei       $0.0375        $0.1500 (example below)
        100 GWei      $0.0500        $0.2000
        125 GWei      $0.0625        $0.2500
        150 GWei      $0.0750        $0.3000
* Example calculation to get the cost of a 2M gas tx at 75 GWei and $1.00/POL
    1) Convert GWei to POL per gas unit: 75 GWei = 75 × 10^-9 POL per gas unit
    2) Multiply by gas used:           2,000,000 × 75 × 10^-9 = 0.15 POL
    3) Multiply by POL price in USD:                            0.15 POL × $1.00 = $0.15 USD (answer)

**ROLE_SWAP**: Removing a swap feature and this enum saved 0.940 KiB, enum Action { None, Add, Remove, Count }
Savings from (enum, params, validation, feature code) add up fast
The same effects can be achieved via Add + Remove as limits are checked in aggregate after applying all changes
There's more gas cost in doing a full remove vs inplace swap but it's minimal compared to the size saved

**NONCE_EXAMPLE**:
Example base case:
- A) `getNonce`=42
- B) The client signs two messages:
    - sig1 with nonce 42
    - sig2 with nonce 43
Example possible endings:
- C) The relay pipeline (client/server/etc) causes an Agent to send messages to the contract:
    - C1) in-order (42,43), each is successful, next `getNonce`=44
    - C2) out-of-order (43,42 or just 43) and each sig fails due to an invalid nonce, next `getNonce`=42
    - C3) C2 + messages are recreated and/or resubmitted as C1
    - C4) in-order (42,43), 42 fails to remove all voters, 43 fails nonce, next `getNonce`=42
CD_ARRAY_COPY: A calldata array assignment requires either:
    1) IR-pipeline - which prevents static analysis via slither
    2) A loop that does assignment per item (this is what the IR-pipeline optimizer would do anyways)

**SET_CR_LESS_SIGS**: Not all `CallTracker._setCallRes` signatures are used to reduce bytecode

## From XferMgr:
- **EXEC_GAS** estimates for `propExecute`: (worst-case) from `cleanup` declaration until the end of the function given:
  The following estimates were before some refactoring but likely still resonable
  All calls access cold storage, a single iteration of both loops (for and while), USDC approval required
  These estimates are from GPT:
  +------+---------------------------------------------+----------------+
  | Sec# | Description                                 | Worst-Case Gas |
  +------+---------------------------------------------+----------------+
  |  1   | Cache values from InstRev                   | ~21,000        |
  |  2   | _transferToVault (incl. approval, USDC)     | ~110,000       |
  |  3   | IR.add (emap update, 3 mappings)            | ~50,000        |
  |  4   | OI.addNoCheck (emap update)                 | ~25,000        | indexes exist for correction
  |  5   | EMAP.addIfNew(_instToDates                  | ~60,000        | 5-8 skipped for correction
  |  6   | EMAP.addIfNew(_dateToInsts                  | ~60,000        |
  |  7   | EMAP.addIfNew(_instNames                    | ~32,000        |
  |  8   | EMAP.addIfNew(_earnDates                    | ~25,000        |
  |  9   | One balance update (_balances[owner.eid])   | ~22,000        | (now uses 1-2 mgr contracts)
  | 10   | Emit RevenueAllocated event                 | ~2,000         |
  | 11   | Track progress (store iInst, iOwner, etc.)  | ~3,000         |
  +------+---------------------------------------------+----------------+
  |      | Total                                       | ~410,000       |
  +------+---------------------------------------------+----------------+
  | MAX  | Conservatively padded worst-case            | ~500k          |
  +------+---------------------------------------------+----------------+

**REV_MGR_PROP_EXEC_BIG_O**: `propExecute` is O(N^2) to have higher consistency than an O(N) implementation.
Summary O(N^2) Pros/Cons:
- Pro: Simpler recovery as execution validation occurs per instrument
- Pro: Less bytecode size to recover due to unforeseen issues mid-execution such as a `LowFunds` error
- Con: More time/txs to apply changes per inst per owner (vs only per owner vs O(N)) on the happy path
Details:
  - The original logic aggregated owner balances during proposal creation/validation such that propExecute
    would simply loop over aggregate balance increases O(N).
  - While O(N) is many fewer txs, it is more difficult to recover from an unforseen issue blocking progress
    mid-execution such as `LowFunds` where InstRevs had been added to the contract but before balance increases
    as they would be applied once for all insts at the end. So recovery would need to unravel balances O(N^2).
  - A `LowFunds` error would block a proposal mid-execution and require a prune function:
      - If propExecute is O(N^2) then the prune is O(N) since it would stop between fully handled InstRevs
        such that no balances need to be adjusted, the InstRev and OwnSnap could be O(1) removed from prop
      - If propExecute is O(N) then the prune is: O(N^2) since removing InstRev and OwnSnap would also
        require reducing all related aggregate balances.
      - If the error affects N insts the complexity increases to O(N^2) and O(N^3) respectively

## From BoxMgr.sol

**PROXY_OPTIONS**: Common options for proxies/upgrades:
- UUPSUpgradeable + Initializable: Allows a contract to be upgradeable in a generally preferred way vs TUP, but heavy
- EIP-1967 proxy: TransparentUpgradeableProxy (TUP): Contracts each have a unique logic address, requires N upgrades.
  By virtue of the proxy, logic can be upgraded with a stable proxy address.
- EIP-1967 proxy: UpgradeableBeacon(Proxy) + BeaconProxy: Contracts share a logic address, to upgrade in 1 place.
  By virtue of the proxy, logic can be upgraded with a stable proxy address.
- EIP-1167 minimal proxy clones: Contracts have fixed logic address, a direct update requires a new address.
  Any logic/state delegated/invoked via another contract can be updated in 1 place (the other contract), but
  state stored in the contract directly requires N upgrades. A conditional hybrid of the 1 vs N scenarios.

**CREATE2**: Proxy address creation using minimal clone (EIP-1167) logic via CREATE2 opcode. The address is
deterministic for consistent salt inputs.

**NO_SQUATTERS**: Algo makes it infeasible to squat addrs while ubound is high vs the max block gas.
- If a gas block limit increase makes squatting feasible then increase the ubound via `setProbeAddrMax`
Given a miner bot tx in the same block:
- All inputs can be known by seeing the tx in the pool and the previous block
- Squatter must deploy to every addr in range, but deploy cost (~25k+) is far more than probe cost (~700)
- High ubound(10k default) x deploy cost exhausts both current and near-future block gas limits for squatters
- The ubound cost for this deploy is ~7M vs an attacker cost of ~250M gas @25k gas/addr, limit now 45M
Miner bots cannot front-run across multiple txs due to block.prevrandao which is basically random per block

## From CRT.sol

**METADATA_FILE**: The file content is based upon https://eips.ethereum.org/EIPS/eip-1155#metadata and popular
marketplace conventions like OpenSea. The url id substitution is different from ERC-721, but file content is same:

For example, the contract might return: https://example.com/tokens/{id}.json as the metadata file and then the client
replaces the "{id}" substring with the token id for that instrument, examples:
wallet calls contract.uri(100) (where the param is ignored)
- receives the string https://gigastar.io/tokens/meta/{id}.json
- loads the file at https://gigastar.io/tokens/meta/100.json to see:

```json
{
  "name": "ClearValue Tax",
  "description": "Channel Revenue Token",
  "image": "https://gigastar.io/tokens/images/cvt.png",
  "external_url": "https://www.youtube.com/@clearvaluetax9382",
  "decimals": 0,
  "attributes": [
    { "trait_type": "instrument", "value": "CVT" },
    { "trait_type": "symbol", "value": "CVT" },
    { "trait_type": "series", "value": 0, "display_type": "number" },
    { "trait_type": "decimals", "value": 0, "display_type": "number" },
    { "trait_type": "release_date", "value": 1700000000, "display_type": "date" },
    { "trait_type": "first_earn_date", "value": 1700000000, "display_type": "date" },
    { "trait_type": "last_earn_date", "value": 1700000000, "display_type": "date" },
    { "trait_type": "term", "value": "Perpetual" },
    { "trait_type": "rsu_rate", "value": 0.000025, "display_type": "number" },
    { "trait_type": "rsu_percent", "value": 0.0025, "display_type": "number" },
    { "trait_type": "url_legal_0", "value": "https://gigastar.io/docs/terms/cvt.pdf" },
    { "trait_type": "url_channel_0", "value": "https://www.youtube.com/@clearvaluetax9382" }
  ]
}
```

Same sequence:
- loads the file at https://gigastar.io/tokens/meta/101.json to see:
```json
{
  "name": "ClearValue Tax, Series 1",
  "description": "Channel Revenue Token",
  "image": "https://gigastar.io/tokens/images/cvt.png",
  "external_url": "https://www.youtube.com/@clearvaluetax9382",
  "decimals": 0,
  "attributes": [
    { "trait_type": "instrument", "value": "CVT.1" },
    { "trait_type": "symbol", "value": "CVT" },
    { "trait_type": "series", "value": 1, "display_type": "number" },
    { "trait_type": "decimals", "value": 0, "display_type": "number" },
    { "trait_type": "release_date", "value": 1700000000, "display_type": "date" },
    { "trait_type": "first_earn_date", "value": 1700000000, "display_type": "date" },
    { "trait_type": "last_earn_date", "value": 1700000000, "display_type": "date" },
    { "trait_type": "term", "value": "Perpetual" },
    { "trait_type": "rsu_rate", "value": 0.000025, "display_type": "number" },
    { "trait_type": "rsu_percent", "value": 0.0025, "display_type": "number" },
    { "trait_type": "url_legal_0", "value": "https://gigastar.io/docs/terms/cvt.1.pdf" },
    { "trait_type": "url_channel_0", "value": "https://www.youtube.com/@clearvaluetax9382" }
  ]
}
```

Same sequence:
- loads the file at https://gigastar.io/tokens/meta/801.json to see:
```json
{
  "name": "Thee Mademoiselle, Series 1",
  "description": "Channel Revenue Token",
  "image": "https://gigastar.io/tokens/images/tmdm.png",
  "external_url": "https://www.youtube.com/channel/UCJRp9BKPrtX90otL2e1Bs4A",
  "decimals": 0,
  "attributes": [
    { "trait_type": "instrument", "value": "TMDM.1" },
    { "trait_type": "symbol", "value": "TMDM" },
    { "trait_type": "series", "value": 1, "display_type": "number" },
    { "trait_type": "decimals", "value": 0, "display_type": "number" },
    { "trait_type": "release_date", "value": 1700000000, "display_type": "date" },
    { "trait_type": "first_earn_date", "value": 1700000000, "display_type": "date" },
    { "trait_type": "last_earn_date", "value": 1700000000, "display_type": "date" },
    { "trait_type": "term", "value": "Perpetual" },
    { "trait_type": "rsu_rate", "value": 0.0002, "display_type": "number" },
    { "trait_type": "rsu_percent", "value": 0.02, "display_type": "number" },
    { "trait_type": "url_legal_0", "value": "https://gigastar.io/docs/terms/tmdm.1.pdf" },
    { "trait_type": "url_channel_0", "value": "https://www.youtube.com/channel/UCJRp9BKPrtX90otL2e1Bs4A" },
    { "trait_type": "url_channel_1", "value": "https://www.youtube.com/channel/UCYYfjodFlgAQaZeoywpGblQ" },
    { "trait_type": "url_channel_2", "value": "https://www.youtube.com/channel/UC1r-ikKjDmLFCqe9kns2IRQ" }
  ]
}
```
