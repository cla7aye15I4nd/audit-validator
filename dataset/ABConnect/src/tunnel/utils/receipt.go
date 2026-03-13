// Copyright 2014 The go-ethereum Authors
// This file is part of the go-ethereum library.
//
// The go-ethereum library is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// The go-ethereum library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with the go-ethereum library. If not, see <http://www.gnu.org/licenses/>.

package utils

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/rpc"
)

//go:generate gencodec -type Receipt -field-override receiptMarshaling -out gen_receipt_json.go

var (
	receiptStatusFailedRLP     = []byte{}
	receiptStatusSuccessfulRLP = []byte{0x01}
)

const (
	// ReceiptStatusFailed is the status code of a transaction if execution failed.
	ReceiptStatusFailed = uint(0)

	// ReceiptStatusSuccessful is the status code of a transaction if execution succeeded.
	ReceiptStatusSuccessful = uint(1)
)

// Receipt represents the results of a transaction.
type Receipt struct {
	BlockNumber       uint64         `json:"blockNumber"`
	Status            uint           `json:"status"`
	CumulativeGasUsed uint64         `json:"cumulativeGasUsed" gencodec:"required"`
	TxHash            common.Hash    `json:"transactionHash" gencodec:"required"`
	ContractAddress   common.Address `json:"contractAddress"`
	GasUsed           uint64         `json:"gasUsed" gencodec:"required"`
}

func (r Receipt) MarshalJSON() ([]byte, error) {
	type Receipt struct {
		BlockNumber       hexutil.Uint64 `json:"blockNumber"`
		PostState         hexutil.Bytes  `json:"root"`
		Status            hexutil.Uint   `json:"status"`
		CumulativeGasUsed hexutil.Uint64 `json:"cumulativeGasUsed" gencodec:"required"`
		TxHash            common.Hash    `json:"transactionHash" gencodec:"required"`
		ContractAddress   common.Address `json:"contractAddress"`
		GasUsed           hexutil.Uint64 `json:"gasUsed" gencodec:"required"`
	}
	var enc Receipt
	enc.BlockNumber = hexutil.Uint64(r.BlockNumber)
	enc.Status = hexutil.Uint(r.Status)
	enc.CumulativeGasUsed = hexutil.Uint64(r.CumulativeGasUsed)
	enc.TxHash = r.TxHash
	enc.ContractAddress = r.ContractAddress
	enc.GasUsed = hexutil.Uint64(r.GasUsed)
	return json.Marshal(&enc)
}

func (r *Receipt) UnmarshalJSON(input []byte) error {
	type Receipt struct {
		BlockNumber       *hexutil.Uint64 `json:"blockNumber"`
		PostState         *hexutil.Bytes  `json:"root"`
		Status            *hexutil.Uint   `json:"status"`
		CumulativeGasUsed *hexutil.Uint64 `json:"cumulativeGasUsed" gencodec:"required"`
		TxHash            *common.Hash    `json:"transactionHash" gencodec:"required"`
		ContractAddress   *common.Address `json:"contractAddress"`
		GasUsed           *hexutil.Uint64 `json:"gasUsed" gencodec:"required"`
	}
	var dec Receipt
	if err := json.Unmarshal(input, &dec); err != nil {
		return err
	}
	if dec.BlockNumber == nil {
		return errors.New("missing required field 'blockNumber' for Receipt")
	}
	r.BlockNumber = uint64(*dec.BlockNumber)
	if dec.Status != nil {
		r.Status = uint(*dec.Status)
	}
	if dec.CumulativeGasUsed == nil {
		return errors.New("missing required field 'cumulativeGasUsed' for Receipt")
	}
	r.CumulativeGasUsed = uint64(*dec.CumulativeGasUsed)
	if dec.TxHash == nil {
		return errors.New("missing required field 'transactionHash' for Receipt")
	}
	r.TxHash = *dec.TxHash
	if dec.ContractAddress != nil {
		r.ContractAddress = *dec.ContractAddress
	}
	if dec.GasUsed == nil {
		return errors.New("missing required field 'gasUsed' for Receipt")
	}
	r.GasUsed = uint64(*dec.GasUsed)
	return nil
}

func GetTransactionReceipt(rc *rpc.Client, ctx context.Context, hash common.Hash) (*Receipt, error) {
	var r *Receipt
	err := rc.CallContext(ctx, &r, "eth_getTransactionReceipt", hash)
	if err == nil {
		if r == nil {
			return nil, ethereum.NotFound
		}
	}
	return r, err
}
