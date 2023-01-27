using Microsoft.Extensions.Configuration;
using Renci.SshNet;
using Renci.SshNet.Common;
using System.Collections.Concurrent;
using System.Diagnostics;

var builder = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
#if DEBUG
    .AddUserSecrets<Program>()
#endif
    .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
    .AddEnvironmentVariables();

var configuration = builder.Build();
var stopwatch = new Stopwatch();

var threads = configuration.GetValue<int>("threads", 10);
var host = configuration.GetValue<string>("host") ?? throw new ArgumentNullException("host");
var user = configuration.GetValue<string>("user") ?? throw new ArgumentNullException("user");
var password = configuration.GetValue<string>("password") ?? throw new ArgumentNullException("password");
var sourceFolder = configuration.GetValue<string>("sourceFolder") ?? throw new ArgumentNullException("sourceFolder");
var targetFolder = configuration.GetValue<string>("targetFolder", Guid.NewGuid().ToString("D"));

ConcurrentQueue<string> queue = new();
int uploading = 0;

Console.WriteLine("Enumerating files...");
var files = Directory.GetFiles(sourceFolder);
foreach (var path in files)
{
    queue.Enqueue(path);
}

Console.WriteLine($"Starting {threads} threads...");

stopwatch.Start();
var threadList = new List<Thread>();
for (int i = 0; i < threads; i++)
{
    var t = new Thread(() =>
    {
        while (queue.TryDequeue(out var sourceFilename))
        {
            Interlocked.Increment(ref uploading);

            var targetFileName = Path.GetFileName(sourceFilename);
            var relativePath = Path.GetRelativePath(sourceFolder, Path.GetDirectoryName(sourceFilename));
            if (relativePath == ".")
            {
                relativePath = "";
            }
            using var client = new SftpClient(host, user, password);
            client.Connect();
            var targetFullPath = Path.Combine(targetFolder, relativePath);
            var subDirectories = targetFullPath.Split(new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar });

            foreach (var subDirectory in subDirectories)
            {
                if (!client.Exists(subDirectory))
                {
                    try
                    {
                        client.CreateDirectory(subDirectory);

                    }
                    catch (SshException sshEx)
                    {
                        if (sshEx.Message != "BlobAlreadyExists: The specified blob already exists.")
                        {
                            Console.WriteLine(sshEx);
                        }
                    }
                }
                client.ChangeDirectory(subDirectory);
            }

            using var file = File.OpenRead(sourceFilename);
            client.UploadFile(file, targetFileName);
            client.Disconnect();
            Interlocked.Decrement(ref uploading);
        }
    });

    t.Start();
    threadList.Add(t);
}

while (queue.Any())
{
    Console.WriteLine($"{Math.Round(stopwatch.Elapsed.TotalSeconds, 0)}s: Queue: {queue.Count}, Uploading: {uploading}");
    await Task.Delay(1000);
}

foreach (var t in threadList)
{
    t.Join();
}
