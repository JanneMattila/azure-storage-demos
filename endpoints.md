# Storage Account Endpoints

Setup basic variables:

```powershell
$storage = "<your storage account name>"
$container = "files"
$path = "folder1/folder2"
$filename = "file.txt"

Login-AzAccount

$accessToken = Get-AzAccessToken -ResourceUrl "https://$storage.blob.core.windows.net/"
$accessTokenDFS = Get-AzAccessToken -ResourceUrl "https://$storage.dfs.core.windows.net/"
```

> [!IMPORTANT]  
> Storage Account is not enabled with Hierarchical Namespace (HNS).

Upload a file to Blob storage:

```powershell
"https://$storage.blob.core.windows.net/$container/$path/$filename"
```

Now let's fetch that file using Blob endpoint:

```powershell
Invoke-RestMethod `
    -Method "GET" `
    -Headers @{ 
    "x-ms-version" = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessTokenDFS.Token `
    -Uri "https://$storage.dfs.core.windows.net/$container/$path/$filename"
```

Output:

```text
Hello there!
```

Set blob tags:

```powershell
Invoke-WebRequest `
    -Method "PUT" `
    -Headers @{ 
    "x-ms-version"     = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessToken.Token `
    -Uri "https://$storage.blob.core.windows.net/$container/$path/$filename`?comp=tags" `
    -Body "<Tags><TagSet><Tag><Key>example</Key><Value>test</Value></Tag></TagSet></Tags>"
```

Let's now use the DFS endpoint to get blob:

```powershell
Invoke-RestMethod `
    -Method "GET" `
    -Headers @{ 
    "x-ms-version" = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessTokenDFS.Token `
    -Uri "https://$storage.dfs.core.windows.net/$container/$path/$filename"
```

Output:

```text
Hello there!
```

Let's try to list ACLs using DFS endpoint:

```powershell
Invoke-RestMethod `
    -Method "HEAD" `
    -Headers @{ 
    "x-ms-version" = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessTokenDFS.Token `
    -Uri "https://$storage.dfs.core.windows.net/$container/$path`?action=getAccessControl"
```

Output:

```text
400 (This operation is only supported on a hierarchical namespace account.).
```

Go to Portal and enable Hierarchical Namespace (HNS) on the storage account to use DFS features.
After validation, it will fail with:

```json
{
  "startTime": "2025-11-05T18:00:07.0653107Z",
  "id": "2ed767a8-7a21-4b18-9b21-9a0e8323e4ec",
  "incompatibleFeatures": [],
  "blobValidationErrors": [
      "files:folder1/folder2/file.txt, Unable to proceed HnsOn migration due to incompatible feature, Blob Tags not supported",
      ""
  ],
  "scannedBlobCount": 1,
  "invalidBlobCount": 1,
  "endTime": "2025-11-05T18:00:19.7651924Z"
}
```

The key part being:

```text
Unable to proceed HnsOn migration due to incompatible feature, Blob Tags not supported
```

Let's remove the tags and try again:

```powershell
Invoke-WebRequest `
    -Method "PUT" `
    -Headers @{ 
    "x-ms-version"     = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessToken.Token `
    -Uri "https://$storage.blob.core.windows.net/$container/$path/$filename`?comp=tags" `
    -Body "<Tags><TagSet></TagSet></Tags>"
```

After removing the tags, retry the HNS migration validation, and it should succeed.

Now you can use DFS features like ACLs:

```powershell
Invoke-RestMethod `
    -Method "HEAD" `
    -Headers @{ 
    "x-ms-version" = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessTokenDFS.Token `
    -Uri "https://$storage.dfs.core.windows.net/$container/$path`?action=getAccessControl"
```

Let's try to set blob tags again now that HNS is enabled:

```powershell
Invoke-WebRequest `
    -Method "PUT" `
    -Headers @{ 
    "x-ms-version"     = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessToken.Token `
    -Uri "https://$storage.blob.core.windows.net/$container/$path/$filename`?comp=tags" `
    -Body "<Tags><TagSet><Tag><Key>example</Key><Value>test</Value></Tag></TagSet></Tags>"
```

Output:

```text
FeatureNotEnabled: A required feature for this operation is not enabled on the account.
```
