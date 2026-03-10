package notify

type Notify interface {
	// send message
	SendMessage(title, message string) error
}
