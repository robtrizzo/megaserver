package api

import (
	"flag"
	"log/slog"
	"megaserver/internal/secrets"
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
	secrets *secrets.SecretManager
	wg      sync.WaitGroup
}

func Init() {
	var cfg config
	flag.IntVar(&cfg.port, "port", 4000, "API server port")
	flag.StringVar(&cfg.env, "env", "development", "Environment (development|staging|production)")

	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))

	secretManager := secrets.NewSecretManager(logger)

	if s, err := secretManager.GetSecret(secrets.Clerk); err != nil {
		logger.Error(err.Error())
		panic(err)
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
