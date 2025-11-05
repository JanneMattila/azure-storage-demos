
$storage = "<your storage account name>"
$storage = "stor0000000000100"
$container = "files"
$path = "folder1/folder2"
$filename = "file.txt"

Login-AzAccount

$accessToken = Get-AzAccessToken -ResourceUrl "https://$storage.blob.core.windows.net/"

# Blob endpoint examples
## Download full blob
Invoke-RestMethod `
    -Method "GET" `
    -Headers @{ 
    "x-ms-version" = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessToken.Token `
    -Uri "https://$storage.blob.core.windows.net/$container/$path/$filename"

# Output:
# -------
# Hello there!

## Set blob tags
# https://learn.microsoft.com/en-us/azure/storage/blobs/storage-manage-find-blobs?tabs=azure-portal
# Requires "Storage Blob Data Owner" role or equivalent permissions
Invoke-WebRequest `
    -Method "PUT" `
    -Headers @{ 
    "x-ms-version"     = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessToken.Token `
    -Uri "https://$storage.blob.core.windows.net/$container/$path/$filename`?comp=tags" `
    -Body "<Tags><TagSet><Tag><Key>example</Key><Value>test</Value></Tag></TagSet></Tags>"

## Get blob tags
Invoke-RestMethod `
    -Method "GET" `
    -Headers @{ 
    "x-ms-version" = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessToken.Token `
    -Uri "https://$storage.blob.core.windows.net/$container/$path/$filename`?comp=tags"

## Remove blob tags
Invoke-WebRequest `
    -Method "PUT" `
    -Headers @{ 
    "x-ms-version"     = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessToken.Token `
    -Uri "https://$storage.blob.core.windows.net/$container/$path/$filename`?comp=tags" `
    -Body "<Tags><TagSet></TagSet></Tags>"

# Storage is normal storage account but let's try DFS endpoint
$accessTokenDFS = Get-AzAccessToken -ResourceUrl "https://$storage.dfs.core.windows.net/"

## Download full blob using DFS endpoint
Invoke-RestMethod `
    -Method "GET" `
    -Headers @{ 
    "x-ms-version" = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessTokenDFS.Token `
    -Uri "https://$storage.dfs.core.windows.net/$container/$path/$filename"

# Output:
# -------
# Hello there!

## Let's list the directory
Invoke-RestMethod `
    -Method "GET" `
    -Headers @{ 
    "x-ms-version" = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessTokenDFS.Token `
    -Uri "https://$storage.dfs.core.windows.net/$container`?resource=filesystem&recursive=false" | ConvertTo-Json

# Output:
# -------
# {
#   "paths": [
#     {
#       "isDirectory": "true",
#       "name": "folder1"
#     }
#   ]
# }

## List ACLs of the directory
Invoke-RestMethod `
    -Method "HEAD" `
    -Headers @{ 
    "x-ms-version" = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $accessTokenDFS.Token `
    -Uri "https://$storage.dfs.core.windows.net/$container/$path`?action=getAccessControl"

# Output:
# Invoke-RestMethod: Response status code does not indicate success: 400 (This operation is only supported on a hierarchical namespace account.).
