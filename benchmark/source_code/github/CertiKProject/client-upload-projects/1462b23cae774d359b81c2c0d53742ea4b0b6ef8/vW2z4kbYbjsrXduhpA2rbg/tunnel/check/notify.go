package check

import (
	"fmt"

	"gitlab.weinvent.org/yangchenzhong/tunnel/notify/pushover"
)

func (c *Check) initNotify() error {
	if c.Pushover == nil {
		return fmt.Errorf("pushover instance is nil")
	}

	c.notify = pushover.New(c.Pushover.Token, c.Pushover.Key)

	return nil
}

func (c *Check) sendMessage(title, message string) error {
	if c.Bridge.Pushover == nil {
		return fmt.Errorf("no pushover api client")
	}
	if c.notify == nil {
		if err := c.initNotify(); err != nil {
			return err
		}
	}

	log.WithField("message", message).Errorln(title)

	return c.notify.SendMessage(title, message)
}
