# Enable auto export
set -a

# All the variables for the deployment
subscription_name="development"
resource_group_name="rg-storage"
location="westeurope"

vnet_name="vnet-vm"
subnet_vm_name="snet-vm"

vm_name="vm"
vm_username="azureuser"

if test -f ".env"; then
  # Password has been created so load it
  source .env
else
  # Generate password and store it
  vm_password=$(openssl rand -base64 32)
  echo "vm_password=$vm_password" > .env
fi

nsg_name="nsg-vm"
nsg_rule_ssh_name="ssh-rule"
nsg_rule_myip_name="myip-rule"

# Login and set correct context
az login -o table
az account set --subscription $subscription_name -o table

# Create resource group
az group create -l $location -n $resource_group_name -o table

az network nsg create \
  --resource-group $resource_group_name \
  --name $nsg_name

my_ip=$(curl --no-progress-meter https://api.ipify.org)
echo $my_ip

az network nsg rule create \
  --resource-group $resource_group_name \
  --nsg-name $nsg_name \
  --name $nsg_rule_ssh_name \
  --protocol '*' \
  --direction inbound \
  --source-address-prefix $my_ip \
  --source-port-range '*' \
  --destination-address-prefix '*' \
  --destination-port-range '22' \
  --access allow \
  --priority 100

az network nsg rule create \
  --resource-group $resource_group_name \
  --nsg-name $nsg_name \
  --name $nsg_rule_myip_name \
  --protocol '*' \
  --direction outbound \
  --source-address-prefix '*' \
  --source-port-range '*' \
  --destination-address-prefix $my_ip \
  --destination-port-range '*' \
  --access allow \
  --priority 100

vnet_id=$(az network vnet create -g $resource_group_name --name $vnet_name \
  --address-prefix 10.0.0.0/8 \
  --query newVNet.id -o tsv)
echo $vnet_id

subnet_vm_id=$(az network vnet subnet create -g $resource_group_name --vnet-name $vnet_name \
  --name $subnet_vm_name --address-prefixes 10.4.0.0/24 \
  --network-security-group $nsg_name \
  --query id -o tsv)
echo $subnet_vm_id

vm_json=$(az vm create \
  --resource-group $resource_group_name  \
  --name $vm_name \
  --image UbuntuLTS \
  --size Standard_D8ds_v4 \
  --admin-username $vm_username \
  --admin-password $vm_password \
  --subnet $subnet_vm_id \
  --accelerated-networking true \
  --nsg "" \
  --public-ip-sku Standard \
  -o json)

vm_public_ip_address=$(echo $vm_json | jq -r .publicIpAddress)
echo $vm_public_ip_address

# Display variables
echo vm_username=$vm_username
echo vm_password=$vm_password
echo vm_public_ip_address=$vm_public_ip_address

ssh $vm_username@$vm_public_ip_address

# Or using sshpass
sshpass -p $vm_password ssh $vm_username@$vm_public_ip_address

# Install AzCopy
wget "https://aka.ms/downloadazcopy-v10-linux" -o azcopy.tar

truncate -s 10m demo1.bin
time curl -T demo1.bin -X POST "http://$ingress_ip/api/upload"

# Install fio
sudo apt-get install fio
cd /home
mkdir perf-test

# Write test with 4 x 4MBs for 20 seconds
fio --directory=perf-test --direct=1 --rw=randwrite --bs=4k --ioengine=libaio --iodepth=256 --runtime=20 --numjobs=4 --time_based --group_reporting --size=4m --name=iops-test-job --eta-newline=1

# Read test with 4 x 4MBs for 20 seconds
fio --directory=perf-test --direct=1 --rw=randread --bs=4k --ioengine=libaio --iodepth=256 --runtime=20 --numjobs=4 --time_based --group_reporting --size=4m --name=iops-test-job --eta-newline=1 --readonly

fio --name=random-write --ioengine=posixaio --rw=randwrite --bs=4k --numjobs=1 --size=4g --iodepth=1 --runtime=60 --time_based --end_fsync=1

# Find test files
ls perf-test/*.0

# Remove test files
rm perf-test/*.0

# Exit VM
exit

# Wipe out the resources
az group delete --name $resource_group_name -y
