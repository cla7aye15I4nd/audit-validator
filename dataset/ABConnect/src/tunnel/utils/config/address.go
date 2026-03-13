package config

type Address interface {
	String() string
}

type StringAddress string

func (s StringAddress) String() string {
	return string(s)
}
