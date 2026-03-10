package utils

import "strings"

const SystemConfigPrefix = "SC_"

type SystemConfig int

const (
	Default SystemConfig = iota // error
	AutoConfirm
)

var systemConfigText = map[SystemConfig]string{
	AutoConfirm: "AutoConfirm",
}

var systemConfigIndex = map[string]SystemConfig{
	"AutoConfirm": AutoConfirm,
}

const (
	AutoConfirmDefault = "enable" // enable
	AutoConfirmDisable = "disable"
)

func GetSystemConfigText(action SystemConfig) string {
	return systemConfigText[action]
}

func GetSystemConfigDefaultText() map[SystemConfig]interface{} {
	return map[SystemConfig]interface{}{
		AutoConfirm: AutoConfirmDefault,
	}
}

func (sc SystemConfig) Text() string {
	return SystemConfigPrefix + sc.String()
}

func (sc SystemConfig) String() string {
	return GetSystemConfigText(sc)
}

func SystemConfigUnmarshal(text string) SystemConfig {
	if strings.HasPrefix(text, SystemConfigPrefix) {
		return systemConfigIndex[strings.TrimPrefix(text, SystemConfigPrefix)]
	}
	return systemConfigIndex[text]
}

const (
	ManagerSetSuccess = "SUCCESS" // enable
	ManagerSetFailure = "FAILURE"
)
