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

# Build find command
FIND_CMD="find \"$SEARCH_PATH\" -type f"

# Add date filter if specified
if [ -n "$DATE_FILTER" ]; then
  # Validate date format
  if ! date -d "$DATE_FILTER" >/dev/null 2>&1; then
    echo "Error: Invalid date format. Use YYYY-MM-DD"
    exit 1
  fi
  echo "Date filter: Files newer than $DATE_FILTER"
  FIND_CMD="$FIND_CMD -newermt \"$DATE_FILTER\""
else
  echo "Date filter: None"
fi

# Create a temporary file for all results
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

echo "Searching for files..."
eval "$FIND_CMD" > "$TEMP_FILE"

# Count total files found
TOTAL_FILES=$(wc -l < "$TEMP_FILE")
echo "Found $TOTAL_FILES files"

if [ "$TOTAL_FILES" -eq 0 ]; then
  echo "No files found matching the criteria"
  exit 0
fi

# Calculate number of output files needed
NUM_OUTPUT_FILES=$(( (TOTAL_FILES + SPLIT_SIZE - 1) / SPLIT_SIZE ))
echo "Creating $NUM_OUTPUT_FILES output file(s)..."

# Split the results into multiple files
split -l "$SPLIT_SIZE" -d -a ${#NUM_OUTPUT_FILES} "$TEMP_FILE" "${OUTPUT_PREFIX}-"

# Rename files to have .txt extension and proper numbering
counter=1
for file in ${OUTPUT_PREFIX}-*; do
  if [ -f "$file" ]; then
    mv "$file" "${OUTPUT_PREFIX}-${counter}.txt"
    file_count=$(wc -l < "${OUTPUT_PREFIX}-${counter}.txt")
    echo "Created ${OUTPUT_PREFIX}-${counter}.txt with $file_count files"
    counter=$((counter + 1))
  fi
done

echo "Done! Created $NUM_OUTPUT_FILES output file(s)"
