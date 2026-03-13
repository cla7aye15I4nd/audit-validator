// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// import  {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IHorseNFT {
    enum MintMethod {
        PURCHASE,
        AIRDROP,
        EXTERNAL_MINT
    }

    error InvalidAddress(address _address);
    error InvalidSeason(uint256 _sent);
    error InvalidPayoutTier(uint256 _sent);
    error InvalidTokenId(uint256 _sent);
    error InvalidIntValue(string _reason, uint256 _sent, uint256 _expected);
    error InvalidStringValue(string _reason, string _sent, string _expected);
    error InvalidExternalMintAddress(address _sender);
    error MaxHorsesPerWalletExceeded(address _walletAddress);
    error PayoutTierMaxSupplyExceeded(uint256 _payoutTier);
    error MintFailed(
        string _reason,
        uint256 _seasonId,
        uint256 _payoutTier,
        uint256 _quantity,
        MintMethod _method,
        address _to
    );

    // Can be called by ExtMintAddress on the HorseNFT contract
    // V1
    /**
     * extMint function to mint horse NFTs for V1
     * @param to The address to mint to.
     * @param amountReq The amount of horse NFTs to mint.
     */
    function extMint(address to, uint256 amountReq) external;

    // V2
    /**
     * externalMint function to mint horse NFTs for V2
     * @param _seasonId The season for the Horses to be minted.
     * @param _payoutTier  The payout tier for the horse to be minted.
     * @param _quantity The quantity to be minted.
     * @param _to The address to mint to.
     */
    function externalMint(
        uint256 _seasonId,
        uint256 _payoutTier,
        uint256 _quantity,
        address _to
    ) external;

    function purchase(
        uint256 _seasonId,
        uint256 _payoutTier,
        uint256 _quantity
    ) external payable;

    function allowExternalMintAddress(address _extMintAddress) external;

    function balanceOf(address owner) external view returns (uint256);

    function payoutTier(
        uint256 _payoutTier
    )
        external
        view
        returns (
            uint256 tierId,
            string memory description,
            uint256 price,
            uint256 maxPerTx,
            uint256 payoutPct,
            uint256 maxSupply,
            bool paused,
            bool valid
        );
}
