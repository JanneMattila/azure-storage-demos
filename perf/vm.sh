# Enable auto export
set -a

# All the variables for the deployment
subscription_name="development"
resource_group_name="rg-storage"
location="westeurope"

vnet_name="vnet-vm"
subnet_vm_name="snet-vm"

storage_name="sftp00000000011"

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

# Echo important variables
echo -e "Environment vars->" \
     \\nvm_username=\"$vm_username\" \
     \\nvm_password=\"$vm_password\" \
     \\nvm_public_ip_address=\"$vm_public_ip_address\" \
     \\nstorage_sftp_username=\"$storage_sftp_username\" \
     \\nstorage_sftp_password=\"$storage_sftp_password\" \
     \\n"<-Environment vars"

ssh $vm_username@$vm_public_ip_address

# Or using sshpass
sshpass -p $vm_password ssh $vm_username@$vm_public_ip_address

# If you want to use screen for running commands
screen

########################################
#     _          ____
#    / \    ____/ ___|___  _ __  _   _
#   / _ \  |_  / |   / _ \| '_ \| | | |
#  / ___ \  / /| |__| (_) | |_) | |_| |
# /_/   \_\/___|\____\___/| .__/ \__, |
#                         |_|    |___/
########################################
#region AzCopy

# Install AzCopy
wget "https://aka.ms/downloadazcopy-v10-linux"
mkdir -p azcopy
tar -xf downloadazcopy-v10-linux --strip-components=1 --directory azcopy
cd azcopy
./azcopy --help
./azcopy sync --help
./azcopy copy --help

transfer_rate_mbs=0
storage_source="<storage_path>/<storage_sas>"
storage_target="<storage_path>/<storage_sas>"
export AZCOPY_JOB_PLAN_LOCATION=/mnt/logs

# Allow using of temp drive for these logs
sudo mkdir -p /mnt/logs
sudo chmod 777 /mnt/logs

# Additional parameters to check:
# --include-after '2020-08-19'
echo "Started: $(date)" >> log.txt
./azcopy copy \
  $storage_source \
  $storage_target \
  --cap-mbps $transfer_rate_mbs \
  --log-level WARNING \
  --output-level default \
  --overwrite ifSourceNewer \
  --recursive
echo "Ended: $(date)" >> log.txt

cat log.txt

##################################################
#     __     _           ____
#    / /    / \    ____ / ___| ___   _ __   _   _
#   / /    / _ \  |_  /| |    / _ \ | '_ \ | | | |
#  / /    / ___ \  / / | |___| (_) || |_) || |_| |
# /_/    /_/   \_\/___| \____|\___/ | .__/  \__, |
#                                   |_|     |___/
##################################################
#endregion

##################
#   __  _
#  / _|(_)  ___
# | |_ | | / _ \
# |  _|| || (_) |
# |_|  |_| \___/
##################
#region fio

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

#########################
#     __   __  _
#    / /  / _|(_)  ___
#   / /  | |_ | | / _ \
#  / /   |  _|| || (_) |
# /_/    |_|  |_| \___/
#########################

# Exit VM
exit

#endregion

#########################
#        __  _
#  ___  / _|| |_  _ __
# / __|| |_ | __|| '_ \
# \__ \|  _|| |_ | |_) |
# |___/|_|   \__|| .__/
#                |_|
#########################

# Storage options:
# ----------------
# sku="Premium_LRS"
# kind="BlockBlobStorage"
# Or
sku="Standard_LRS"
kind="StorageV2"

storage_id=$(az storage account create \
  --name $storage_name \
  --resource-group $resource_group_name \
  --location $location \
  --sku $sku \
  --kind $kind \
  --enable-hierarchical-namespace true \
  --enable-sftp true \
  --query id -o tsv)

az storage container create \
  --account-name $storage_name \
  --name sftp \
  --auth-mode login

storage_sftp_username=$storage_name.$vm_username@$storage_name.blob.core.windows.net

# Copy vars to VM
echo -e "Environment vars->" \
     \\nvm_username=\"$vm_username\" \
     \\nvm_password=\"$vm_password\" \
     \\nvm_public_ip_address=\"$vm_public_ip_address\" \
     \\nstorage_sftp_username=\"$storage_sftp_username\" \
     \\nstorage_sftp_password=\"$storage_sftp_password\" \
     \\n"<-Environment vars"

# Go to VM
sshpass -p $vm_password ssh $vm_username@$vm_public_ip_address

# Set variables

# https://learn.microsoft.com/en-us/azure/virtual-machines/linux/create-ssh-keys-detailed#generate-keys-with-ssh-keygen
ssh-keygen \
    -m PEM \
    -t rsa \
    -b 4096 \
    -C $storage_sftp_username \
    -f ~/.ssh/$vm_username \
    -N $vm_password

cat ~/.ssh/$vm_username.pub

# Exit VM
exit

# Copy public key to local machine
sshpass -p $vm_password scp $vm_username@$vm_public_ip_address:.ssh/$vm_username.pub .
ll $vm_username.pub

az storage account local-user create \
  --resource-group $resource_group_name \
  --account-name $storage_name \
  --name $vm_username \
  --home-directory sftp \
  --ssh-authorized-key key="$(cat $vm_username.pub)" \
  --has-ssh-key true \
  --has-ssh-password true \
  --permission-scope permissions=rwdlc service=blob resource-name=sftp

storage_sftp_password=$(az storage account local-user regenerate-password \
  --resource-group $resource_group_name \
  --account-name $storage_name \
  --name $vm_username \
  --query sshPassword -o tsv)
echo $storage_sftp_password

# Go to VM
sshpass -p $vm_password ssh $vm_username@$vm_public_ip_address

# Host verification check prompt
ssh $storage_sftp_username

ll ~/.ssh
eval "$(ssh-agent -s)"

echo $vm_password
ssh-add ~/.ssh/$vm_username

# Allow using of temp drive for these files
sudo mkdir -p /mnt/sftp
sudo chmod 777 /mnt/sftp

rm -rf /mnt/sftp/*
find /mnt/sftp/ -type f -delete

generation_time=$(date +%s)
generation_count=320
for ((i=1; i<=$generation_count; i++))
do
  # Generate fix sizes
  # file_size=5000
  # truncate -s ${file_size}m /mnt/sftp/file_${generation_time}_${i}_${file_size}.bin

  # Generate large files with sizes ~50-200 MB
  # file_size=$(($RANDOM % 151 + 50 ))
  # truncate -s ${file_size}m /mnt/sftp/file_${generation_time}_${i}_${file_size}.bin

  # Generate Office document type of payloads with sizes ~1-50 MB
  # file_size=$(($RANDOM % 50 + 1 ))
  # truncate -s ${file_size}m /mnt/sftp/file_${generation_time}_${i}_${file_size}.bin

  # Generate files with sizes ~29-31 MB
  file_size=$(($RANDOM % 3 + 29 ))
  truncate -s ${file_size}m /mnt/sftp/file_${generation_time}_${i}_${file_size}.bin

  # Generate tiny log type payloads with sizes ~30-60 kB
  # file_size=$(($RANDOM % 31 + 30 ))
  # truncate -s ${file_size}k /mnt/sftp/file_${generation_time}_${i}_${file_size}.bin

  # Generate tiny log type payloads with sizes ~1-5 kB
  # file_size=$(($RANDOM % 5 + 1 ))
  # truncate -s ${file_size}k /mnt/sftp/file_${generation_time}_${i}_${file_size}.bin
done

ll /mnt/sftp
ls -lhsR /mnt/sftp
du -h --apparent-size /mnt/sftp
find /mnt/sftp -type f | wc -l

output_path=$(uuidgen)
cat <<EOF > batch_commands.batch
mkdir $output_path
cd $output_path
put -r /mnt/sftp/*
EOF

cat batch_commands.batch

# With 32 requests and buffer size of 262000
date
time sftp -B 262000 -R 32 -b batch_commands.batch $storage_sftp_username

# With compression
time sftp -B 262000 -R 32 -C -b batch_commands.batch $storage_sftp_username

sftp -B 262000 -R 32 $storage_sftp_username

# Example estimation calculator
bandwidth=30 # MB/s
data_size=135*1024 # MB
echo "$((data_size / bandwidth / 60)) minutes"

#############################
#     __      __  _
#    / /___  / _|| |_  _ __
#   / // __|| |_ | __|| '_ \
#  / / \__ \|  _|| |_ | |_) |
# /_/  |___/|_|   \__|| .__/
#                     |_|
#############################

# Exit VM
exit

# Wipe out the resources
az group delete --name $resource_group_name -y
