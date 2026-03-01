package main

import (
	"fmt"
	"net/http"
	"time"
)

func main() {
	http.HandleFunc("/infer", func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(100 * time.Millisecond)
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `{"result":"ok"}`)
	})
	http.ListenAndServe(":8080", nil)
}
