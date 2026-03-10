package swap

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"

	"github.com/shopspring/decimal"
)

type CMCResponse struct {
	Data map[string]struct {
		ID     int    `json:"id"`
		Name   string `json:"name"`
		Symbol string `json:"symbol"`
		Quote  map[string]struct {
			Price float64 `json:"price"`
		} `json:"quote"`
	} `json:"data"`
}

func getCurrencyPrice(key string, id uint64) (decimal.Decimal, error) {
	idStr := fmt.Sprintf("%v", id)
	convert := "USD" // force

	client := &http.Client{}
	req, err := http.NewRequest("GET", "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest", nil)
	if err != nil {
		return decimal.Decimal{}, err
	}
	q := url.Values{}
	q.Add("id", fmt.Sprintf("%v", idStr))
	q.Add("convert", convert)

	req.Header.Set("Accepts", "application/json")
	req.Header.Add("X-CMC_PRO_API_KEY", key)
	req.URL.RawQuery = q.Encode()

	resp, err := client.Do(req)
	if err != nil {
		return decimal.Decimal{}, fmt.Errorf("error sending request to server")
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return decimal.Decimal{}, err
	}

	if resp.StatusCode != 200 {
		return decimal.Decimal{}, fmt.Errorf("Error: HTTP %d - %s\n", resp.StatusCode, string(body))
	}

	var cmcResponse CMCResponse
	err = json.Unmarshal(body, &cmcResponse)
	if err != nil {
		return decimal.Decimal{}, err
	}
	price := cmcResponse.Data[idStr].Quote[convert].Price

	return decimal.NewFromFloat(price), nil
}
