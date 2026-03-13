const {ethers} = require("hardhat");
const METADATA_URI = "https://nft.dev.silks.io/metadata/c1/";
const ROYALTY_RECEIVER = "0x7edAC4f0251a484a28F757d8f6e83783a1f38285";
const ROYALTY_SHARE = 800;

const SEASON_INFOS = [
    { seasonId: 2024, description: "Silks 2024 Horse Season", paused: false, valid: true}
];

const PAYOUT_TIERS = [
    { tierId: 1, description: "1 Pct Payout", price: ethers.utils.parseEther('.0001'), maxPerTx: 100, payoutPct: 100, maxSupply: 0, paused: false, valid: true}
];

module.exports = [
    "Silks Horse V2",
    "SILKS_HORSE_V2",
    METADATA_URI,
    8257,
    ROYALTY_RECEIVER,
    ROYALTY_SHARE, // 8 pct
    0,
    SEASON_INFOS,
    PAYOUT_TIERS
]