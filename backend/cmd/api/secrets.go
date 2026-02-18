package api

import (
	"fmt"
	"os"
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

func NewSecretManager() SecretManager {
	return &secretManagerImpl{
		keyMap: map[SecretType]string{
			Clerk: "CLERK_SECRET_KEY",
		},
	}
}

type secretManagerImpl struct {
	keyMap map[SecretType]string
}

func (s *secretManagerImpl) GetSecret(keyType SecretType) (string, error) {
	if k := os.Getenv(s.keyMap[keyType]); k != "" {
		return k, nil
	}
	return "", fmt.Errorf("secret not found: %s", s.keyMap[keyType])
}