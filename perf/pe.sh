# If you need to create private endpoint for storage account,
# then follow these steps:

# Follow instructions from here:
# https://docs.microsoft.com/en-us/azure/storage/files/storage-files-networking-endpoints?tabs=azure-cli
# Disable private endpoint network policies
#
az network vnet subnet update \
  --ids $subnet_pe_id \
  --disable-private-endpoint-network-policies \
  --output none

# Create private endpoint to "snet-pe"
storage_pe_id=$(az network private-endpoint create \
  --name storage-pe \
  --resource-group $resource_group_name \
  --vnet-name $vnet_name --subnet $subnet_pe_name \
  --private-connection-resource-id $storage_id \
  --group-id file \
  --connection-name storage-connection \
  --query id -o tsv)
echo $storage_pe_id

# Create Private DNS Zone
blob_private_dns_zone_id=$(az network private-dns zone create \
  --resource-group $resource_group_name \
  --name "privatelink.blob.core.windows.net" \
  --query id -o tsv)
echo $blob_private_dns_zone_id

# Link Private DNS Zone to VNET
az network private-dns link vnet create \
  --resource-group $resource_group_name \
  --zone-name "privatelink.blob.core.windows.net" \
  --name blob-dnszone-link \
  --virtual-network $vnet_name \
  --registration-enabled false

# Get private endpoint nic
storage_pe_nic_id=$(az network private-endpoint show \
  --ids $storage_pe_id \
  --query "networkInterfaces[0].id" -o tsv)
echo $storage_pe_nic_id

# Get ip of private endpoint nic
storage_pe_ip=$(az network nic show \
  --ids $storage_pe_nic_id \
  --query "ipConfigurations[0].privateIpAddress" -o tsv)
echo $storage_pe_ip

# Map private endpoint ip to A record in Private DNS Zone
az network private-dns record-set a create \
  --resource-group $resource_group_name \
  --zone-name "privatelink.blob.core.windows.net" \
  --name $storage_name \
  --output none

az network private-dns record-set a add-record \
  --resource-group $resource_group_name \
  --zone-name "privatelink.blob.core.windows.net" \
  --record-set-name $storage_name \
  --ipv4-address $storage_pe_ip \
  --output none
