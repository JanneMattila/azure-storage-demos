# Scan files

This script scans files in a specified directory, optionally filtering by modification date, and splits the list of files into smaller files containing a specified number of entries each.

See the script for details: [split-files.sh](./split-files.sh).

## Usage

```bash
./split-files.sh -p <search_path> -o <output_prefix> -s <split_size> -d [date_filter]
```

- `search_path`: The directory to search for files.
- `output_prefix`: The prefix for the output files.
- `split_size`: The number of file paths to include in each output file.
- `date_filter` (optional): Only include files modified after this date (format: YYYY-MM-DD).

## Example

```bash
./split-files.sh -p /path/to/search -o output -s 1000 -d 2023-01-01
```

This command will search for files in `/path/to/search`, filter them to include only those modified after January 1, 2023, and split the list into files named `output_1.txt`, `output_2.txt`, etc., each containing up to 1000 file paths.

Example output from running the script:

```console
$ ./split-files.sh -p /home -s 100000 -o files
Starting file search...
Search path: /home
Split size: 100000 files per output file
Output prefix: files

Step 1: No date filter applied

Step 2: Processing files in batches of 100000...
Progress will be shown for each batch created

  Processed 10000 files... (currently writing to files-1.txt)
  Processed 20000 files... (currently writing to files-1.txt)
  Processed 30000 files... (currently writing to files-1.txt)
✓ Created files-1.txt with 30375 files

======================================
Done! Summary:
  Total files in search path:
  Output files created: 1
  Files per output file: 100000 (max)
======================================

$ cat files-1.txt | head
/home/data/file1.txt
/home/data/file2.txt
/home/data/file3.txt
```
