package main

import (
	"flag"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	// Define command line parameters
	numFiles := flag.Int("files", 10, "Number of data files to generate")
	rowsPerFile := flag.Int("rows", 1000, "Number of URL paths per file")
	outputDir := flag.String("outdir", "data", "Directory to store generated files")
	filePrefix := flag.String("prefix", "urls", "Prefix for generated filenames")
	flag.Parse()

	fmt.Printf("Generating %d files with %d URLs each in %s\n", *numFiles, *rowsPerFile, *outputDir)

	// Create output directory if it doesn't exist
	if err := os.MkdirAll(*outputDir, 0755); err != nil {
		fmt.Printf("Error creating directory %s: %v\n", *outputDir, err)
		os.Exit(1)
	}

	// Track statistics
	totalRows := 0
	totalSize := int64(0)

	// Generate files
	for fileNum := 0; fileNum < *numFiles; fileNum++ {
		fileName := filepath.Join(*outputDir, fmt.Sprintf("%s-%d.txt", *filePrefix, fileNum+1))

		file, err := os.Create(fileName)
		if err != nil {
			fmt.Printf("Error creating file %s: %v\n", fileName, err)
			continue
		}

		// Generate URLs for this file
		for row := 0; row < *rowsPerFile; row++ {
			// Generate random date and time components
			year := rand.Intn(10) + 2020 // Years from 2020 to 2029
			month := rand.Intn(12) + 1   // Months 1-12
			day := rand.Intn(28) + 1     // Days 1-28 (simplified)
			hour := rand.Intn(24)        // Hours 0-23
			minute := rand.Intn(60)      // Minutes 0-59
			second := rand.Intn(60)      // Seconds 0-59

			// Generate a GUID-like string
			guid := generateGUID()

			// Create URL path
			url := fmt.Sprintf("/%d/%02d/%02d/%02d/%02d/%02d/log-%s.txt\n",
				year, month, day, hour, minute, second, guid)

			// Write to file
			bytesWritten, err := file.WriteString(url)
			if err != nil {
				fmt.Printf("Error writing to file %s: %v\n", fileName, err)
				file.Close()
				continue
			}

			totalSize += int64(bytesWritten)
			totalRows++
		}

		file.Close()
		fmt.Printf("Generated file %s\n", fileName)
	}

	// Output statistics
	fmt.Printf("\nGeneration complete!\n")
	fmt.Printf("Total rows generated: %s\n", formatNumber(totalRows))
	fmt.Printf("Total data size: %s\n", formatSize(totalSize))
}

// Generate a simple GUID-like string
func generateGUID() string {
	// Create random hex characters
	const chars = "0123456789abcdef"
	result := strings.Builder{}

	// Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
	sections := []int{8, 4, 4, 4, 12}

	for i, length := range sections {
		if i > 0 {
			result.WriteByte('-')
		}

		for j := 0; j < length; j++ {
			result.WriteByte(chars[rand.Intn(len(chars))])
		}
	}

	return result.String()
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

// Format number in human-readable format (e.g., 5 Million, 2.5 Billion)
func formatNumber(num int) string {
	if num < 1000 {
		return fmt.Sprintf("%d", num)
	} else if num < 1000000 {
		return fmt.Sprintf("%.2f Thousand", float64(num)/1000)
	} else if num < 1000000000 {
		return fmt.Sprintf("%.2f Million", float64(num)/1000000)
	} else {
		return fmt.Sprintf("%.2f Billion", float64(num)/1000000000)
	}
}

func init() {
	// Initialize random seed
	rand.Seed(time.Now().UnixNano())
}
