package cli

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

var (
	buildCommit string
	buildDate   string

	log *logrus.Logger
)

func init() {
	log = logrus.New()
	log.SetOutput(os.Stdout)
}

// CLI represents a command-line interface. This class is
// not threadsafe.
type CLI struct {
	Name    string
	rootCmd *cobra.Command
	rpcURL  string
	config  string
	logfile string

	host     string
	user     string
	database string
	password string
}

// NewCLI returns an initialized CLI
func NewCLI() *CLI {
	cli := &CLI{
		Name:    "tunnel",
		rootCmd: nil,
		rpcURL:  "",
		config:  "",
	}

	cli.buildRootCmd()
	return cli
}

// Execute parses the command line and processes it.
func (cli *CLI) Execute() {
	cli.rootCmd.Execute()
}

// setup turns up the CLI environment, and gets called by Cobra before
// a command is executed.
func (cli *CLI) setup(cmd *cobra.Command, args []string) {
	err := setupConfig(cli)
	if err != nil {
		fmt.Println(err)
		fmt.Fprint(os.Stderr, cmd.UsageString())
		os.Exit(1)
	}
}

func (cli *CLI) help(cmd *cobra.Command, args []string) {
	fmt.Fprint(os.Stderr, cmd.UsageString())

	os.Exit(-1)

}

// TestCommand test command
func (cli *CLI) TestCommand(command string) string {
	// cli.testing = true
	result := cli.Run(strings.Fields(command)...)
	//	cli.testing = false
	return result
}

// Run executes CLI with the given arguments. Used for testing. Not thread safe.
func (cli *CLI) Run(args ...string) string {
	oldStdout := os.Stdout

	r, w, _ := os.Pipe()

	os.Stdout = w

	cli.rootCmd.SetArgs(args)
	cli.rootCmd.Execute()
	cli.buildRootCmd()

	w.Close()

	os.Stdout = oldStdout

	var stdOut bytes.Buffer
	io.Copy(&stdOut, r)
	return stdOut.String()
}

// Embeddable returns a CLI that you can embed into your own Go programs. This
// is not thread-safe.
func (cli *CLI) Embeddable() *CLI {

	return cli
}
