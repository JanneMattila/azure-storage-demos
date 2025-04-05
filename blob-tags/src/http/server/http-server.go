package main

import (
	"flag"
	"io/ioutil"
	"log"
	"net/http"
)

func main() {
	// Define command line parameters
	port := flag.String("port", "8080", "Port to listen on")
	flag.Parse()

	// Handler function for all requests
	handler := func(w http.ResponseWriter, r *http.Request) {
		// For PUT requests, read and discard the request body
		if r.Method == http.MethodPut {
			// Read body to prevent connection issues
			_, err := ioutil.ReadAll(r.Body)
			if err != nil {
				log.Printf("Error reading body: %v", err)
			}
			// log.Printf("Received PUT request to %s with %d bytes payload", r.URL.Path, len(body))

			// Always respond with 200 OK
			w.WriteHeader(http.StatusOK)
			return
		}

		// For non-PUT requests, respond with 200 OK as well
		log.Printf("Received %s request to %s", r.Method, r.URL.Path)
		w.WriteHeader(http.StatusOK)
	}

	// Register handler for all paths
	http.HandleFunc("/", handler)

	// Start the server
	serverAddr := ":" + *port
	log.Printf("Starting server on %s, accepting all PUT requests with 200 OK responses", serverAddr)
	if err := http.ListenAndServe(serverAddr, nil); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
