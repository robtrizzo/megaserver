package api

import (
	"net/http"

	clerkhttp "github.com/clerk/clerk-sdk-go/v2/http"
)

func (app *application) routes() http.Handler {
	mux := http.NewServeMux()

	mountGroup(mux, "/api", func(g *routeGroup) {
		g.Handle("/settings", app.userSettings)
	}, clerkhttp.WithHeaderAuthorization(), logRoute())

	mountGroup(mux, "/admin", func(g *routeGroup) {
		g.Handle("/settings", app.adminSettings)
	}, clerkhttp.WithHeaderAuthorization(), adminRoute())

	mux.HandleFunc("/", app.notFoundResponse)

	return mux
}

type routeGroup struct {
	mux    *http.ServeMux
	prefix string
}

func (g *routeGroup) Handle(path string, h http.HandlerFunc) {
	g.mux.HandleFunc(g.prefix+path, h)
}

func mountGroup(mux *http.ServeMux, prefix string, register func(*routeGroup), middlewares ...middleware) {
	g := &routeGroup{mux: http.NewServeMux(), prefix: prefix}
	register(g)
	mux.Handle(prefix+"/", http.StripPrefix(prefix, chain(g.mux, middlewares...)))
}
