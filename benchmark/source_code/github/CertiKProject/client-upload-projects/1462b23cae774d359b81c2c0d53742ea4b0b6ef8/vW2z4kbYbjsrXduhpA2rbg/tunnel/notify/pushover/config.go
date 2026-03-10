package pushover

type Config struct {
	Token string `json:"token"` // the application API token
	Key   string `json:"key"`   // the user/group key
}
