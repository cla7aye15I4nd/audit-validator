package database

import "time"

// Blockchain database blockchains
type Blockchain struct {
	Id        uint64 `db:"id" json:"id"`
	Network   string `db:"network" json:"network"`
	ChainId   string `db:"chain_id" json:"chain_id"`
	BaseChain string `db:"base_chain" json:"base_chain"`
}

type Asset struct {
	ID           uint64 `db:"id"`
	BlockchainId uint64 `db:"blockchain_id"`
	Asset        string `db:"asset"`

	Name      string `db:"name"`
	Symbol    string `db:"symbol"`
	Decimals  uint8  `db:"decimals"`
	Attribute uint64 `db:"attribute"`
	AssetType string `db:"asset_type"`
}

type AssetDetail struct {
	Asset
	Network   string `db:"network"`
	ChainId   string `db:"chain_id"`
	BaseChain string `db:"base_chain"`
}

type PairDetail struct {
	Pair
	AssetAAsset        string `db:"asset_a_asset"`
	AssetAName         string `db:"asset_a_name"`
	AssetASymbol       string `db:"asset_a_symbol"`
	AssetADecimals     uint8  `db:"asset_a_decimals"`
	AssetAAssetType    string `db:"asset_a_asset_type"`
	AssetAAttribute    uint64 `db:"asset_a_attribute"`
	AssetABlockchainId uint64 `db:"asset_a_blockchain_id"`
	AssetANetwork      string `db:"asset_a_network"`
	AssetAChainId      string `db:"asset_a_chain_id"`
	AssetABaseChain    string `db:"asset_a_base_chain"`

	AssetBAsset        string `db:"asset_b_asset"`
	AssetBName         string `db:"asset_b_name"`
	AssetBSymbol       string `db:"asset_b_symbol"`
	AssetBDecimals     uint8  `db:"asset_b_decimals"`
	AssetBAssetType    string `db:"asset_b_asset_type"`
	AssetBAttribute    uint64 `db:"asset_b_attribute"`
	AssetBBlockchainId uint64 `db:"asset_b_blockchain_id"`
	AssetBNetwork      string `db:"asset_b_network"`
	AssetBChainId      string `db:"asset_b_chain_id"`
	AssetBBaseChain    string `db:"asset_b_base_chain"`
}

type Pair struct {
	Id                             uint64 `db:"id"`
	AssetAId                       uint64 `db:"asset_a_id"`
	AssetBId                       uint64 `db:"asset_b_id"`
	AssetAMinDepositAmount         string `db:"asset_a_min_deposit_amount"`
	AssetBMinDepositAmount         string `db:"asset_b_min_deposit_amount"`
	AssetAWithdrawFeePercent       uint   `db:"asset_a_withdraw_fee_percent"`
	AssetBWithdrawFeePercent       uint   `db:"asset_b_withdraw_fee_percent"`
	AssetAWithdrawFeeMin           string `db:"asset_a_withdraw_fee_min"`
	AssetBWithdrawFeeMin           string `db:"asset_b_withdraw_fee_min"`
	AssetAAutoConfirmDepositAmount string `db:"asset_a_auto_confirm_deposit_amount"`
	AssetBAutoConfirmDepositAmount string `db:"asset_b_auto_confirm_deposit_amount"`

	CreatedAt time.Time `db:"created_at" json:"created_at"`
	UpdatedAt time.Time `db:"updated_at" json:"updated_at"`
	SignInfo  *SignInfo `db:"sign_info" json:"sign_info"`
}

func (p Pair) TableType() string {
	return TableOfPairs
}

func (p Pair) GetId() uint64 {
	return p.Id
}

func (p Pair) GetSignInfo() *SignInfo {
	return p.SignInfo
}

func (p *Pair) SetSignInfo(si *SignInfo) {
	p.SignInfo = si
}

func (p *Pair) SetUpdatedAt(at time.Time) {
	p.UpdatedAt = at.UTC()
}
