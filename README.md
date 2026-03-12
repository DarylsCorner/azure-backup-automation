# Azure VM Backup Automation for SDAF

[![Azure](https://img.shields.io/badge/Azure-0078D4?style=flat&logo=microsoftazure&logoColor=white)](https://azure.microsoft.com)
[![SAP](https://img.shields.io/badge/SAP-0FAAFF?style=flat&logo=sap&logoColor=white)](https://www.sap.com)
[![Shell Script](https://img.shields.io/badge/Shell_Script-121011?style=flat&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat&logo=ansible&logoColor=white)](https://www.ansible.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

> **Automated Azure Backup protection for SAP VM workloads deployed via the SAP Deployment Automation Framework (SDAF)**

---

## Overview

This project enables **Azure Backup** for all VMs in an SAP system resource group
deployed via SDAF. It integrates directly into the SDAF configuration menu so the
backup runbook can be run alongside all other post-deployment configuration
playbooks (OS configuration, SAP installation, ODCR, etc.).

Key capabilities:

- Scoped to the **SAP system resource group** — only VMs for the deployed SID are
  affected, not the entire subscription.
- Detects **shared managed disks** (used for ASCS/ERS quorum or HANA shared
  storage) and automatically **excludes those LUNs** from the backup policy, which
  is required for Azure Backup compatibility.
- Idempotent — already-protected VMs are detected and skipped without error.

---

## Features

- **Enable Mode**: Iterates every VM in the resource group, detects shared disks,
  and enrolls each VM in the specified Recovery Services vault / policy.
- **Skip Logic**: VMs that are already protected are reported and skipped.
- **Shared-Disk Awareness**: Queries each data-disk's `maxShares` property and
  excludes LUNs where `maxShares > 1`.

---

## Prerequisites

- Azure CLI installed and configured
- Azure RBAC permissions:
  - `Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems/write`
  - `Microsoft.Compute/virtualMachines/read`
  - `Microsoft.Compute/disks/read`
- SAP system deployed via SDAF with `sap-parameters.yaml`
- Ansible 2.11+
- Recovery Services vault and backup policy already created in Azure

---

## Usage

There are multiple ways to run this playbook depending on your workflow and how
you want to manage variables. Choose the approach that best fits your environment.

### 1. Run Ansible Directly with Extra-Vars

Run the playbook directly using `ansible-playbook` and pass all backup-related
variables at the command line:

```bash
cd ~/Azure_SAP_Automated_Deployment/WORKSPACES/SYSTEM/<SID>/

ansible-playbook \
  ~/Azure_SAP_Automated_Deployment/sap-automation/deploy/ansible/playbook_08_00_01_vm_backup.yaml \
  -i sap-parameters.yaml \
  -e "_workspace_directory=$(pwd)" \
  -e "backup_vault_name=rsv-sap-backup-prod backup_vault_rg=rg-backup-services backup_policy_name=Enhanced-Backup-Policy"
```

> **Note**: No `--private-key` is required since this playbook runs on `localhost`.

### 2. Run via Configuration Menu with Extra-Vars at Runtime

Use the SDAF configuration menu and pass the backup variables as extra-vars:

```bash
cd ~/Azure_SAP_Automated_Deployment/WORKSPACES/SYSTEM/<SID>/

~/Azure_SAP_Automated_Deployment/sap-automation/deploy/ansible/configuration_menu.sh \
  --extra-vars="backup_vault_name=rsv-sap-backup-prod backup_vault_rg=rg-backup-services backup_policy_name=Enhanced-Backup-Policy"
```

Then select **"VM Backup Protection"** from the menu.

### 3. Add Variables to sap-parameters.yaml

Add the backup variables directly to your SID's `sap-parameters.yaml` file so the
configuration menu picks them up automatically:

```yaml
# Add these lines to sap-parameters.yaml
backup_vault_name:   "rsv-sap-backup-prod"
backup_vault_rg:     "rg-backup-services"
backup_policy_name:  "Enhanced-Backup-Policy"
```

Then run the configuration menu without extra-vars:

```bash
cd ~/Azure_SAP_Automated_Deployment/WORKSPACES/SYSTEM/<SID>/
~/Azure_SAP_Automated_Deployment/sap-automation/deploy/ansible/configuration_menu.sh
# Select "VM Backup Protection"
```

### 4. Edit sap-parameters.tmpl Template with Variables Commented (Recommended)

For a reusable approach, add the backup variables to the SDAF template file
`sap-parameters.tmpl` with comments. This makes the variables visible in every
newly deployed SID's `sap-parameters.yaml`, ready to enable when needed:

**File**: `~/Azure_SAP_Automated_Deployment/sap-automation/deploy/terraform/terraform-units/modules/sap_system/output_files/sap-parameters.tmpl`

```yaml
# ==========================================
# VM Backup Protection Configuration
# ==========================================
# Uncomment and populate the following variables to enable
# Azure Backup integration via the configuration menu.
#
# backup_vault_name:   "rsv-sap-backup-prod"
# backup_vault_rg:     "rg-backup-services"
# backup_policy_name:  "Enhanced-Backup-Policy"
```

When you're ready to enable backup for a specific SID, edit that SID's
`sap-parameters.yaml` and remove the `#` prefix:

```yaml
# ==========================================
# VM Backup Protection Configuration
# ==========================================
# Uncomment and populate the following variables to enable
# Azure Backup integration via the configuration menu.
#
backup_vault_name:   "rsv-sap-backup-prod"
backup_vault_rg:     "rg-backup-services"
backup_policy_name:  "Enhanced-Backup-Policy"
```

Then run via the configuration menu:

```bash
cd ~/Azure_SAP_Automated_Deployment/WORKSPACES/SYSTEM/<SID>/
~/Azure_SAP_Automated_Deployment/sap-automation/deploy/ansible/configuration_menu.sh
# Select "VM Backup Protection"
```

---

## Configuration

Variables auto-derived from the inventory file (via `ANSIBLE_INVENTORY` environment variable):

| Variable | Source | Description |
|---|---|---|
| `resource_group_name` | Inventory file (e.g., `sap-parameters.yaml`) | SAP VM resource group (the deployed SID's RG) |
| `subscription_id` | Inventory file (e.g., `sap-parameters.yaml`) | Azure subscription ID |

> **Note**: This follows the same pattern as the ODCR playbook — when you pass `-i <inventory-file>`, the playbook automatically extracts `subscription_id` and `resource_group_name` from that file. No need to hardcode values or pass them as extra-vars.

Required extra-vars:

| Variable | Required | Description |
|---|---|---|
| `backup_vault_name` | Yes | Name of the Recovery Services vault |
| `backup_vault_rg` | Yes | Resource group containing the vault |
| `backup_policy_name` | Yes | Backup policy to assign to the VMs |
| `backup_action` | No | `enable` (default) |

---

## Integration with SDAF Configuration Menu

### Step 1: Copy Files to SDAF Directory

```bash
# Copy playbook
cp playbook_08_00_01_vm_backup.yaml \
  ~/Azure_SAP_Automated_Deployment/sap-automation/deploy/ansible/

# Copy management script
cp backup_management.sh \
  ~/Azure_SAP_Automated_Deployment/sap-automation/deploy/scripts/

# Make script executable
chmod +x ~/Azure_SAP_Automated_Deployment/sap-automation/deploy/scripts/backup_management.sh
```

### Step 2: Edit configuration_menu.sh

**File**: `~/Azure_SAP_Automated_Deployment/sap-automation/deploy/ansible/configuration_menu.sh`

**Add menu display name to the `options` array** (around line 122):

```bash
options=(
        # ... existing entries ...
        "HCMT"
        "Capacity Reservations (ODCR)"
        "VM Backup Protection"          # Add this line

        # Special menu entries
        "BOM Download"
```

**Add playbook path to the `all_playbooks` array** (around line 153):

```bash
all_playbooks=(
        # ... existing playbooks ...
        ${cmd_dir}/playbook_04_00_02_db_hcmt.yaml
        ${cmd_dir}/playbook_08_00_00_capacity_reservations.yaml
        ${cmd_dir}/playbook_08_00_01_vm_backup.yaml    # Add this line
        ${cmd_dir}/playbook_bom_downloader.yaml
```

> **Important**: The position in both arrays must match — if "VM Backup Protection"
> is the 16th item in `options`, `playbook_08_00_01_vm_backup.yaml` must be the
> 16th item in `all_playbooks`.

### Step 3: Verify Integration

```bash
cd ~/Azure_SAP_Automated_Deployment/WORKSPACES/SYSTEM/<SID>/
~/Azure_SAP_Automated_Deployment/sap-automation/deploy/ansible/configuration_menu.sh
```

You should see the new "VM Backup Protection" option in the menu.

---

## Example Output

```
===== VM Backup Management Script =====
Resource Group : X00-WORKLOAD-RG
Vault Name     : rsv-sap-backup
Vault RG       : rg-backup-services
Policy Name    : Enhanced-Backup-Policy
Subscription   : xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
=======================================

Getting VMs in resource group: X00-WORKLOAD-RG ...
Found 5 VM(s)

Processing VM: x00scs01le2e
  No shared disks — enabling standard backup...
  [OK] Backup enabled

Processing VM: x00dhdb01l0e2e
  Found shared disk at LUN 2 (maxShares: 2)
  VM has shared disks — enabling backup with LUN exclusion...
  [OK] Backup enabled (excluded LUNs: 2)

Processing VM: x00app01le2e
  [SKIP] Already protected (item: AzureIaasVMIaasVMContainer;...)

Backup configuration completed for all VMs in resource group: X00-WORKLOAD-RG
```

---

## Best Practices

- **Timing**: Run after Terraform deployment and OS configuration, before or after
  SAP installation — the VMs must exist but SAP does not need to be running.
- **Vault placement**: Place the Recovery Services vault in a separate resource
  group from the SAP workload so backup data is not deleted if the workload RG is
  cleaned up.
- **Shared disks**: The script automatically excludes shared disks. Review the
  Azure Backup documentation if you need those disks crash-consistent as part of
  a separate backup policy.
- **Policy selection**: Use an Enhanced policy (not Classic) if your VMs use
  Trusted Launch or Premium SSDs — the `--policy-name` must reference an existing
  policy in the vault.
- **Idempotency**: Safe to re-run; already-protected VMs are skipped.

---

## Files

1. **`playbook_08_00_01_vm_backup.yaml`** — Ansible playbook wrapper
   - Reads RG and subscription from the inventory file (via `ANSIBLE_INVENTORY` env var)
   - Validates required extra-vars
   - Calls `backup_management.sh` with resolved parameters
   - Writes a `.progress/vm-backup-done` completion flag

2. **`backup_management.sh`** — Bash script with Azure CLI commands
   - Accepts: `<resource_group> <vault_name> <vault_rg> <policy_name> <subscription_id>`
   - Lists VMs scoped to the resource group (not the whole subscription)
   - Detects shared disks via `maxShares` property
   - Enables backup with LUN exclusion where required

---

## Verification

```bash
# List backup items in the vault
az backup item list \
  --resource-group <VAULT-RG> \
  --vault-name <VAULT-NAME> \
  --backup-management-type AzureIaasVM \
  --workload-type VM \
  --output table

# Check protection status for a specific VM
az backup item show \
  --resource-group <VAULT-RG> \
  --vault-name <VAULT-NAME> \
  --container-name "iaasvmcontainer;iaasvmcontainerv2;<VM-RG>;<VM-NAME>" \
  --name "vm;<VM-RG>;<VM-NAME>" \
  --backup-management-type AzureIaasVM \
  --workload-type VM \
  --query "properties.{Status:currentProtectionState, Policy:effectivePolicyId}" \
  --output table
```

---

## References

- [Azure Backup for VMs documentation](https://learn.microsoft.com/azure/backup/backup-azure-vms-introduction)
- [Azure Backup — exclude disks](https://learn.microsoft.com/azure/backup/selective-disk-backup-restore)
- [Azure SAP Deployment Automation Framework](https://github.com/Azure/sap-automation)
- [SDAF Deployment Framework docs](https://learn.microsoft.com/azure/sap/automation/deployment-framework)
- [ODCR Automation (inspiration)](https://github.com/DarylsCorner/azure-odcr-automation)

---

## Contributing

Contributions welcome — please submit a Pull Request.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

**Disclaimer**: This is not an official Microsoft product. Use at your own risk.
