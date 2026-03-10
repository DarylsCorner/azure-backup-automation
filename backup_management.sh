#!/bin/bash
# Backup Management Script for SAP VMs
# Usage: backup_management.sh <resource_group> <vault_name> <vault_rg> <policy_name> <subscription_id>

set -euo pipefail

RESOURCE_GROUP="$1"
VAULT_NAME="$2"
VAULT_RG="$3"
POLICY_NAME="$4"
SUBSCRIPTION_ID="$5"

if [ -z "$RESOURCE_GROUP" ] || [ -z "$VAULT_NAME" ] || [ -z "$VAULT_RG" ] || \
   [ -z "$POLICY_NAME" ]  || [ -z "$SUBSCRIPTION_ID" ]; then
  echo "Usage: $0 <resource_group> <vault_name> <vault_rg> <policy_name> <subscription_id>"
  exit 1
fi

# Verify required tools are present
for cmd in az jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Required tool '$cmd' is not installed or not in PATH."
    exit 1
  fi
done

echo "===== VM Backup Management Script ====="
echo "Resource Group : $RESOURCE_GROUP"
echo "Vault Name     : $VAULT_NAME"
echo "Vault RG       : $VAULT_RG"
echo "Policy Name    : $POLICY_NAME"
echo "Subscription   : $SUBSCRIPTION_ID"
echo "======================================="

# Set subscription context
az account set --subscription "$SUBSCRIPTION_ID"

echo ""
echo "Getting VMs in resource group: $RESOURCE_GROUP ..."

vm_ids=$(az vm list --resource-group "$RESOURCE_GROUP" --query "[].id" -o tsv)

if [ -z "$vm_ids" ]; then
  echo "No VMs found in resource group '$RESOURCE_GROUP'. Exiting."
  exit 0
fi

VM_COUNT=$(echo "$vm_ids" | wc -l | tr -d ' ')
echo "Found $VM_COUNT VM(s)"
echo ""

while IFS= read -r vm_id; do
  vm_name=$(basename "$vm_id")
  echo "Processing VM: $vm_name"

  # Check if VM is already protected
  vm_id_lower=$(echo "$vm_id" | tr '[:upper:]' '[:lower:]')

  backup_item=$(az backup item list \
    --resource-group "$VAULT_RG" \
    --vault-name "$VAULT_NAME" \
    --backup-management-type AzureIaasVM \
    --workload-type VM \
    -o json 2>/dev/null | jq -r --arg vmid "$vm_id_lower" \
      '.[] | select(
         (.properties.sourceResourceId | ascii_downcase) == $vmid or
         (.properties.virtualMachineId  | ascii_downcase) == $vmid
       ) | .name' | head -n 1)

  if [ -n "$backup_item" ]; then
    echo "  [SKIP] Already protected (item: $backup_item)"
    echo ""
    continue
  fi

  # Detect shared disks and collect LUNs to exclude
  disk_ids=$(az vm show --ids "$vm_id" \
    --query "storageProfile.dataDisks[].managedDisk.id" -o tsv 2>/dev/null)

  shared_disk_luns=()
  has_shared_disks=false

  for disk_id in $disk_ids; do
    if [ -n "$disk_id" ]; then
      max_shares=$(az disk show --ids "$disk_id" --query "maxShares" -o tsv 2>/dev/null)

      if [ -n "$max_shares" ] && [ "$max_shares" -gt 1 ]; then
        has_shared_disks=true
        lun=$(az vm show --ids "$vm_id" \
          --query "storageProfile.dataDisks[?managedDisk.id=='$disk_id'].lun" -o tsv 2>/dev/null)
        if [ -n "$lun" ]; then
          shared_disk_luns+=("$lun")
          echo "  Found shared disk at LUN $lun (maxShares: $max_shares)"
        fi
      fi
    fi
  done

  if [ "$has_shared_disks" = true ]; then
    echo "  VM has shared disks — enabling backup with LUN exclusion..."

    exclude_disks=""
    for lun in "${shared_disk_luns[@]}"; do
      exclude_disks="${exclude_disks:+$exclude_disks }$lun"
    done

    # Word-split on $exclude_disks is intentional: --diskslist expects space-separated LUN integers
    # shellcheck disable=SC2086
    if az backup protection enable-for-vm \
        --vm "$vm_id" \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --policy-name "$POLICY_NAME" \
        --disk-list-setting exclude \
        --diskslist $exclude_disks; then
      echo "  [OK] Backup enabled (excluded LUNs: $exclude_disks)"
    else
      echo "  [FAIL] Could not enable backup for $vm_name"
    fi
  else
    echo "  No shared disks — enabling standard backup..."

    if az backup protection enable-for-vm \
        --vm "$vm_id" \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --policy-name "$POLICY_NAME"; then
      echo "  [OK] Backup enabled"
    else
      echo "  [FAIL] Could not enable backup for $vm_name"
    fi
  fi

  echo ""
done <<< "$vm_ids"

echo "Backup configuration completed for all VMs in resource group: $RESOURCE_GROUP"
