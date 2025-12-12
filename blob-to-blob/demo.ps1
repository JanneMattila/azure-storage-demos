$resourceGroupName = "rg-storage-demos"
$storageSourceName = "storagesource0000000011"
$storageTargetName = "storagetarget0000000011"
$location = "westeurope"
$sku = "Standard_LRS"
$kind = "StorageV2"
$containerName = "files"

$resourceGroup = New-AzResourceGroup -Name $resourceGroupName -Location $location -Force

$storageSource = New-AzStorageAccount `
    -ResourceGroupName $resourceGroupName `
    -Name $storageSourceName `
    -SkuName $sku `
    -Location $location `
    -Kind $kind `
    -AllowSharedKeyAccess $true

$storageSource

$storageTarget = New-AzStorageAccount `
    -ResourceGroupName $resourceGroupName `
    -Name $storageTargetName `
    -SkuName $sku `
    -Location $location `
    -Kind $kind `
    -AllowSharedKeyAccess $true

$storageTarget

$keySource = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageSourceName
$keyTarget = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageTargetName
$key1Source = $keySource[0].Value
$key1Target = $keyTarget[0].Value

$storageSource = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageSourceName
$storageTarget = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageTargetName

$contextSource = $storageSource.Context
$contextTarget = $storageTarget.Context

$contextSource
$contextTarget

$sasSource = New-AzStorageAccountSASToken -Context $contextSource -Service Blob -ResourceType Service, Container, Object -Permission "rwdlacupiytfx" -ExpiryTime ([DateTime]::UtcNow).AddYears(1)
$sasTarget = New-AzStorageAccountSASToken -Context $contextTarget -Service Blob -ResourceType Service, Container, Object -Permission "rwdlacupiytfx" -ExpiryTime ([DateTime]::UtcNow).AddYears(1)

# Create if not existing
$storageContainerSource = New-AzStorageContainer -Name $containerName -Context $contextSource
$storageContainerTarget = New-AzStorageContainer -Name $containerName -Context $contextTarget

# Or get existing
$storageContainerSource = Get-AzStorageContainer -Name $containerName -Context $contextSource
$storageContainerTarget = Get-AzStorageContainer -Name $containerName -Context $contextTarget

Set-Content -Path "file.txt" -Value "hello world"
Set-AzStorageBlobContent -Context $contextSource -Container $containerName -Blob "file.txt" -File "file.txt"

###########################
#  ____
# / ___| _   _ _ __   ___
# \___ \| | | | '_ \ / __|
#  ___) | |_| | | | | (__
# |____/ \__, |_| |_|\___|
#        |___/
###########################

azcopy --help
azcopy sync --help
azcopy copy --help

$uriSource = $storageContainerSource.CloudBlobContainer.Uri.AbsoluteUri
$uriTarget = $storageContainerTarget.CloudBlobContainer.Uri.AbsoluteUri

azcopy sync `
($uriSource + $sasSource) `
($uriTarget + $sasTarget) `
    --recursive `
    --dry-run

azcopy sync `
($uriSource + "/" + $sasSource) `
($uriTarget + "/" + $sasTarget) `
    --recursive

azcopy copy `
($uriSource + "/" + $sasSource) `
($uriTarget + "/" + $sasTarget) `
    --overwrite ifSourceNewer `
    --recursive


## Using Rest API
$storage1 = "<your storage account name>"
$storage2 = "<your storage account name>"
$container = "container1"
$path = "directory"
$filename = "file.txt"

$accessToken1 = Get-AzAccessToken -ResourceUrl "https://$storage1.blob.core.windows.net/"
$accessToken2 = Get-AzAccessToken -ResourceUrl "https://$storage2.blob.core.windows.net/"

## Put Blob From URL
# https://learn.microsoft.com/en-us/rest/api/storageservices/put-blob-from-url?tabs=microsoft-entra-id
Invoke-RestMethod `
    -Method "PUT" `
    -Headers @{ 
    "x-ms-version"     = "2025-11-05"
    "x-ms-blob-type"   = "BlockBlob"
    "x-ms-copy-source" = "https://$storage1.blob.core.windows.net/$container/$path/$filename"
    "x-ms-copy-source-authorization" = "Bearer $($accessToken1.Token | ConvertFrom-SecureString -AsPlainText)"
} `
    -Authentication Bearer `
    -Token $accessToken2.Token `
    -Uri "https://$storage2.blob.core.windows.net/$container/$path/$filename"

# Clean up
Remove-AzResourceGroup -Name $resourceGroupName -Force
