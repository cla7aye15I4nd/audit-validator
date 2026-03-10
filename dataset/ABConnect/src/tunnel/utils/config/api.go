package config

type APIConfig struct {
	Host            string         `json:"Host"`
	HostNetwork     string         `json:"HostNetwork,omitempty"`
	HttpHost        string         `json:"HttpHost"`
	ManagerHost     string         `json:"ManagerHost"`
	ManagerHttpHost string         `json:"ManagerHttpHost"`
	Blockchains     []*ChainConfig `json:"Blockchain"`
}
