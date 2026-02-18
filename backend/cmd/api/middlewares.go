package api

import "net/http"

type middleware func(http.Handler) http.Handler

func chain(h http.Handler, middlewares ...middleware) http.Handler {
	for i := len(middlewares) - 1; i >= 0; i-- {
		h = middlewares[i](h)
	}
	return h
}

func logRoute() middleware {
	return func(h http.Handler) http.Handler { return nil }
}

func adminRoute() middleware {
	return func(h http.Handler) http.Handler { return nil }
}
