# To generate demo file in bash:
# truncate -s 500m demo.bin
# head -c 500m </dev/urandom > demo2.bin

$storage = "<your storage account name>"
$tenantId = "<your tenant id>"

Login-AzAccount
Login-AzAccount -Tenant $tenantId

$accessToken = Get-AzAccessToken -ResourceUrl "https://$storage.blob.core.windows.net/"
$secureAccessToken = ConvertTo-SecureString -AsPlainText -String $accessToken.Token

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

