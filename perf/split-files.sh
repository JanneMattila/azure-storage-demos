#!/bin/bash

# Script to search for files and split them into multiple text files
# Usage: ./split-files.sh -p /data -d "2024-01-01" -s 100000 -o files
#   -p: Path to search (default: /data)
#   -d: Date filter - only files newer than this date (optional, format: YYYY-MM-DD)
#   -s: Split size - number of files per output file (default: 100000)
#   -o: Output prefix - prefix for output files (default: files)

# Default values
SEARCH_PATH="/data"
DATE_FILTER=""
SPLIT_SIZE=100000
OUTPUT_PREFIX="files"

# Parse command line arguments
while getopts "p:d:s:o:h" opt; do
  case $opt in
    p)
      SEARCH_PATH="$OPTARG"
      ;;
    d)
      DATE_FILTER="$OPTARG"
      ;;
    s)
      SPLIT_SIZE="$OPTARG"
      ;;
    o)
      OUTPUT_PREFIX="$OPTARG"
      ;;
    h)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  -p <path>        Path to search (default: /data)"
      echo "  -d <date>        Date filter - only files newer than this date (format: YYYY-MM-DD, optional)"
      echo "  -s <size>        Split size - number of files per output file (default: 100000)"
      echo "  -o <prefix>      Output prefix - prefix for output files (default: files)"
      echo "  -h               Show this help message"
      echo ""
      echo "Example: $0 -p /data -d \"2024-01-01\" -s 100000 -o files"
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Validate search path exists
if [ ! -d "$SEARCH_PATH" ]; then
  echo "Error: Search path '$SEARCH_PATH' does not exist"
  exit 1
fi

# Validate split size is a positive number
if ! [[ "$SPLIT_SIZE" =~ ^[0-9]+$ ]] || [ "$SPLIT_SIZE" -le 0 ]; then
  echo "Error: Split size must be a positive number"
  exit 1
fi

echo "Starting file search..."
echo "Search path: $SEARCH_PATH"
echo "Split size: $SPLIT_SIZE files per output file"
echo "Output prefix: $OUTPUT_PREFIX"

# Build find command with date filter if specified
if [ -n "$DATE_FILTER" ]; then
  # Validate date format
  if ! date -d "$DATE_FILTER" >/dev/null 2>&1; then
    echo "Error: Invalid date format. Use YYYY-MM-DD"
    exit 1
  fi
  echo ""
  echo "Step 1: Applying date filter (files newer than $DATE_FILTER)..."
  FIND_CMD="find \"$SEARCH_PATH\" -type f -newermt \"$DATE_FILTER\""
else
  echo ""
  echo "Step 1: No date filter applied"
  FIND_CMD="find \"$SEARCH_PATH\" -type f"
fi

echo ""
echo "Step 2: Processing files in batches of $SPLIT_SIZE..."
echo "Progress will be shown for each batch created"
echo ""

# Process files in batches and write directly to output files
file_counter=0
batch_number=1
current_batch_file="${OUTPUT_PREFIX}-${batch_number}.txt"

# Remove any existing output files
rm -f "${OUTPUT_PREFIX}"-*.txt

# Process files with progress indicator
eval "$FIND_CMD" 2>/dev/null | while IFS= read -r filepath; do
  echo "$filepath" >> "$current_batch_file"
  file_counter=$((file_counter + 1))
  
  # Show progress every 10000 files
  if [ $((file_counter % 10000)) -eq 0 ]; then
    echo "  Processed $file_counter files... (currently writing to ${OUTPUT_PREFIX}-${batch_number}.txt)"
  fi
  
  # Check if we need to start a new batch
  if [ $((file_counter % SPLIT_SIZE)) -eq 0 ]; then
    files_in_batch=$(wc -l < "$current_batch_file")
    echo "✓ Created ${OUTPUT_PREFIX}-${batch_number}.txt with $files_in_batch files"
    batch_number=$((batch_number + 1))
    current_batch_file="${OUTPUT_PREFIX}-${batch_number}.txt"
  fi
done

# Handle the last batch if it has files
if [ -f "$current_batch_file" ] && [ -s "$current_batch_file" ]; then
  files_in_batch=$(wc -l < "$current_batch_file")
  echo "✓ Created ${OUTPUT_PREFIX}-${batch_number}.txt with $files_in_batch files"
fi

# Count how many output files were created
OUTPUT_FILES_CREATED=$(ls -1 "${OUTPUT_PREFIX}"-*.txt 2>/dev/null | wc -l)

if [ "$OUTPUT_FILES_CREATED" -eq 0 ]; then
  echo ""
  echo "No files found matching the criteria"
  exit 0
fi

# Count total files processed
TOTAL_FILES_PROCESSED=0
for file in "${OUTPUT_PREFIX}"-*.txt; do
  if [ -f "$file" ]; then
    TOTAL_FILES_PROCESSED=$((TOTAL_FILES_PROCESSED + $(wc -l < "$file")))
  fi
done

echo ""
echo "======================================"
echo "Done! Summary:"
echo "  Total files in search path: $TOTAL_FILES_UNFILTERED"
if [ -n "$DATE_FILTER" ]; then
  echo "  Files matching date filter: $TOTAL_FILES_PROCESSED"
fi
echo "  Output files created: $OUTPUT_FILES_CREATED"
echo "  Files per output file: $SPLIT_SIZE (max)"
echo "======================================"
