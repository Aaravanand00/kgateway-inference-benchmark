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

	http.HandleFunc("/infer-stream", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/x-ndjson")
		w.Header().Set("Transfer-Encoding", "chunked")

		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
			return
		}

		// Flush headers immediately so clients can measure TTFB.
		flusher.Flush()

		// Simulate TTFT: 50ms before first token.
		time.Sleep(50 * time.Millisecond)

		for i := 1; i <= 20; i++ {
			fmt.Fprintf(w, `{"token_id": %d, "text": "token_%d"}`, i, i)
			fmt.Fprint(w, "\n")
			flusher.Flush()
			if i < 20 {
				time.Sleep(10 * time.Millisecond) // ~10ms inter-token latency
			}
		}
	})

	fmt.Println("Server starting on :8080...")
	http.ListenAndServe(":8080", nil)
}
