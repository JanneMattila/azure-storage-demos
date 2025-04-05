$storage = "<your storage account name>"
$container = "container"

Login-AzAccount

# Note: Least privileged built-in role: Storage Blob Data Owner
$accessToken = Get-AzAccessToken -ResourceUrl "https://$storage.blob.core.windows.net/"
$secureAccessToken = ConvertTo-SecureString -AsPlainText -String $accessToken.Token

# Find blobs with tags
# https://learn.microsoft.com/en-us/rest/api/storageservices/get-blob-tags?tabs=azure-ad#request-headers
$query = [System.Uri]::EscapeDataString("@container='$container' AND `"Example header`" = 'Example value'")

$response = Invoke-WebRequest `
    -Method "GET" `
    -Headers @{ 
    "x-ms-version"     = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net`?comp=blobs&where=$query"

$response
$response.Content
$xml = [xml]$response.Content.Substring($response.Content.IndexOf(">") + 1)
$xml.EnumerationResults.Blobs.Blob | ForEach-Object {
    $_.Name
}

$xml.EnumerationResults.Blobs.Blob[0]
$xml.EnumerationResults.Blobs.Blob[0].Tags.TagSet.Tag
$file = $xml.EnumerationResults.Blobs.Blob[0].Name

# ---

# Remove tags from blob
# https://learn.microsoft.com/en-us/rest/api/storageservices/set-blob-tags?tabs=azure-ad#request-headers

$response = Invoke-WebRequest `
    -Method "PUT" `
    -Headers @{ 
    "x-ms-version"     = "2025-05-05"
} `
    -Authentication Bearer `
    -Token $secureAccessToken `
    -Uri "https://$storage.blob.core.windows.net/$container/$file`?comp=tags" `
    -Body "<Tags><TagSet></TagSet></Tags>"
$response
$response.StatusCode
