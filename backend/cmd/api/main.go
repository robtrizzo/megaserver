package api

import (
	"flag"
	"log/slog"
	"os"
	"sync"

	"github.com/clerk/clerk-sdk-go/v2"
)

type config struct {
	port int
	env  string
}

type application struct {
	config  config
	logger  *slog.Logger
	secrets *SecretManager
	wg      sync.WaitGroup
}

func main() {
	var cfg config
	flag.IntVar(&cfg.port, "port", 4000, "API server port")
	flag.StringVar(&cfg.env, "env", "development", "Environment (development|staging|production)")

	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))

	secretManager := NewSecretManager()

	if s, err := secretManager.GetSecret(Clerk); err != nil {
		logger.Error(err.Error())
		os.Exit(1)
	} else {
		clerk.SetKey(s)
	}

	app := &application{
		config:  cfg,
		logger:  logger,
		secrets: &secretManager,
	}

	err := app.serve()
	if err != nil {
		logger.Error(err.Error())
		os.Exit(1)
	}
}
