using Azure;
using Azure.Storage;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using System.Threading;
using System.Linq;
using System.Text.Json.Serialization;
using System.Diagnostics;

class Program
{
    class ConfigurationFile
    {
        [JsonPropertyName("operation")]
        public string Operation { get; set; } = "";
        [JsonPropertyName("storageName")]
        public string StorageName { get; set; } = "";
        [JsonPropertyName("storageKey")]
        public string StorageKey { get; set; } = "";
        [JsonPropertyName("tagFilter")]
        public string TagFilter { get; set; } = "";
        [JsonPropertyName("folder")]
        public string Folder { get; set; } = "";
        [JsonPropertyName("rowsPerFile")]
        public int RowsPerFile { get; set; } = 100000;
    }
    
    static async Task Main(string[] args)
    {
        if (args.Length < 1)
        {
            Console.WriteLine("Usage: StorageApp <config-file>");
            return;
        }

        string configFile = args[0];
        
        if (!File.Exists(configFile))
        {
            Console.WriteLine($"Error: Configuration file '{configFile}' not found.");
            return;
        }
        
        ConfigurationFile config;
        try
        {
            string jsonContent = await File.ReadAllTextAsync(configFile);
            config = JsonSerializer.Deserialize<ConfigurationFile>(jsonContent) 
                ?? throw new Exception("Failed to deserialize configuration file.");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error reading configuration file: {ex.Message}");
            return;
        }
        
        // Validate configuration
        if (string.IsNullOrEmpty(config.StorageName) || string.IsNullOrEmpty(config.StorageKey) || 
            string.IsNullOrEmpty(config.Folder) || string.IsNullOrEmpty(config.Operation))
        {
            Console.WriteLine("Error: Invalid configuration. Make sure storageName, storageKey, folder, and operation are specified.");
            return;
        }
        
        try
        {
            // Create BlobServiceClient
            var client = new BlobServiceClient(
                new Uri($"https://{config.StorageName}.blob.core.windows.net/"), 
                new StorageSharedKeyCredential(config.StorageName, config.StorageKey));
                
            // Ensure the output folder exists
            Directory.CreateDirectory(config.Folder);
            
            // Process based on operation
            if (config.Operation.ToLower() == "export")
            {
                await ExportBlobsToFiles(client, config);
            }
            else if (config.Operation.ToLower() == "set")
            {
                await SetBlobTags(client, config);
            }
            else
            {
                Console.WriteLine($"Error: Unknown operation '{config.Operation}'. Supported operations are 'export' and 'set'.");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error during execution: {ex.Message}");
        }
    }
    
    static async Task ExportBlobsToFiles(BlobServiceClient client, ConfigurationFile config)
    {
        Console.WriteLine("Starting export operation...");
        
        // Build the tag filter - using the same filter from the original code
        string tagFilter = config.TagFilter ?? "tag1='value1' AND tag2='value2'";
        Console.WriteLine($"Using tag filter: {tagFilter}");
        
        int fileCounter = 1;
        int blobCounter = 0;
        int batchCounter = 0;
        List<TimeSpan> batchTimes = new List<TimeSpan>();
        var totalStopwatch = Stopwatch.StartNew();

        // Setup producer-consumer queue for file writing
        var fileWriteQueue = new BlockingCollection<FileWriteItem>(new ConcurrentQueue<FileWriteItem>());
        var cancellationTokenSource = new CancellationTokenSource();
        var fileWriterTask = Task.Run(() => FileWriterWorker(config.Folder, fileWriteQueue, cancellationTokenSource.Token));
        
        try
        {
            var batchStopwatch = Stopwatch.StartNew();
            var currentBatch = new List<string>();
            
            await foreach (Page<TaggedBlobItem> page in client.FindBlobsByTagsAsync(tagFilter).AsPages())
            {
                // Capture timing for this batch
                batchStopwatch.Stop();
                batchCounter++;
                batchTimes.Add(batchStopwatch.Elapsed);
                
                // Calculate statistics
                TimeSpan averageBatchTime = TimeSpan.FromTicks((long)batchTimes.Average(t => t.Ticks));
                TimeSpan totalTime = totalStopwatch.Elapsed;
                int blobsInCurrentBatch = page.Values.Count();
                
                // Log batch statistics
                Console.WriteLine($"Batch #{batchCounter} fetched in {batchStopwatch.Elapsed.TotalSeconds:F2} seconds ({blobsInCurrentBatch} blobs)");
                Console.WriteLine($"  Average batch time: {averageBatchTime.TotalSeconds:F2} seconds");
                Console.WriteLine($"  Total time elapsed: {totalTime.TotalMinutes:F2} minutes");
                Console.WriteLine($"  Estimated throughput: {blobCounter / Math.Max(1, totalTime.TotalSeconds):F2} blobs/second");
                
                // Reset stopwatch for next batch
                batchStopwatch.Restart();
                
                foreach (TaggedBlobItem blobItem in page.Values)
                {
                    currentBatch.Add("/" + blobItem.BlobName);
                    blobCounter++;
                    
                    // When we hit the limit, add to queue and reset
                    if (currentBatch.Count >= config.RowsPerFile)
                    {
                        // Queue the batch for writing
                        fileWriteQueue.Add(new FileWriteItem 
                        { 
                            FileNumber = fileCounter,
                            BlobNames = new List<string>(currentBatch)
                        });
                        
                        Console.WriteLine($"Queued {currentBatch.Count} blobs for file {fileCounter}");
                        
                        currentBatch.Clear();
                        fileCounter++;
                    }
                }
            }
            
            // Queue any remaining blob names
            if (currentBatch.Count > 0)
            {
                fileWriteQueue.Add(new FileWriteItem 
                { 
                    FileNumber = fileCounter,
                    BlobNames = new List<string>(currentBatch)
                });
                
                Console.WriteLine($"Queued {currentBatch.Count} blobs for file {fileCounter}");
            }
            
            // Signal no more items will be added
            fileWriteQueue.CompleteAdding();
            
            // Wait for all writes to complete
            Console.WriteLine("Waiting for file writer to complete...");
            await fileWriterTask;
            
            totalStopwatch.Stop();
            TimeSpan totalRunTime = totalStopwatch.Elapsed;
            
            Console.WriteLine($"Export completed. Total blobs: {blobCounter}, Total files: {fileCounter}");
            Console.WriteLine($"Total batches: {batchCounter}, Average batch time: {TimeSpan.FromTicks((long)batchTimes.Average(t => t.Ticks)).TotalSeconds:F2} seconds");
            Console.WriteLine($"Total run time: {totalRunTime.TotalMinutes:F2} minutes");
            Console.WriteLine($"Final throughput: {blobCounter / totalRunTime.TotalSeconds:F2} blobs/second");
            
            // Extrapolation for billions
            if (batchCounter > 0 && blobCounter > 0)
            {
                long estimatedBlobsPerBatch = blobCounter / batchCounter;
                double timePerBillion = (totalRunTime.TotalHours * 1_000_000_000) / blobCounter;
                Console.WriteLine($"Extrapolated time for 1 billion blobs: {timePerBillion:F2} hours");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error during export: {ex.Message}");
            // Make sure to stop the file writer thread
            cancellationTokenSource.Cancel();
        }
        finally
        {
            // Ensure we always signal the file writer to stop even if there's an exception
            if (!fileWriteQueue.IsAddingCompleted)
            {
                fileWriteQueue.CompleteAdding();
            }
        }
    }
    
    // Class to represent items in the file write queue
    class FileWriteItem
    {
        public int FileNumber { get; set; }
        public List<string> BlobNames { get; set; } = new List<string>();
    }
    
    // Background worker that processes the file write queue
    static async Task FileWriterWorker(string folderPath, BlockingCollection<FileWriteItem> queue, CancellationToken cancellationToken)
    {
        int filesWritten = 0;
        int totalBlobsWritten = 0;
        var fileWriteStopwatch = Stopwatch.StartNew();
        
        try
        {
            // Process queue items until the queue is marked as complete and empty
            while (!queue.IsCompleted)
            {
                FileWriteItem item;
                try
                {
                    // Try to take an item from the queue with a timeout
                    if (queue.TryTake(out item, 100, cancellationToken))
                    {
                        // We got an item, process it
                        var itemStopwatch = Stopwatch.StartNew();
                        string filePath = Path.Combine(folderPath, $"data-{item.FileNumber}.txt");
                        await File.WriteAllLinesAsync(filePath, item.BlobNames, cancellationToken);
                        
                        filesWritten++;
                        totalBlobsWritten += item.BlobNames.Count;
                        
                        Console.WriteLine($"File writer: Wrote file {item.FileNumber} with {item.BlobNames.Count} blobs in {itemStopwatch.ElapsedMilliseconds} ms");
                        Console.WriteLine($"  Total files written: {filesWritten}, Total blobs written: {totalBlobsWritten}");
                    }
                }
                catch (OperationCanceledException)
                {
                    // Cancellation requested
                    Console.WriteLine("File writer: Operation was canceled");
                    break;
                }
            }
            
            fileWriteStopwatch.Stop();
            Console.WriteLine($"File writer completed: {filesWritten} files written with {totalBlobsWritten} blobs in {fileWriteStopwatch.Elapsed.TotalSeconds:F2} seconds");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"File writer error: {ex.Message}");
        }
    }
    
    static async Task SetBlobTags(BlobServiceClient client, ConfigurationFile config)
    {
        Console.WriteLine("Starting set operation...");
        
        // Get list of files in the folder
        string[] files = Directory.GetFiles(config.Folder, "data-*.txt");
        
        if (files.Length == 0)
        {
            Console.WriteLine("No data files found in the specified folder.");
            return;
        }
        
        Console.WriteLine($"Found {files.Length} files to process.");
        
        // Determine number of threads based on processor count
        int processorCount = Environment.ProcessorCount;
        int filesPerProcessor = (int)Math.Ceiling(files.Length / (double)processorCount);
        
        Console.WriteLine($"Using {processorCount} processors, {filesPerProcessor} files per processor.");
        
        // Group files for each processor
        List<List<string>> fileGroups = new List<List<string>>();
        for (int i = 0; i < files.Length; i += filesPerProcessor)
        {
            fileGroups.Add(files.Skip(i).Take(filesPerProcessor).ToList());
        }
        
        // Create tasks for each processor
        List<Task> tasks = new List<Task>();
        foreach (var fileGroup in fileGroups)
        {
            tasks.Add(ProcessFilesAsync(client, fileGroup));
        }
        
        // Wait for all tasks to complete
        await Task.WhenAll(tasks);
        
        Console.WriteLine("Set operation completed.");
    }
    
    static async Task ProcessFilesAsync(BlobServiceClient client, List<string> files)
    {
        foreach (string file in files)
        {
            await ProcessFileAsync(client, file);
        }
    }
    
    static async Task ProcessFileAsync(BlobServiceClient client, string filePath)
    {
        Console.WriteLine($"Processing file: {Path.GetFileName(filePath)}");
        
        string[] blobNames;
        try
        {
            blobNames = await File.ReadAllLinesAsync(filePath);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error reading file {filePath}: {ex.Message}");
            return;
        }
        
        // Process each blob in parallel
        List<Task> blobTasks = new List<Task>();
        
        foreach (string blobName in blobNames)
        {
            if (string.IsNullOrWhiteSpace(blobName))
                continue;
                
            // Parse the blob name to get container and blob path
            string[] parts = blobName.Split('/', 2);
            if (parts.Length < 2)
            {
                Console.WriteLine($"Invalid blob name format: {blobName}");
                continue;
            }
            
            string containerName = parts[0];
            string blobPath = parts[1];
            
            // Add task to set tags
            blobTasks.Add(SetBlobTagAsync(client, containerName, blobPath));
            
            // Limit concurrent operations to avoid throttling
            if (blobTasks.Count >= 100)
            {
                await Task.WhenAny(blobTasks);
                blobTasks = blobTasks.Where(t => !t.IsCompleted).ToList();
            }
        }
        
        // Wait for any remaining tasks
        await Task.WhenAll(blobTasks);
        
        Console.WriteLine($"Completed processing file: {Path.GetFileName(filePath)}");
    }
    
    static async Task SetBlobTagAsync(BlobServiceClient client, string containerName, string blobPath)
    {
        try
        {
            var containerClient = client.GetBlobContainerClient(containerName);
            var blobClient = containerClient.GetBlobClient(blobPath);
            
            // Set a sample tag - you can customize this based on your needs
            var tags = new Dictionary<string, string>
            {
                { "Processed", "True" },
                { "ProcessedDate", DateTime.UtcNow.ToString("o") }
            };
            
            await blobClient.SetTagsAsync(tags);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error setting tags for blob {containerName}/{blobPath}: {ex.Message}");
        }
    }
}
