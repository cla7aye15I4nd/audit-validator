package orderbook

// -- Order Queue --

type BuyQueue []*Order

func (q BuyQueue) Len() int { return len(q) }
func (q BuyQueue) Less(i, j int) bool {
	if q[i].Price.Cmp(q[j].Price) == 0 {
		return q[i].Timestamp < q[j].Timestamp
	}
	return q[i].Price.Cmp(q[j].Price) > 0
}
func (q BuyQueue) Swap(i, j int) {
	q[i], q[j] = q[j], q[i]
	q[i].Index = i
	q[j].Index = j
}
func (q *BuyQueue) Push(x interface{}) {
	o := x.(*Order)
	o.Index = len(*q)
	*q = append(*q, o)
}
func (q *BuyQueue) Pop() interface{} {
	old := *q
	n := len(old)
	o := old[n-1]
	*q = old[0 : n-1]
	return o
}

type SellQueue []*Order

func (q SellQueue) Len() int { return len(q) }
func (q SellQueue) Less(i, j int) bool {
	if q[i].Price.Cmp(q[j].Price) == 0 {
		return q[i].Timestamp < q[j].Timestamp
	}
	return q[i].Price.Cmp(q[j].Price) < 0
}
func (q SellQueue) Swap(i, j int) {
	q[i], q[j] = q[j], q[i]
	q[i].Index = i
	q[j].Index = j
}
func (q *SellQueue) Push(x interface{}) {
	o := x.(*Order)
	o.Index = len(*q)
	*q = append(*q, o)
}
func (q *SellQueue) Pop() interface{} {
	old := *q
	n := len(old)
	o := old[n-1]
	*q = old[0 : n-1]
	return o
}
