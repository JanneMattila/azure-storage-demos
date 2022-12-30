# Blob to Blob

## Example

Example storage account:

![Storage account usage metric](https://user-images.githubusercontent.com/2357647/209114259-aa75166a-52c4-4f16-a5e1-758d69487d61.png)

Most important metrics:

- 31.6 GiB of data
- 187.64 Million items

### Sync

To run `dry-run`:

```powershell
azcopy sync `
($uriSource + $sasSource) `
($uriTarget + $sasTarget) `
    --recursive `
    --dry-run
```

To execute sync:

```powershell
azcopy sync `
($uriSource + $sasSource) `
($uriTarget + $sasTarget) `
    --recursive
```

### Copy

To execute copy:

```powershell
azcopy copy `
($uriSource + "/" + $sasSource) `
($uriTarget + "/" + $sasTarget) `
    --overwrite ifSourceNewer `
    --recursive
```

### Notes

#### Tiny files copy

Copying tiny few byte files (all are under < 20 B) files using `azcopy copy`.

Source Storage account Insights for 1 hour period:

![Small file copy statistics source account](https://user-images.githubusercontent.com/2357647/209936847-fdbc6303-90b6-47df-ad95-099828753f12.png)

Target Storage account Insights for 1 hour period:

![Small file copy statistics target account](https://user-images.githubusercontent.com/2357647/209938096-8ed414f0-7946-49cd-8d3f-a5b3de136ad4.png)

Example output:

```
Job be6e41e4-dd16-3744-4a35-5571c34349d8 summary
Elapsed Time (Minutes): 186.262
Number of File Transfers: 4130000
Number of Folder Property Transfers: 0
Total Number of Transfers: 4130000
Number of Transfers Completed: 4068820
Number of Transfers Failed: 0
Number of Transfers Skipped: 87
TotalBytesTransferred: 22182726
Final Job Status: Cancelled
```

=> `20k files per minute`

### Links

[Optimize file synchronization](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-optimize#optimize-file-synchronization)
