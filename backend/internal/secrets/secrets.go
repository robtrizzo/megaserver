package secrets

import (
	"fmt"
	"log/slog"
	"os"
	"strings"
)

type SecretType int

const (
	Clerk SecretType = iota
)

type Secrets struct {
	SecretKey string
}

type SecretManager interface {
	GetSecret(key SecretType) (string, error)
}

func NewSecretManager(logger *slog.Logger) SecretManager {
	return &secretManagerImpl{
		keyMap: map[SecretType]string{
			Clerk: strings.TrimSpace(os.Getenv("CLERK_SECRET_KEY")),
		},
		logger: logger,
	}
}

type secretManagerImpl struct {
	keyMap map[SecretType]string

	logger *slog.Logger
}

func (s *secretManagerImpl) GetSecret(keyType SecretType) (string, error) {
	if k := s.keyMap[keyType]; k != "" {
		return k, nil
	}
	return "", fmt.Errorf("secret not found for type %d", keyType)
}
