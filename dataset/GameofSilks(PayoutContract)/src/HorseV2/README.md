# SilksHorseDiamond Contract Documentation

## Summary

Repo containing code for Silks Horse V2 (ERC-721) contract using the Diamond (ERC-2535) pattern.

## Contracts, Libraries, and Facets

These Solidity contracts, libraries, and facets together form the SilksHorseDiamond project, offering a comprehensive solution for managing NFTs with various features, including access control, royalties, metadata, and pausing capabilities. Detailed implementation and usage instructions can be found in the respective contract source code and accompanying documentation.

### <span style="color:gray">Contracts</span>
#### SilksHorseDiamond.sol

The `SilksHorseDiamond` contract is a Diamond upgradeable NFT (ERC721) with additional features. It serves as a core contract for managing NFTs, royalties, and access control.

- Sets metadata for the NFT, including name, symbol, and base URI.
- Configures default royalty information.
- Sets the contract owner and initially pauses the contract.
- Grants roles to the contract owner for access control.
- Defines and grants admin roles for the contract and minting NFTs.

##### Inherited Contracts

- `AccessControlInternal`: Provides access control features.
- `ERC2981`: Implements the ERC2981 standard for royalties.
- `PausableInternal`: Provides pausing functionality.
- `SolidStateDiamond`: Serves as the base contract for Diamond upgradeability.

### <span style="color:gray">Libraries</span>
#### LibSilksHorseDiamond.sol
##### Constants

- `CONTRACT_ADMIN_ROLE` (bytes32): Role identifier for contract administrators.
- `MINT_ADMIN_ROLE` (bytes32): Role identifier for mint administrators.
- `HORSE_PURCHASING_PAUSED` (bytes32): Identifier for pausing horse purchases.

##### Layout

- `seasons`: Mapping from season IDs to sets of associated token IDs.
- `seasonInfos`: Mapping from season IDs to season information.
- `payoutTiers`: Mapping from payout tier IDs to payout tier information.
- `horsePayoutPct`: Mapping from horse token IDs to payout percentages.

##### Functions

- `layout`: Returns a reference to the internal Diamond contract storage slot `silks.contracts.storage.SilksHorseDiamond`.

### <span style="color:gray">Facets</span>
#### SilksHorseDiamondInit.sol

##### Inherited Contracts

- `ERC165BaseInternal`: Provides ERC165 functionality.

##### Functions

- `init`: Initialize supported interfaces within the Diamond contract.

#### ERC721Facet.sol

##### Inherited Contracts

- `AccessControlInternal`: Provides access control features.
- `ERC165BaseInternal`: Extends ERC165 internal contract.
- `ERC721Base`: Extends ERC721Base contract.
- `ERC721Enumerable`: Extends ERC721 with enumeration functionality.
- `ERC721Metadata`: Extends ERC721 with metadata support.
- `PartiallyPausableInternal`: Provides partial pausing functionality.
- `PausableInternal`: Provides pausing functionality.

##### Functions

- `purchase`: Allows users to purchase horses by specifying the season, payout tier, and quantity.
- `airdrop`: Allows administrators to airdrop horses by specifying the season, payout tier, quantity, and recipient address.
- `externalMint`: Allows minting of horses from a contract that is part of an allowed list.
- `_mintHorses`: Mint horses based on season, payout tier, quantity, and recipient address.
- `_beforeTokenTransfer`: Hook function called before token transfer, inherited from ERC721Metadata.

#### ReadableFacet.sol

##### Inherited Contracts

- `AccessControlInternal`: Provides access control features.
- `PartiallyPausableInternal`: Provides partial pausing functionality.

##### Functions

- `seasonInfo`: Get information about a specific season.
- `horseSeasonInfo`: Get information about a horse's season
- `payoutTier`: Get information about a specific payout tier.
- `horsePayoutTier`: Get the payout tier for a specific horse token.
- `baseURI`: Get current baseURI
- `horsePurchasesPaused`: Check if horse purchases are paused.
- `isAllowedExternalMintAddress`: Returns true if passed address is allowed to call externalMint function.
- `hasContractAdminRole`: Returns true if address has the contract admin role.
- `hasMintAdminRole`: Returns true if address has the mint admin role

#### WriteableFacet.sol
##### Inherited Contracts

- `AccessControl`: Provides access control features.
- `ERC721BaseInternal`: Provides ERC721 functionality.
- `OwnableInternal`: Provides ownable features.
- `Pausable`: Provides pausable features.
- `PartiallyPausableInternal`: Provides partial pausing functionality.

##### Functions

- `setRoleAdmin`: Set the admin role for a specified role.
- `setSeasonInfo`: Set season information.
- `setPayoutTier`: Set payout tier information.
- `setBaseURI`: Set the base URI for metadata of NFTs.
- `setHorsePayoutTier`: Set the payout tier for a specific horse token.
- `pause`: Pause the contract.
- `unpause`: Unpause the contract.
- `pauseHorsePurchases`: Pause horse purchases.
- `unpauseHorsePurchases`: Unpause horse purchases.
- `allowExternalMintAddress`: Add address to external mint allow list.
- `setContractAdminRoleMember`: Set or revoke the `CONTRACT_ADMIN_ROLE` for a specific address.
- `setMintAdminRoleMember`: Set or revoke the `MINT_ADMIN_ROLE` for a specific address.
- `setRoyaltyInfo`: Set royalty information.

## Dummy Diamond Generator Notes

### Usage

Deploy the dummy diamond implementation contract separately from the other
diamond contracts. Using louper.dev and the `setDummyImplementation`, set the
implementation to the address of the deployed dummy contract. 

After setting the implementation slot go to etherscan and navigate to the
contract page. Under the "Contract" tab, click the "More Options" dropdown
button and select "Is this a proxy?". Don't change anything and click Verify.

### Adding Facets
New facets should be added to the `utils/fetchFacets.ts` file. Currently, these scripts are compatible only with ethers v6. A branch named `hardhat-ethers-v6` is available if ethers v6 support is required. Ensure tests are upgraded for v6 support before merging.

### Generating New Dummy Contract

Depending on your setup, follow the instructions below to generate a new dummy diamond implementation contract:


- **With [hardhat-shorthand](https://hardhat.org/hardhat-runner/docs/guides/command-line-completion#shorthand-hh-and-autocomplete) installed:**
    ```bash
    hh run ./scripts/runGenerateDummy.ts
    ```

- **Regular Hardhat:**
    ```bash
    npx hardhat run ./scripts/runGenerateDummy.ts
    ```
