package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type Stats struct {
	completed       uint64
	errors          uint64
	startTime       time.Time
	lastReportTime  time.Time
	lastCompleted   uint64
	errorDetails    sync.Map   // Map of error URL -> error message
	errorCounts     sync.Map   // Map of error message -> count
	mu              sync.Mutex // Mutex for synchronized access to maps
	logErrorDetails bool       // Flag to control detailed error logging
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

// Azure Storage authentication variables
var (
	storageAccountName string
	storageAccountKey  string
	useAzureStorage    bool
)

func main() {
	numWorkers := flag.Int("workers", runtime.NumCPU()*10, "Number of worker goroutines")
	dataDir := flag.String("datadir", "datas", "Directory containing data files")
	dataPattern := flag.String("pattern", "*.txt", "Pattern for data files")
	storageAccount := flag.String("account", "", "Azure Storage account name")
	storageKey := flag.String("key", "", "Azure Storage account access key")
	container := flag.String("container", "", "Azure Storage container name (will be prefixed to paths)")
	verbose := flag.Bool("verbose", false, "Enable verbose error logging")
	logErrorDetails := flag.Bool("logerrors", false, "Enable logging error details during processing (may impact performance)")
	showErrors := flag.Bool("showerrors", true, "Show error details at the end of execution")
	batchSize := flag.Int("batchsize", 1000000, "Maximum number of URLs to process in a batch")
	flag.Parse()

	// Configure Azure Storage settings
	storageAccountName = *storageAccount
	storageAccountKey = *storageKey
	containerPath := ""
	if *container != "" {
		containerPath = "/" + *container
	}

	log.Printf("Using Azure Storage authentication for account: %s", storageAccountName)
	baseURL = fmt.Sprintf("https://%s.blob.core.windows.net%s", storageAccountName, containerPath)

	stats := &Stats{
		startTime:       time.Now(),
		lastReportTime:  time.Now(),
		logErrorDetails: *logErrorDetails,
	}

	// Find all data files matching the pattern
	log.Printf("Finding data files from %s matching %s...", *dataDir, *dataPattern)
	files, err := filepath.Glob(filepath.Join(*dataDir, *dataPattern))
	if err != nil {
		log.Fatalf("Failed to find data files: %v", err)
	}

	if len(files) == 0 {
		log.Fatalf("No data files found in %s matching %s", *dataDir, *dataPattern)
	}

	// Start stats reporting in the background
	go reportStats(stats)

	// Setup counting of total processed items across all batches
	var totalProcessed uint64

	// Process files in batches
	for _, file := range files {
		log.Printf("Processing file: %s", file)
		processFileInBatches(file, stats, numWorkers, batchSize, verbose)

		// Update total processed after each file
		totalProcessed += atomic.LoadUint64(&stats.completed) + atomic.LoadUint64(&stats.errors)
	}

	elapsed := time.Since(stats.startTime)
	completed := atomic.LoadUint64(&stats.completed)
	errors := atomic.LoadUint64(&stats.errors)

	rps := float64(completed) / elapsed.Seconds()

	log.Printf("All done! Completed %d requests in %v (%.2f req/sec)",
		completed, elapsed, rps)
	log.Printf("Errors: %d (%.2f%%)", errors,
		float64(errors)/float64(completed+errors)*100)

	// Display error details at the end
	if errors > 0 && *showErrors {
		log.Println("Error details:")
		errorMap := make(map[string]int) // Track error types and frequencies

		// Collect all error details for output
		stats.errorCounts.Range(func(key, value interface{}) bool {
			errMsg := key.(string)
			count := value.(int)
			errorMap[errMsg] = count
			return true
		})

		// Show error summary by type (sorted by frequency)
		log.Println("Error summary by type:")

		type errorCount struct {
			msg   string
			count int
		}

		// Convert to slice for sorting
		errorSlice := make([]errorCount, 0, len(errorMap))
		for msg, count := range errorMap {
			errorSlice = append(errorSlice, errorCount{msg, count})
		}

		// Sort by count, descending
		sort.Slice(errorSlice, func(i, j int) bool {
			return errorSlice[i].count > errorSlice[j].count
		})

		// Print the sorted errors
		for _, e := range errorSlice {
			log.Printf("  [%d occurrences] %s", e.count, e.msg)
		}
	}
}

// processFileInBatches reads a file in batches and processes URLs to avoid memory limits
func processFileInBatches(filePath string, stats *Stats, numWorkers *int, batchSize *int, verbose *bool) {
	// Open the file
	file, err := os.ReadFile(filePath)
	if err != nil {
		log.Fatalf("Failed to read data file %s: %v", filePath, err)
	}

	// Split content into lines
	lines := bytes.Split(file, []byte("\n"))
	totalLines := len(lines)
	log.Printf("Found %d URLs in file %s", totalLines, filePath)

	// Process in batches to avoid memory issues
	for batchStart := 0; batchStart < totalLines; batchStart += *batchSize {
		batchEnd := batchStart + *batchSize
		if batchEnd > totalLines {
			batchEnd = totalLines
		}

		// Process this batch
		log.Printf("Processing batch %d to %d of %d URLs", batchStart+1, batchEnd, totalLines)
		processBatch(lines[batchStart:batchEnd], stats, numWorkers, verbose)

		// Clear the batch from memory to allow GC
		if batchEnd < totalLines {
			// Only explicitly clear if we have more batches to process
			for i := batchStart; i < batchEnd; i++ {
				lines[i] = nil
			}
			runtime.GC() // Force garbage collection between batches
		}
	}
}

// processBatch handles processing a batch of URLs using worker pool pattern
func processBatch(lines [][]byte, stats *Stats, numWorkers *int, verbose *bool) {
	// Convert byte slices to strings and clean them up
	urlPaths := make([]string, 0, len(lines))
	for _, line := range lines {
		if len(line) == 0 {
			continue // Skip empty lines
		}

		// Trim whitespace and any carriage returns
		path := strings.TrimSpace(string(line))
		if path == "" {
			continue
		}

		// Add to our list of paths to process
		urlPaths = append(urlPaths, path)
	}

	// No valid URLs in this batch
	if len(urlPaths) == 0 {
		log.Println("No valid URLs found in this batch")
		return
	}

	// Distribute work among workers
	workerCount := *numWorkers
	if workerCount > len(urlPaths) {
		workerCount = len(urlPaths)
	}

	// Calculate paths per worker
	pathsPerWorker := len(urlPaths) / workerCount
	if pathsPerWorker < 1 {
		pathsPerWorker = 1
	}

	log.Printf("Starting %d workers to process %d URLs (approx. %d per worker)",
		workerCount, len(urlPaths), pathsPerWorker)

	// Create a wait group to synchronize workers
	var wg sync.WaitGroup
	wg.Add(workerCount)

	// Launch workers
	for i := 0; i < workerCount; i++ {
		start := i * pathsPerWorker
		end := (i + 1) * pathsPerWorker
		if i == workerCount-1 {
			// Last worker takes remaining paths
			end = len(urlPaths)
		}

		// Check if this worker has any paths to process
		if start < len(urlPaths) {
			go processWorkerItems(urlPaths[start:end], stats, &wg, *verbose)
		} else {
			// No paths for this worker, just mark it as done
			wg.Done()
		}
	}

	// Wait for all workers to complete
	wg.Wait()
}

func processWorkerItems(paths []string, stats *Stats, wg *sync.WaitGroup, verbose bool) {
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

	// Standard headers for all requests
	headers := map[string]string{
		"Content-Type": "application/xml; charset=UTF-8",
		"x-ms-version": "2025-05-05",
	}

	for _, path := range paths {
		fullURL := baseURL + path + "?comp=tags"

		// Create a new request with the global payload
		req, err := http.NewRequest("PUT", fullURL, bytes.NewReader(globalPayload))
		if err != nil {
			atomic.AddUint64(&stats.errors, 1)
			errMsg := fmt.Sprintf("Request creation error: %v", err)
			stats.errorDetails.Store(fullURL, errMsg)

			// Aggregate error count
			updateErrorCount(stats, errMsg)

			if verbose {
				log.Printf("Error creating request for %s: %v", fullURL, err)
			}
			continue
		}

		// Set headers
		for k, v := range headers {
			req.Header.Set(k, v)
		}

		// Set a fresh x-ms-date header for each request
		currentTime := time.Now().UTC().Format(http.TimeFormat)
		req.Header.Set("x-ms-date", currentTime)

		// Update authorization header after setting date
		authHeader := createAuthorizationHeader(req, storageAccountName, storageAccountKey)
		req.Header.Set("Authorization", authHeader)

		// Execute the request
		resp, err := client.Do(req)
		if err != nil {
			atomic.AddUint64(&stats.errors, 1)
			errMsg := fmt.Sprintf("Request execution error: %v", err)
			stats.errorDetails.Store(fullURL, errMsg)

			// Aggregate error count
			updateErrorCount(stats, errMsg)

			if verbose {
				log.Printf("Error executing request for %s: %v", fullURL, err)
			}
			continue
		}

		// Read response body for error cases
		var responseBody []byte
		if resp.StatusCode >= 400 {
			responseBody, _ = ioutil.ReadAll(resp.Body)
		}

		// Always close the response body
		resp.Body.Close() // Important to prevent resource leaks

		// Track successful and failed requests
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			atomic.AddUint64(&stats.completed, 1)
		} else {
			// For error handling
			atomic.AddUint64(&stats.errors, 1)
			errMsg := fmt.Sprintf("Status: %d, Response: %s", resp.StatusCode, string(responseBody))
			stats.errorDetails.Store(fullURL, errMsg)

			// Aggregate error count
			updateErrorCount(stats, errMsg)

			if verbose {
				log.Printf("Error for %s: %s", fullURL, errMsg)
			}
		}
	}
}

// updateErrorCount aggregates error messages by count
func updateErrorCount(stats *Stats, errMsg string) {
	// If error details logging is disabled, just increment the count
	if !stats.logErrorDetails {
		return
	}

	// Normalize the error message - take only first 200 chars for grouping similar errors
	normalizedMsg := errMsg
	if len(normalizedMsg) > 200 {
		normalizedMsg = normalizedMsg[:200]
	}

	// Need to handle concurrent access to sync.Map safely
	stats.mu.Lock()
	defer stats.mu.Unlock()

	// Get current count for this error type
	val, ok := stats.errorCounts.Load(normalizedMsg)
	var count int
	if ok {
		count = val.(int)
	}

	// Increment count and store
	stats.errorCounts.Store(normalizedMsg, count+1)
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

		// Report top error types if there are any errors
		if errors > 0 {
			// Create a temporary map to store error message -> count
			errorSummary := make(map[string]int)

			// Gather error counts from the sync.Map
			stats.errorCounts.Range(func(key, value interface{}) bool {
				errMsg := key.(string)
				count := value.(int)
				errorSummary[errMsg] = count
				return true
			})

			// Show up to 3 most common errors
			if len(errorSummary) > 0 {
				type errorCount struct {
					msg   string
					count int
				}

				// Convert to slice for sorting
				errorSlice := make([]errorCount, 0, len(errorSummary))
				for msg, count := range errorSummary {
					errorSlice = append(errorSlice, errorCount{msg, count})
				}

				// Sort by count, descending
				sort.Slice(errorSlice, func(i, j int) bool {
					return errorSlice[i].count > errorSlice[j].count
				})

				log.Println("Top errors:")
				for i, e := range errorSlice {
					if i >= 3 {
						break
					}
					// Truncate long messages for display
					msg := e.msg
					if len(msg) > 100 {
						msg = msg[:97] + "..."
					}
					log.Printf("  [%d occurrences] %s", e.count, msg)
				}
			}
		}

		stats.lastReportTime = now
		stats.lastCompleted = completed
	}
}

// createAuthorizationHeader creates the Azure Storage authorization header
func createAuthorizationHeader(request *http.Request, storageAccount string, storageKey string) string {
	// Format: Authorization="[SharedKey|SharedKeyLite] <AccountName>:<Signature>"
	canonicalizedResource := getCanonicalizedResource(request.URL, storageAccount)

	// Get content-length as a string
	contentLength := ""
	if request.ContentLength > 0 {
		contentLength = fmt.Sprintf("%d", request.ContentLength)
	}

	// Get the canonicalized headers
	canonicalizedHeadersStr := canonicalizedHeaders(request)

	// Construct string to sign exactly as Azure expects
	// According to the error message, this is the format expected:
	// PUT\n\n\n30\n\napplication/xml; charset=UTF-8\n\n\n\n\n\n\nx-ms-date:Fri, 04 Apr 2025 06:42:53 GMT\nx-ms-version:2025-05-05\n/stor00000001010/logs/file.txt\ncomp:tags
	stringToSign := fmt.Sprintf("%s\n\n\n%s\n\n%s\n\n\n\n\n\n\n%s\n%s",
		request.Method,
		contentLength,
		request.Header.Get("Content-Type"),
		canonicalizedHeadersStr,
		canonicalizedResource)

	signature := computeHmac256(stringToSign, storageKey)
	return fmt.Sprintf("SharedKey %s:%s", storageAccount, signature)
}

// getCanonicalizedResource constructs the canonicalized resource string for Azure Storage
func getCanonicalizedResource(uri *url.URL, accountName string) string {
	// Start with the forward slash
	canonicalizedResource := "/"

	// Add the account name
	canonicalizedResource += accountName

	// Add the path part
	canonicalizedResource += uri.Path

	// Process query parameters if they exist
	queryParams := uri.Query()
	if len(queryParams) > 0 {
		// Get the keys and sort them
		params := make([]string, 0, len(queryParams))
		for key := range queryParams {
			params = append(params, key)
		}
		sort.Strings(params)

		// Add each query parameter in sorted order
		for _, param := range params {
			values := queryParams[param]
			sort.Strings(values)
			for _, value := range values {
				canonicalizedResource += fmt.Sprintf("\n%s:%s", strings.ToLower(param), value)
			}
		}
	}

	return canonicalizedResource
}

// canonicalizedHeaders gets canonicalized headers for Azure Storage
func canonicalizedHeaders(request *http.Request) string {
	// Get all headers that start with x-ms-
	msHeaders := make(map[string]string)
	for header, values := range request.Header {
		headerName := strings.ToLower(header)
		if strings.HasPrefix(headerName, "x-ms-") {
			msHeaders[headerName] = strings.Join(values, ",")
		}
	}

	// No x-ms- headers found
	if len(msHeaders) == 0 {
		return ""
	}

	// Get the keys and sort them
	keys := make([]string, 0, len(msHeaders))
	for key := range msHeaders {
		keys = append(keys, key)
	}
	sort.Strings(keys)

	// Build the canonicalized headers string
	var result strings.Builder
	for _, key := range keys {
		result.WriteString(key)
		result.WriteString(":")
		result.WriteString(msHeaders[key])
		result.WriteString("\n")
	}

	return strings.TrimSuffix(result.String(), "\n")
}

// computeHmac256 computes the HMAC-SHA256 signature for Azure Storage authentication
func computeHmac256(message string, secret string) string {
	key, _ := base64.StdEncoding.DecodeString(secret)
	h := hmac.New(sha256.New, key)
	h.Write([]byte(message))
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}
