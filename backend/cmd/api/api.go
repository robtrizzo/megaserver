package api

import (
	"fmt"
	"net/http"

	"github.com/clerk/clerk-sdk-go/v2"
	clerkhttp "github.com/clerk/clerk-sdk-go/v2/http"
	"github.com/clerk/clerk-sdk-go/v2/user"
)

func setupRoutes() error {
	secretManager := NewSecretManager()
	if s, err := secretManager.GetSecret(Clerk); err != nil {
		return err
	} else {
		clerk.SetKey(s)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", publicRoute)
	protectedHandler := http.HandlerFunc(protectedRoute)
	mux.Handle(
		"/protected",
		clerkhttp.WithHeaderAuthorization()(protectedHandler),
	)

	http.ListenAndServe(":3000", mux)
	return nil
}

func publicRoute(w http.ResponseWriter, r *http.Request) {
	w.Write([]byte(`{"access": "public"}`))
}

func protectedRoute(w http.ResponseWriter, r *http.Request) {
	claims, ok := clerk.SessionClaimsFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"access": "unauthorized"}`))
		return
	}

	usr, err := user.Get(r.Context(), claims.Subject)
	if err != nil {
		// handle the error
	}
	fmt.Fprintf(w, `{"user_id": "%s", "user_banned": "%t"}`, usr.ID, usr.Banned)
}
