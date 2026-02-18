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
	mux.Handle("/api/", newGroup("/api", func(g *routeGroup) {
		g.Handle("/settings", userSettings)
	}, clerkhttp.WithHeaderAuthorization(), logRoute()))

	mux.Handle("/admin/", newGroup("/admin", func(g *routeGroup) {
		g.Handle("/settings", adminSettings)
	}, clerkhttp.WithHeaderAuthorization(), adminRoute()))

	http.ListenAndServe(":3000", mux)
	return nil
}

func logRoute() funcHandler {
	return func(h http.Handler) http.Handler { return nil }
}

func adminRoute() funcHandler {
	// user.Get()
	return func(h http.Handler) http.Handler { return nil }
}

type funcHandler func(http.Handler) http.Handler

func newGroup(prefix string, register func(*routeGroup), middlewares ...funcHandler) http.Handler {
	g := &routeGroup{mux: http.NewServeMux(), prefix: prefix}
	register(g)
	return chain(g.mux, middlewares...)
}

func chain(h http.Handler, middlewares ...funcHandler) http.Handler {
	for i := len(middlewares) - 1; i >= 0; i-- {
		h = middlewares[i](h)
	}
	return h
}

type routeGroup struct {
	mux    *http.ServeMux
	prefix string
}

func (g *routeGroup) Handle(path string, h http.HandlerFunc) {
	g.mux.HandleFunc(g.prefix+path, h)
}

func publicRoute(w http.ResponseWriter, r *http.Request) {
	w.Write([]byte(`{"access": "public"}`))
}

func userSettings(w http.ResponseWriter, r *http.Request) {
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

func adminSettings(w http.ResponseWriter, r *http.Request) {
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
