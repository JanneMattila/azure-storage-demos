package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/container"
)

type Stats struct {
	blobsFound int64
	errors     int64
	startTime  time.Time
	batchTimes []time.Duration
}

type FileWriterTask struct {
	BlobNames []string
}

func main() {
	// Define command line parameters
	var tagFilter string
	flag.StringVar(&tagFilter, "tagfilter", "\"My field\" = 'My value'", "Filter expression for blob tags")
	outputDir := flag.String("outdir", "data", "Directory for output files")
	filePrefix := flag.String("prefix", "data", "Prefix for output files")
	storageAccount := flag.String("account", "", "Azure Storage account name")
	storageKey := flag.String("key", "", "Azure Storage account access key")
	containerName := flag.String("container", "", "Storage container name")
	rowsPerFile := flag.Int("rowsperfile", 1000000, "Number of blob names per file")
	connectionString := flag.String("connection", "", "Azure Storage connection string (alternative to account+key)")
	maxResults := flag.Int("maxresults", 5000, "Maximum number of results per page")
	flag.Parse()

	fmt.Println("Using tagfilter: ", tagFilter)

	// Validate required parameters
	if *connectionString == "" && (*storageAccount == "" || *storageKey == "") {
		log.Fatal("Either connection string or storage account name and key are required")
	}

	if *containerName == "" {
		log.Fatal("Container name is required")
	}

	// Initialize statistics
	stats := Stats{startTime: time.Now()}

	// Create output directory if it doesn't exist
	err := os.MkdirAll(*outputDir, 0755)
	if err != nil {
		log.Fatalf("Error creating output directory: %v", err)
	}

	// Create blob client
	var client *azblob.Client
	if *connectionString != "" {
		client, err = azblob.NewClientFromConnectionString(*connectionString, nil)
	} else {
		// Create credential using the shared key
		cred, credErr := azblob.NewSharedKeyCredential(*storageAccount, *storageKey)
		if credErr != nil {
			log.Fatalf("Failed to create shared key credential: %v", credErr)
		}

		// Create the blob service client
		serviceURL := fmt.Sprintf("https://%s.blob.core.windows.net", *storageAccount)
		client, err = azblob.NewClientWithSharedKeyCredential(serviceURL, cred, nil)
	}

	if err != nil {
		log.Fatalf("Error creating blob client: %v", err)
	}

	// Get a container client
	containerClient := client.ServiceClient().NewContainerClient(*containerName)

	// Setup file writing
	fileWriteChan := make(chan FileWriterTask, 10) // Buffer for 10 batches
	fileWriterWg := &sync.WaitGroup{}
	fileWriterWg.Add(1)
	cancellationChan := make(chan struct{})

	// Start file writer goroutine
	go fileWriterWorker(*outputDir, *filePrefix, *rowsPerFile, fileWriteChan, fileWriterWg, cancellationChan)

	log.Printf("Starting export operation with tag filter: %s", tagFilter)
	totalStopwatch := time.Now()
	batchCounter := 0

	// Create options for FilterBlobs
	opts := &container.FilterBlobsOptions{
		MaxResults: to.Ptr(int32(*maxResults)),
	}

	// Use marker for pagination
	var marker *string = nil

	for {
		batchStopwatch := time.Now()

		// Set the marker for pagination if we have one
		if marker != nil {
			opts.Marker = marker
		}

		// Get a batch of blobs that match the filter
		resp, err := containerClient.FilterBlobs(context.Background(), tagFilter, opts)
		if err != nil {
			log.Printf("Error fetching blobs with tags: %v", err)
			atomic.AddInt64(&stats.errors, 1)
			break
		}

		// Capture timing for this batch
		batchTime := time.Since(batchStopwatch)
		batchCounter++
		stats.batchTimes = append(stats.batchTimes, batchTime)

		// Calculate average batch time
		averageBatchTime := averageBatchTime(stats.batchTimes)
		totalTime := time.Since(totalStopwatch)

		// Count blobs in this batch
		blobsInBatch := len(resp.Blobs)
		newBlobCounter := atomic.AddInt64(&stats.blobsFound, int64(blobsInBatch))

		// Log batch statistics
		log.Printf("Batch #%d fetched in %.2f seconds (%d blobs)",
			batchCounter, batchTime.Seconds(), blobsInBatch)
		log.Printf("  Average batch time: %.2f seconds", averageBatchTime.Seconds())
		log.Printf("  Total time elapsed: %.2f minutes", totalTime.Minutes())
		log.Printf("  Estimated throughput: %.2f blobs/second",
			float64(newBlobCounter)/totalTime.Seconds())

		// If we have blobs in this batch, write them to a file
		if blobsInBatch > 0 {
			// Extract blob names
			blobNames := make([]string, 0, blobsInBatch)
			for _, blob := range resp.Blobs {
				// Format similar to C# code - prepend with "/" and container name
				blobNames = append(blobNames, "/"+*containerName+"/"+*blob.Name)
			}

			// Send to file writer worker
			fileWriteChan <- FileWriterTask{
				BlobNames: blobNames,
			}
		}

		// Check if there are more results
		if resp.NextMarker == nil || *resp.NextMarker == "" {
			// No more results
			break
		}

		// Update the marker for the next batch
		marker = resp.NextMarker
	}

	// Signal we're done adding tasks
	close(fileWriteChan)

	// Wait for file writer to complete
	log.Printf("Waiting for file writer to complete...")
	fileWriterWg.Wait()

	// Calculate and display final statistics
	totalRunTime := time.Since(totalStopwatch)

	log.Printf("Export completed. Total blobs: %d", stats.blobsFound)
	log.Printf("Total batches: %d, Average batch time: %.2f seconds",
		batchCounter, averageBatchTime(stats.batchTimes).Seconds())
	log.Printf("Total run time: %.2f minutes", totalRunTime.Minutes())
	log.Printf("Final throughput: %.2f blobs/second",
		float64(stats.blobsFound)/totalRunTime.Seconds())

	// Extrapolation for billions
	if batchCounter > 0 && stats.blobsFound > 0 {
		blobsPerBatch := stats.blobsFound / int64(batchCounter)
		timePerBillion := (totalRunTime.Hours() * 1_000_000_000) / float64(stats.blobsFound)
		log.Printf("Extrapolated time for 1 billion blobs: %.2f hours", timePerBillion)
		log.Printf("Estimated blobs per batch: %d", blobsPerBatch)
	}
}

// Calculate average batch time
func averageBatchTime(times []time.Duration) time.Duration {
	if len(times) == 0 {
		return 0
	}
	var total time.Duration
	for _, t := range times {
		total += t
	}
	return total / time.Duration(len(times))
}

// fileWriterWorker handles writing blob names to files
func fileWriterWorker(folderPath, filePrefix string, rowsPerFile int, tasks <-chan FileWriterTask, wg *sync.WaitGroup, cancel <-chan struct{}) {
	defer wg.Done()

	currentFileNumber := 1
	totalBlobsWritten := 0
	rowsInCurrentFile := 0
	fileWriteStopwatch := time.Now()

try:
	for {
		select {
		case task, ok := <-tasks:
			if !ok {
				// Channel closed, we're done
				break try
			}

			// Write blob names to the current file
			filePath := filepath.Join(folderPath, fmt.Sprintf("%s-%d.txt", filePrefix, currentFileNumber))

			// Open file for appending or create if it doesn't exist
			file, err := os.OpenFile(filePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
			if err != nil {
				log.Printf("Error opening file %s: %v", filePath, err)
				continue
			}

			// Use a buffered writer for better performance
			writer := bufio.NewWriter(file)
			for _, blobName := range task.BlobNames {
				fmt.Fprintln(writer, blobName)
			}
			writer.Flush()
			file.Close()

			rowsInCurrentFile += len(task.BlobNames)
			totalBlobsWritten += len(task.BlobNames)

			// Check if we need to start a new file
			if rowsInCurrentFile >= rowsPerFile {
				currentFileNumber++
				rowsInCurrentFile = 0
			}

		case <-cancel:
			// Cancellation requested
			log.Println("File writer: Operation was canceled")
			return
		}
	}

	elapsed := time.Since(fileWriteStopwatch)
	log.Printf("File writer completed: %d files written with %d blobs in %.2f seconds",
		currentFileNumber, totalBlobsWritten, elapsed.Seconds())
}
