$resourceGroupName = "rg-storage-demos"
$storageSourceName = "storagesource0000000010"
$storageTargetName = "storagetarget0000000010"
$location = "northeurope"
$sku = "Premium_LRS"
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

$storageSource = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageSource
$storageTarget = Get-AzStorageAccount -ResourceGroupName $resouresourceGroupNamerceGroup -Name $storageTargetName

$sourceContext = $storageSource.Context
$targetContext = $storageTarget.Context

$sourceContext
$targetContext
