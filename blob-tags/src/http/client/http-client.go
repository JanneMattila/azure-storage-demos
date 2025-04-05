package main

import (
	"bytes"
	"crypto/tls"
	"flag"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type Stats struct {
	completed      uint64
	errors         uint64
	startTime      time.Time
	lastReportTime time.Time
	lastCompleted  uint64
}

type WorkItem struct {
	URL     string
	Headers map[string]string
}

// Global payload that all requests will use
var globalPayload = []byte(`<Tags><TagSet></TagSet></Tags>`)

// Global storage for all URL paths that will be processed
var urlPaths []string

// Global base URL that will be prefixed to all paths
var baseURL string

func main() {
	numWorkers := flag.Int("workers", runtime.NumCPU()*10, "Number of worker goroutines")
	baseURLArg := flag.String("baseurl", "http://localhost:8080", "Base URL for requests")
	dataDir := flag.String("datadir", "datas", "Directory containing data files")
	dataPattern := flag.String("pattern", "*.txt", "Pattern for data files")
	flag.Parse()

	baseURL = *baseURLArg

	stats := &Stats{startTime: time.Now(), lastReportTime: time.Now()}

	// Load all data files into memory
	log.Printf("Loading data files from %s matching %s...", *dataDir, *dataPattern)
	files, err := filepath.Glob(filepath.Join(*dataDir, *dataPattern))
	if err != nil {
		log.Fatalf("Failed to find data files: %v", err)
	}

	if len(files) == 0 {
		log.Fatalf("No data files found in %s matching %s", *dataDir, *dataPattern)
	}

	// Read all URL paths into global memory
	for _, file := range files {
		log.Printf("Reading file: %s", file)
		data, err := ioutil.ReadFile(file)
		if err != nil {
			log.Printf("Error reading file %s: %v", file, err)
			continue
		}

		// Split file content into lines and add to global URL paths
		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line != "" {
				urlPaths = append(urlPaths, line)
			}
		}
	}

	totalRequests := len(urlPaths)
	if totalRequests == 0 {
		log.Fatalf("No URLs found in data files")
	}

	log.Printf("Loaded %d URLs into memory", totalRequests)

	// Calculate work distribution
	itemsPerWorker := totalRequests / *numWorkers
	if itemsPerWorker == 0 {
		itemsPerWorker = 1
		*numWorkers = totalRequests
	}

	// Create channel for workers to signal completion
	var wg sync.WaitGroup

	// Setup periodic stats reporting
	go reportStats(stats)

	// Start workers with their assigned slice of the data
	log.Printf("Starting %d workers, each processing ~%d URLs...", *numWorkers, itemsPerWorker)
	for i := 0; i < *numWorkers; i++ {
		wg.Add(1)

		// Calculate start and end indices for this worker
		startIdx := i * itemsPerWorker
		endIdx := startIdx + itemsPerWorker

		// Make sure the last worker gets any remaining items
		if i == *numWorkers-1 {
			endIdx = totalRequests
		}

		// Don't exceed array bounds
		if endIdx > totalRequests {
			endIdx = totalRequests
		}

		// Skip workers with no items to process
		if startIdx >= totalRequests {
			wg.Done()
			continue
		}

		// Start worker with its portion of the data
		go processWorkerItems(i, urlPaths[startIdx:endIdx], stats, &wg)
	}

	wg.Wait()

	elapsed := time.Since(stats.startTime)
	rps := float64(stats.completed) / elapsed.Seconds()

	log.Printf("All done! Completed %d requests in %v (%.2f req/sec)",
		stats.completed, elapsed, rps)
	log.Printf("Errors: %d (%.2f%%)", stats.errors,
		float64(stats.errors)/float64(stats.completed+1)*100) // Add 1 to avoid division by zero
}

func processWorkerItems(id int, paths []string, stats *Stats, wg *sync.WaitGroup) {
	defer wg.Done()

	// Create optimized HTTP client with connection pooling
	client := &http.Client{
		Transport: &http.Transport{
			Proxy: http.ProxyFromEnvironment,
			DialContext: (&net.Dialer{
				Timeout:   30 * time.Second,
				KeepAlive: 30 * time.Second,
			}).DialContext,
			MaxIdleConns:        100,
			MaxIdleConnsPerHost: 100,
			IdleConnTimeout:     90 * time.Second,
			TLSHandshakeTimeout: 10 * time.Second,
			TLSClientConfig:     &tls.Config{InsecureSkipVerify: true}, // For testing only!
		},
		Timeout: 30 * time.Second,
	}

	// log.Printf("Worker %d processing %d items", id, len(paths))

	headers := map[string]string{
		"Content-Type": "application/xml",
		"x-ms-version": "2025-05-05",
	}

	for _, path := range paths {
		// Construct full URL
		fullURL := baseURL + path

		req, err := http.NewRequest("PUT", fullURL, bytes.NewReader(globalPayload))
		if err != nil {
			atomic.AddUint64(&stats.errors, 1)
			continue
		}

		// Set headers
		for k, v := range headers {
			req.Header.Set(k, v)
		}

		resp, err := client.Do(req)
		if err != nil {
			atomic.AddUint64(&stats.errors, 1)
			continue
		}
		resp.Body.Close() // Important to prevent resource leaks

		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			atomic.AddUint64(&stats.completed, 1)
		} else {
			atomic.AddUint64(&stats.errors, 1)
		}

		// Occasionally report progress
		// if (i+1)%1000 == 0 {
		// 	log.Printf("Worker %d: Processed %d/%d items", id, i+1, len(paths))
		// }
	}

	// log.Printf("Worker %d: Finished processing %d items", id, len(paths))
}

func reportStats(stats *Stats) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		now := time.Now()
		completed := atomic.LoadUint64(&stats.completed)
		errors := atomic.LoadUint64(&stats.errors)

		elapsed := now.Sub(stats.startTime)
		interval := now.Sub(stats.lastReportTime)

		totalRPS := float64(completed) / elapsed.Seconds()
		currentRPS := float64(completed-stats.lastCompleted) / interval.Seconds()

		log.Printf("Progress: %d completed, %d errors, %.2f req/sec (current: %.2f req/sec)",
			completed, errors, totalRPS, currentRPS)

		stats.lastReportTime = now
		stats.lastCompleted = completed
	}
}
