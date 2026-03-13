package database

import (
	"time"
)

type History struct {
	Id             uint64    `db:"id" json:"id"`
	Hash           string    `db:"hash" json:"hash"`
	Address        string    `db:"address" json:"address"`
	BlockchainId   uint64    `db:"blockchain_id" json:"blockchain_id"`
	Asset          string    `db:"asset" json:"asset"`
	BlockNumber    uint64    `db:"block_number" json:"block_number"`
	BlockTimestamp time.Time `db:"block_timestamp" json:"block_timestamp"`
	TxHash         string    `db:"tx_hash" json:"tx_hash"`
	TxIndex        uint      `db:"tx_index" json:"tx_index"`
	Sender         string    `db:"sender" json:"sender"`
	Amount         string    `db:"amount" json:"amount"`

	AdjustedAmount string `db:"adjusted_amount" json:"adjusted_amount"`
	FinalAmount    string `db:"final_amount" json:"final_amount"`
	Fee            string `db:"fee" json:"fee"`

	Recipient            string    `db:"recipient" json:"recipient"`
	TargetBlockchainId   uint64    `db:"target_blockchain_id" json:"target_blockchain_id"`
	TargetAsset          string    `db:"target_asset" json:"target_asset"`
	TargetBlockNumber    uint64    `db:"target_block_number" json:"target_block_number"`
	TargetBlockTimestamp time.Time `db:"target_block_timestamp" json:"target_block_timestamp"`
	TargetTxHash         string    `db:"target_tx_hash" json:"target_tx_hash"`
	TargetTxIndex        uint      `db:"target_tx_index" json:"target_tx_index"`

	SwapAsset          string    `json:"-"` // no db, must empty, native asset
	SwapAmountUsed     string    `db:"swap_amount_used" json:"swap_amount_used"`
	SwapAmount         string    `db:"swap_amount" json:"swap_amount"`
	SwapBlockNumber    uint64    `db:"swap_block_number" json:"swap_block_number"`
	SwapBlockTimestamp time.Time `db:"swap_block_timestamp" json:"swap_block_timestamp"`
	SwapTxHash         string    `db:"swap_tx_hash" json:"swap_tx_hash"`
	SwapTxIndex        uint      `db:"swap_tx_index" json:"swap_tx_index"`

	Status uint `db:"status" json:"status"`

	MergeTxHash string `db:"merge_tx_hash" json:"merge_tx_hash"`
	MergeStatus uint   `db:"merge_status" json:"merge_status"`
	FeeTxHash   string `db:"fee_tx_hash" json:"fee_tx_hash"`
	FeeStatus   uint   `db:"fee_status" json:"fee_status"`

	CreatedAt time.Time `db:"created_at" json:"created_at"`
	UpdatedAt time.Time `db:"updated_at" json:"updated_at"`
	SignInfo  *SignInfo `db:"sign_info" json:"sign_info"`
}

func (h History) TableType() string {
	return TableOfHistory
}

func (h History) GetId() uint64 {
	return h.Id
}

func (h History) GetSignInfo() *SignInfo {
	return h.SignInfo
}

func (h *History) SetSignInfo(si *SignInfo) {
	h.SignInfo = si
}

func (h *History) SetUpdatedAt(at time.Time) {
	h.UpdatedAt = at.UTC()
}

type HistoryDetail struct {
	History
	PairId *uint64 `db:"pair_id"`

	AssetId        uint64 `db:"asset_id"`
	AssetName      string `db:"asset_name"`
	AssetSymbol    string `db:"asset_symbol"`
	AssetDecimals  uint8  `db:"asset_decimals"`
	AssetAttribute uint64 `db:"asset_attribute"`
	AssetType      string `db:"asset_type"`
	Network        string `db:"network"`
	ChainId        string `db:"chain_id"`
	BaseChain      string `db:"base_chain"`

	TargetAssetId        *uint64 `db:"target_asset_id"`
	TargetAssetName      *string `db:"target_asset_name"`
	TargetAssetSymbol    *string `db:"target_asset_symbol"`
	TargetAssetDecimals  *uint8  `db:"target_asset_decimals"`
	TargetAssetAttribute *uint64 `db:"target_asset_attribute"`
	TargetAssetType      *string `db:"target_asset_type"`

	TargetNetwork   *string `db:"target_network"`
	TargetChainId   *string `db:"target_chain_id"`
	TargetBaseChain *string `db:"target_base_chain"`

	SwapAssetId       *uint64 `db:"swap_asset_id"`
	SwapAssetName     *string `db:"swap_asset_name"`
	SwapAssetSymbol   *string `db:"swap_asset_symbol"`
	SwapAssetDecimals *uint8  `db:"swap_asset_decimals"`
	SwapAssetType     *string `db:"swap_asset_type"`
}
