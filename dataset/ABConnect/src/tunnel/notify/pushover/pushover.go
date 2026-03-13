package pushover

import (
	"os"

	"github.com/gregdel/pushover"
	"github.com/sirupsen/logrus"
)

var log *logrus.Logger

func init() {
	log = logrus.New()
	log.SetOutput(os.Stdout)
}

type Pushover struct {
	*pushover.Pushover
	recipient *pushover.Recipient
}

func New(token, key string) *Pushover {
	po := pushover.New(token)
	pr := pushover.NewRecipient(key)
	return &Pushover{
		Pushover:  po,
		recipient: pr,
	}
}

func (p *Pushover) SendMessage(title, message string) error {
	m := pushover.Message{
		Message: message,
		Title:   title,
	}

	log.WithFields(logrus.Fields{
		"title":   title,
		"message": message,
	}).Infoln("pushover send message")

	_, err := p.Pushover.SendMessage(&m, p.recipient)
	if err != nil {
		return err
	}

	return nil
}
