# Make the script executable
chmod +x split-files.sh

# Basic usage (searches /data, splits into 100000 files per output)
./split-files.sh

# Custom path and split size
./split-files.sh -p /data -s 100000 -o files

# With date filter (only files newer than 2024-01-01)
./split-files.sh -p /data -d "2024-01-01" -s 100000 -o files

# Show help
./split-files.sh -h
