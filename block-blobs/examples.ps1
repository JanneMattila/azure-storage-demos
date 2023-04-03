# To generate demo file in bash:
# truncate -s 500m demo.bin
# head -c 500m </dev/urandom > demo2.bin

$storage = "<your storage account name>"
$tenantId = "<your tenant id>"

Login-AzAccount
Login-AzAccount -Tenant $tenantId

$accessToken = Get-AzAccessToken -ResourceUrl "https://$storage.blob.core.windows.net/"
$secureAccessToken = ConvertTo-SecureString -AsPlainText -String $accessToken.Token

# To upload directly using "PUT" to "Archive" tier
Invoke-RestMethod `
    -Method "PUT" `
    -Headers @{ 
    "x-ms-version"     = "2022-11-02"
    "x-ms-blob-type"   = "BlockBlob" 
    "x-ms-access-tier" = "Archive" 
} `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net/block-blobs/part1.bin" `
    -InFile "part1.bin"

# ---

Invoke-RestMethod `
    -Method "GET" `
    -Headers @{ "x-ms-version" = "2022-11-02" } `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net/block-blobs/demo.bin?comp=blocklist&blocklisttype=all" 

# Example output (formatted):
# ---------------------------
# <?xml version="1.0" encoding="utf-8"?>
# <BlockList>
#   <CommittedBlocks>
#     <Block>
#       <Name>NGM0MjI4YjMtNWM5Mi00YzEwLWEyN2QtYzk4YTcyMzZkOWEy</Name>
#       <Size>268435456</Size>
#     </Block>
#     <Block>
#       <Name>NmUzM2JkNTQtOGIxNi00NDBhLTk2ZDctMTE5ZWYyYjQyYWM5</Name>
#       <Size>255852544</Size>
#     </Block>
#   </CommittedBlocks>
#   <UncommittedBlocks />
# </BlockList>
# ---------------------------
# 268435456 = 256 MB
# 255852544 = 244 MB
#           = 500 MB

# Specifying the range header for Blob service operations
# https://learn.microsoft.com/en-us/rest/api/storageservices/specifying-the-range-header-for-blob-service-operations

# Take full file:
Invoke-RestMethod `
    -Method "GET" `
    -Headers @{ 
    "x-ms-version" = "2022-11-02"
} `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net/block-blobs/demo.bin" `
    -OutFile "demo-full.bin"

# Take full first block:
Invoke-RestMethod `
    -Method "GET" `
    -Headers @{ 
    "x-ms-version" = "2022-11-02"
    "Range"        = "bytes=0-268435455" 
} `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net/block-blobs/demo.bin" `
    -OutFile "part1.bin"

# Take full second block:
Invoke-RestMethod `
    -Method "GET" `
    -Headers @{ 
    "x-ms-version" = "2022-11-02"
    "Range"        = "bytes=268435456-" 
} `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net/block-blobs/demo.bin" `
    -OutFile "part2.bin"

# For bash:
cat part1.bin part2.bin > combined.bin
# For cmd:
cmd.exe /c copy part1.bin+part2.bin combined.bin

Get-FileHash -Algorithm SHA256 -Path combined.bin
Get-FileHash -Algorithm SHA256 -Path demo-full.bin

Format-Hex -Path combined.bin -Count 50 -Offset 0
Format-Hex -Path demo-full.bin -Count 50 -Offset 0

# Change pricing tier to "Archive"
# https://learn.microsoft.com/en-us/rest/api/storageservices/set-blob-tier#request-headers
Invoke-RestMethod `
    -Method "PUT" `
    -Headers @{ 
    "x-ms-version"            = "2022-11-02"
    "x-ms-access-tier"        = "Archive"
    "x-ms-rehydrate-priority" = "High"
} `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net/block-blobs/demo.bin?comp=tier"

# Copy "Archive" file to "Hot"
# https://learn.microsoft.com/en-us/azure/storage/blobs/archive-rehydrate-overview
# https://learn.microsoft.com/en-us/rest/api/storageservices/copy-blob
$copyResponse = Invoke-WebRequest `
    -Method "PUT" `
    -Headers @{ 
    "x-ms-version"            = "2022-11-02"
    "x-ms-access-tier"        = "Hot"
    "x-ms-rehydrate-priority" = "High"
    "x-ms-copy-source"        = "https://$storage.blob.core.windows.net/block-blobs/demo.bin"
} `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net/block-blobs/demo-hot.bin"

$copyResponse
$copyResponse.Headers
$copyResponse.Headers["x-ms-copy-status"]

# Check copy status
$statusResponse2 = Invoke-WebRequest `
    -Method "HEAD" `
    -Headers @{ 
    "x-ms-version" = "2022-11-02"
} `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net/block-blobs/demo-hot.bin"

$statusResponse
$statusResponse.Headers
# https://learn.microsoft.com/en-us/rest/api/storageservices/get-blob-properties?tabs=azure-ad#response-headers
# Key                          Value
# ---                          -----
# x-ms-blob-type               {BlockBlob}
# x-ms-copy-id                 {7a01027d-74b7-4cfd-8c12-9ccf78ccd209}
# x-ms-copy-source             {https://<storage>.blob.core.windows.net/block-blobs/demo.bin}
# x-ms-copy-status             {success}
# x-ms-copy-status-description {pending}
# x-ms-copy-progress           {524288000/524288000}
# x-ms-copy-completion-time    {Mon, 03 Apr 2023 12:30:37 GMT}
# x-ms-access-tier             {Archive}
# x-ms-access-tier-change-time {Mon, 03 Apr 2023 12:30:37 GMT}
# x-ms-archive-status          {rehydrate-pending-to-hot}
# x-ms-rehydrate-priority      {High}
# Date                         {Mon, 03 Apr 2023 13:21:16 GMT}
# Content-Length               {524288000}
# Content-Type                 {application/octet-stream}
# Last-Modified                {Mon, 03 Apr 2023 12:30:37 GMT}
# 
$statusResponse.Headers["x-ms-copy-status"]
$statusResponse.Headers["x-ms-copy-progress"]
$statusResponse.Headers["x-ms-copy-status-description"]
$statusResponse.Headers["x-ms-archive-status"]
$statusResponse.Headers["x-ms-rehydrate-priority"]

# Follow-up on the copy status
$statusResponse2 = Invoke-WebRequest `
    -Method "HEAD" `
    -Headers @{ 
    "x-ms-version" = "2022-11-02"
} `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net/block-blobs/demo-hot.bin"

$statusResponse2.Headers

# Key                          Value
# ---                          -----
# x-ms-blob-type               {BlockBlob}
# x-ms-copy-id                 {7a01027d-74b7-4cfd-8c12-9ccf78ccd209}
# x-ms-copy-source             {https://<storage>.blob.core.windows.net/block-blobs/demo.bin}
# x-ms-copy-status             {success}
# x-ms-copy-status-description {success}
# x-ms-copy-progress           {524288000/524288000}
# x-ms-copy-completion-time    {Mon, 03 Apr 2023 12:30:37 GMT}
# x-ms-access-tier             {Hot}
# x-ms-access-tier-change-time {Mon, 03 Apr 2023 12:30:37 GMT}
# Date                         {Mon, 03 Apr 2023 13:24:08 GMT}
# Content-Length               {524288000}
# Content-Type                 {application/octet-stream}
# Last-Modified                {Mon, 03 Apr 2023 12:30:37 GMT}

$statusResponse2.Headers["x-ms-copy-status"]
$statusResponse2.Headers["x-ms-copy-progress"]
$statusResponse2.Headers["x-ms-copy-status-description"]
$statusResponse2.Headers["x-ms-archive-status"]
$statusResponse2.Headers["x-ms-rehydrate-priority"]
