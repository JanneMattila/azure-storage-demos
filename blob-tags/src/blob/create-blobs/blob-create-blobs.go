package main

import (
	"bufio"
	"context"
	"crypto/rand"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
)

type Stats struct {
	uploaded  int64
	errors    int64
	startTime time.Time
	totalSize int64
}

// Job represents a blob upload task
type Job struct {
	blobName string
	content  []byte
}

func main() {
	// Define command line parameters
	inputDir := flag.String("indir", "datas", "Directory containing input files")
	filePattern := flag.String("pattern", "data-*.txt", "Pattern for input files")
	storageAccount := flag.String("account", "", "Azure Storage account name")
	storageKey := flag.String("key", "", "Azure Storage account access key")
	containerName := flag.String("container", "", "Container name for blob upload")
	concurrency := flag.Int("concurrency", 0, "Number of concurrent uploads (0 = automatic based on CPU cores)")
	contentSizeKB := flag.Int("size", 1, "Content size in KB for each blob")
	connectionString := flag.String("connection", "", "Azure Storage connection string (alternative to account+key)")
	verbose := flag.Bool("verbose", false, "Enable verbose logging")
	flag.Parse()

	// Validate required parameters
	if *connectionString == "" && (*storageAccount == "" || *storageKey == "") {
		log.Fatal("Either connection string or storage account name and key are required")
	}

	if *containerName == "" {
		log.Fatal("Container name is required")
	}

	// Set default concurrency based on CPU cores if not specified
	workerCount := *concurrency
	if workerCount <= 0 {
		workerCount = runtime.NumCPU() * 10 // Multiplier for IO-bound operations
		log.Printf("Auto-configuring to %d workers based on %d CPU cores", workerCount, runtime.NumCPU())
	}

	// Initialize statistics
	stats := Stats{startTime: time.Now()}

	// Find input files
	log.Printf("Looking for input files matching '%s' in '%s'", *filePattern, *inputDir)
	inputFiles, err := filepath.Glob(filepath.Join(*inputDir, *filePattern))
	if err != nil {
		log.Fatalf("Error finding input files: %v", err)
	}

	if len(inputFiles) == 0 {
		log.Fatal("No input files found")
	}

	log.Printf("Found %d input files", len(inputFiles))

	// Create blob client
	var client *azblob.Client
	var containerURL string
	if *connectionString != "" {
		client, containerURL, err = createBlobClientFromConnectionString(*connectionString, *containerName)
	} else {
		client, containerURL, err = createBlobClient(*storageAccount, *storageKey, *containerName)
	}
	if err != nil {
		log.Fatalf("Error creating blob client: %v", err)
	}

	// Generate content for blobs (1KB default)
	contentSize := *contentSizeKB * 1024
	content := generateRandomContent(contentSize)

	// Read all blob names from input files
	blobNames := []string{}
	for _, file := range inputFiles {
		names, err := readBlobNamesFromFile(file)
		if err != nil {
			log.Printf("Error reading from %s: %v", file, err)
			atomic.AddInt64(&stats.errors, 1)
			continue
		}
		blobNames = append(blobNames, names...)
	}

	log.Printf("Found %d blob names to upload", len(blobNames))

	// Create a job queue with buffer capacity
	jobQueueSize := min(10000, len(blobNames)) // Buffer up to 10K jobs or the number of blobs, whichever is smaller
	jobs := make(chan Job, jobQueueSize)

	// Create a WaitGroup to wait for all workers
	var wg sync.WaitGroup

	// Start worker pool
	log.Printf("Starting %d worker goroutines", workerCount)
	for i := 0; i < workerCount; i++ {
		wg.Add(1)
		go func(workerId int) {
			defer wg.Done()
			for job := range jobs {
				// Process the job
				err := uploadBlob(client, containerURL, job.blobName, job.content, *verbose && workerId == 0)
				if err != nil {
					log.Printf("Error uploading blob %s: %v", job.blobName, err)
					atomic.AddInt64(&stats.errors, 1)
				} else {
					atomic.AddInt64(&stats.uploaded, 1)
					atomic.AddInt64(&stats.totalSize, int64(len(job.content)))

					// Print progress periodically - only one worker reports to avoid log spam
					if workerId == 0 {
						uploaded := atomic.LoadInt64(&stats.uploaded)
						if uploaded%100 == 0 {
							percent := float64(uploaded) * 100.0 / float64(len(blobNames))
							log.Printf("Progress: %d/%d blobs uploaded (%.1f%%)",
								uploaded, len(blobNames), percent)
						}
					}
				}
			}
			log.Printf("Worker %d finished", workerId)
		}(i)
	}

	// Submit all jobs to the queue
	startTime := time.Now()
	log.Printf("Queueing %d upload jobs", len(blobNames))
	for _, blobName := range blobNames {
		jobs <- Job{
			blobName: blobName,
			content:  content,
		}
	}
	close(jobs) // Signal that no more jobs are coming

	// Wait for all workers to complete
	wg.Wait()

	// Calculate statistics about job submission rate
	submissionTime := time.Since(startTime)
	if len(blobNames) > 0 {
		submissionRate := float64(len(blobNames)) / submissionTime.Seconds()
		log.Printf("Job submission completed in %.2f seconds (%.1f jobs/sec)",
			submissionTime.Seconds(), submissionRate)
	}

	// Print final statistics
	elapsed := time.Since(stats.startTime)
	log.Printf("Operation completed in %v", elapsed)
	log.Printf("Total blobs uploaded: %d", stats.uploaded)
	log.Printf("Total errors: %d", stats.errors)
	log.Printf("Total data size: %s", formatSize(stats.totalSize))

	if stats.uploaded > 0 {
		uploadRate := float64(stats.totalSize) / elapsed.Seconds()
		blobsPerSecond := float64(stats.uploaded) / elapsed.Seconds()
		log.Printf("Upload rate: %s/s (%.1f blobs/sec)",
			formatSize(int64(uploadRate)), blobsPerSecond)
	}
}

// min returns the smaller of x or y
func min(x, y int) int {
	if x < y {
		return x
	}
	return y
}

// readBlobNamesFromFile reads blob names from a file created by datagenerator.go
func readBlobNamesFromFile(filepath string) ([]string, error) {
	file, err := os.Open(filepath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var names []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		name := strings.TrimSpace(scanner.Text())
		if name != "" {
			names = append(names, name)
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return names, nil
}

// createBlobClient creates an Azure Blob client using account key
func createBlobClient(accountName, accountKey, containerName string) (*azblob.Client, string, error) {
	// Create credential using the shared key
	cred, err := azblob.NewSharedKeyCredential(accountName, accountKey)
	if err != nil {
		return nil, "", fmt.Errorf("failed to create shared key credential: %v", err)
	}

	// Create the blob service client
	serviceURL := fmt.Sprintf("https://%s.blob.core.windows.net", accountName)
	client, err := azblob.NewClientWithSharedKeyCredential(serviceURL, cred, nil)
	if err != nil {
		return nil, "", fmt.Errorf("failed to create blob service client: %v", err)
	}

	// Container URL for later use in upload operations - just the container name
	containerURL := containerName

	return client, containerURL, nil
}

// createBlobClientFromConnectionString creates an Azure Blob client using connection string
func createBlobClientFromConnectionString(connectionString, containerName string) (*azblob.Client, string, error) {
	// Create client from connection string
	client, err := azblob.NewClientFromConnectionString(connectionString, nil)
	if err != nil {
		return nil, "", fmt.Errorf("failed to create client from connection string: %v", err)
	}

	// Container URL for later use in upload operations - just the container name
	containerURL := containerName

	return client, containerURL, nil
}

// generateRandomContent generates random binary data of specified size
func generateRandomContent(size int) []byte {
	content := make([]byte, size)
	rand.Read(content)
	return content
}

// uploadBlob uploads a single blob to Azure Storage
func uploadBlob(client *azblob.Client, containerName string, blobName string, content []byte, verbose bool) error {
	if verbose {
		log.Printf("Uploading blob: %s", blobName)
	}

	ctx := context.Background()

	// Clean up the blob name - remove any leading slash
	if strings.HasPrefix(blobName, "/") {
		blobName = blobName[1:]
	}

	// Format: just containerName/blobName
	// The SDK will construct the full URL with the account name internally
	blobURL := containerName + "/" + blobName

	// Upload the content directly
	_, err := client.UploadBuffer(
		ctx,
		blobURL,
		"application/octet-stream", // content type
		content,
		&azblob.UploadBufferOptions{},
	)

	return err
}

// Format file size in human-readable format
func formatSize(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d bytes", bytes)
	}

	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}

	return fmt.Sprintf("%.2f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}
