using System.Text.Json.Serialization;

partial class Program
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
}
