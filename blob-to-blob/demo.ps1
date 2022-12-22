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

# Clean up
Remove-AzResourceGroup -Name $resourceGroupName -Force
