$resourceGroupName = "rg-storage-demos"
$storageSourceName = "storagesource0000000010"
$storageTargetName = "storagetarget0000000010"
$location = "northeurope"
$sku = "Standard_LRS"
$kind = "StorageV2"

$resourceGroup = New-AzResourceGroup -Name $resourceGroupName -Location $location

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

$storageSource = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageSourceName
$storageTarget = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageTargetName

$contextSource = $storageSource.Context
$contextTarget = $storageTarget.Context

$contextSource
$contextTarget

$storageContainerSource = New-AzStorageContainer -Name $containerName -Context $contextSource
$storageContainerTarget = New-AzStorageContainer -Name $containerName -Context $contextTarget

$containerName = "files"
Set-Content -Path "file.txt" -Value "hello world"
Set-AzStorageBlobContent -Context $contextSource -Container $containerName -Blob "file.txt" -File "file.txt"

# Clean up
Remove-AzResourceGroup -Name $resourceGroupName -Force
