package types

import (
	"encoding/json"
	"errors"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/rlp"
	"github.com/holiman/uint256"
	"io"
	"math/big"
	"sort"
)

type BalanceEntry struct {
	Token  string
	Amount *uint256.Int
}

func (b *BalanceEntry) EncodeRLP(w io.Writer) error {
	return rlp.Encode(w, []interface{}{b.Token, b.Amount})
}

type Balances struct {
	Available map[string]*uint256.Int
	Locked    map[string]*uint256.Int
}

func NewBalances() *Balances {
	return &Balances{
		Available: make(map[string]*uint256.Int),
		Locked:    make(map[string]*uint256.Int),
	}
}

func (bs *Balances) EncodeRLP(w io.Writer) error {
	type rlpBalances struct {
		Available []*BalanceEntry
		Locked    []*BalanceEntry
	}

	toSortedEntries := func(m map[string]*uint256.Int) []*BalanceEntry {
		keys := make([]string, 0, len(m))
		for k := range m {
			// TODO-Orderbook: should be removed zero balance account?
			keys = append(keys, k)
		}
		sort.Strings(keys)

		entries := make([]*BalanceEntry, 0, len(m))
		for _, k := range keys {
			entries = append(entries, &BalanceEntry{Token: k, Amount: m[k]})
		}
		return entries
	}

	return rlp.Encode(w, &rlpBalances{
		Available: toSortedEntries(bs.Available),
		Locked:    toSortedEntries(bs.Locked),
	})
}

func (bs *Balances) DecodeRLP(s *rlp.Stream) error {
	type rlpBalances struct {
		Available []*BalanceEntry
		Locked    []*BalanceEntry
	}

	var data rlpBalances
	if err := s.Decode(&data); err != nil {
		return err
	}

	bs.Available = make(map[string]*uint256.Int, len(data.Available))
	for _, e := range data.Available {
		bs.Available[e.Token] = e.Amount
	}

	bs.Locked = make(map[string]*uint256.Int, len(data.Locked))
	for _, e := range data.Locked {
		bs.Locked[e.Token] = e.Amount
	}

	return nil
}

// TODO-Orderbook: it should be handled when balance is zero, delete key from Balances

func ensureMapEntry(m map[string]*uint256.Int, token string) *uint256.Int {
	if m[token] == nil {
		m[token] = uint256.NewInt(0)
	}
	return m[token]
}

func (bs *Balances) Lock(token string, amount *uint256.Int) error {
	avail := ensureMapEntry(bs.Available, token)
	if avail.Cmp(amount) < 0 {
		return errors.New("insufficient available balance to lock")
	}
	avail.Sub(avail, amount)

	lock := ensureMapEntry(bs.Locked, token)
	lock.Add(lock, amount)
	return nil
}

func (bs *Balances) Unlock(token string, amount *uint256.Int) error {
	lock := ensureMapEntry(bs.Locked, token)
	if lock.Cmp(amount) < 0 {
		return errors.New("insufficient locked balance to unlock")
	}
	lock.Sub(lock, amount)

	avail := ensureMapEntry(bs.Available, token)
	avail.Add(avail, amount)
	return nil
}

func (bs *Balances) ConsumeLock(token string, amount *uint256.Int) error {
	lock := ensureMapEntry(bs.Locked, token)
	if lock.Cmp(amount) < 0 {
		return errors.New("insufficient locked balance to consume")
	}
	lock.Sub(lock, amount)
	// Note: 실제 차감은 이미 Available에서 했기 때문에 여기선 Locked만 줄이면 됨
	return nil
}

func (bs *Balances) IsEmpty() bool {
	for _, val := range bs.Available {
		if val != nil && !val.IsZero() {
			return false
		}
	}
	for _, val := range bs.Locked {
		if val != nil && !val.IsZero() {
			return false
		}
	}
	return true
}

func (bs *Balances) Copy() *Balances {
	bsCopy := NewBalances()
	for k, v := range bs.Available {
		if v != nil {
			bsCopy.Available[k] = new(uint256.Int).Set(v)
		}
	}
	for k, v := range bs.Locked {
		if v != nil {
			bsCopy.Locked[k] = new(uint256.Int).Set(v)
		}
	}
	return bsCopy
}

func (bs *Balances) MarshalJSON() ([]byte, error) {
	type balanceEntry struct {
		Token  string       `json:"token"`
		Amount *hexutil.Big `json:"amount"`
	}
	type balancesJSON struct {
		Available []balanceEntry `json:"available"`
		Locked    []balanceEntry `json:"locked"`
	}
	toEntries := func(m map[string]*uint256.Int) []balanceEntry {
		var entries []balanceEntry
		for token, amount := range m {
			if amount != nil {
				entries = append(entries, balanceEntry{
					Token:  token,
					Amount: (*hexutil.Big)(amount.ToBig()),
				})
			}
		}
		return entries
	}

	return json.Marshal(balancesJSON{
		Available: toEntries(bs.Available),
		Locked:    toEntries(bs.Locked),
	})
}

func (bs *Balances) UnmarshalJSON(data []byte) error {
	type balanceEntry struct {
		Token  string       `json:"token"`
		Amount *hexutil.Big `json:"amount"`
	}
	type balancesJSON struct {
		Available []balanceEntry `json:"available"`
		Locked    []balanceEntry `json:"locked"`
	}

	var bj balancesJSON
	if err := json.Unmarshal(data, &bj); err != nil {
		return err
	}

	bs.Available = make(map[string]*uint256.Int)
	for _, e := range bj.Available {
		if e.Amount != nil {
			bs.Available[e.Token] = uint256.MustFromBig((*big.Int)(e.Amount))
		}
	}

	bs.Locked = make(map[string]*uint256.Int)
	for _, e := range bj.Locked {
		if e.Amount != nil {
			bs.Locked[e.Token] = uint256.MustFromBig((*big.Int)(e.Amount))
		}
	}
	return nil
}
