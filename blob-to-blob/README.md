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

Storage Insights for 1 hour when copying tiny few byte files (all are under < 20 B) files using `azcopy copy`:

![Small file copy statistics](https://user-images.githubusercontent.com/2357647/209936847-fdbc6303-90b6-47df-ad95-099828753f12.png)


### Links

[Optimize file synchronization](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-optimize#optimize-file-synchronization)
