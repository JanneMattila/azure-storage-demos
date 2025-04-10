using Azure.Storage.Blobs.Models;

partial class Program
{
    // Class to represent items in the file write queue
    class FileWriteItem
    {
        public required IReadOnlyList<TaggedBlobItem> Blobs { get; set; }
    }
}
