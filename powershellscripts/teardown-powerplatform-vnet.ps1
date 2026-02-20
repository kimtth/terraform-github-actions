<#
.SYNOPSIS
    Removes Power Platform VNet integration enterprise policy (reverses setup-powerplatform-vnet.ps1).

.DESCRIPTION
    Reverses the three-step setup in the correct order:

    Step 1 – Unlink the enterprise policy from the Power Platform environment.
    Step 2 – Delete the enterprise policy ARM resource.
    Step 3 – Remove the subnet delegation registration from Power Platform.

    Run this before `terraform destroy` so Power Platform releases the subnet
    before Terraform attempts to delete the VNet/subnet resources.

.PREREQUISITES
    - Power Platform administrator role (Entra)
    - Network Contributor (or equivalent) on the Azure subscription
    - Microsoft.PowerPlatform.EnterprisePolicies module (auto-installed if missing)

.PARAMETER EnvironmentId
    The Power Platform environment ID (GUID) — same value used during setup.

.PARAMETER TenantId
    Azure AD tenant ID. Run: az account show --query tenantId
    Required to ensure Connect-AzAccount targets the correct tenant.

.PARAMETER SubscriptionId
    Azure subscription ID. Run: az account show --query id

.PARAMETER ResourceGroupName
    Azure resource group name. Defaults to the Terraform default.

.PARAMETER VirtualNetworkName
    Name of the primary VNet created by Terraform. Defaults to the Terraform default.

.PARAMETER SubnetName
    Name of the Power Platform delegated subnet in the primary VNet. Defaults to the Terraform default.

.PARAMETER SecondaryVirtualNetworkName
    Name of the secondary VNet. Defaults to the Terraform default.

.PARAMETER SecondarySubnetName
    Name of the Power Platform delegated subnet in the secondary VNet.

.PARAMETER PolicyName
    Name of the enterprise policy resource to delete. Defaults to the Terraform default.

.EXAMPLE
    .\teardown-powerplatform-vnet.ps1 `
        -EnvironmentId  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -TenantId       "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -SubscriptionId "zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory = $true)]
    [string] $EnvironmentId,

    [Parameter(Mandatory = $true)]
    [string] $TenantId,

    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,

    [string] $ResourceGroupName          = "azppf-rg",
    [string] $VirtualNetworkName         = "azppf-vnet",
    [string] $SubnetName                 = "azppf-ppf-subnet",
    [string] $SecondaryVirtualNetworkName = "azppf-vnet-secondary",
    [string] $SecondarySubnetName        = "azppf-ppf-subnet",
    [string] $PolicyName                 = "azppf-enterprise-policy"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Clear all cached Az contexts to prevent a previously cached account (e.g. a corporate
# account with access to many tenants) from being reused instead of the intended account.
# This forces an interactive login where the correct account can be selected.
if ($PSCmdlet.ShouldProcess("existing Az contexts", "Clear-AzContext")) {
    Clear-AzContext -Force | Out-Null
}
if ($PSCmdlet.ShouldProcess("tenant $TenantId", "Connect-AzAccount")) {
    Connect-AzAccount -TenantId $TenantId -Subscription $SubscriptionId | Out-Null
    Set-AzContext -TenantId $TenantId -Subscription $SubscriptionId | Out-Null
}

# ─── Step 0: Install / import the module ─────────────────────────────────────

# Workaround: Microsoft.PowerPlatform.EnterprisePolicies references $Global:InPesterExecution
# without initialising it. StrictMode -Version Latest treats this as a terminating error.
# Set the variable before import and temporarily relax StrictMode for the import call.
$Global:InPesterExecution = $false

if (-not (Get-Module -ListAvailable -Name "Microsoft.PowerPlatform.EnterprisePolicies")) {
    Write-Host "Installing Microsoft.PowerPlatform.EnterprisePolicies module..."
    Install-Module Microsoft.PowerPlatform.EnterprisePolicies -Scope CurrentUser -Force
}
Set-StrictMode -Off
Import-Module Microsoft.PowerPlatform.EnterprisePolicies
Set-StrictMode -Version Latest

$PolicyArmId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" +
               "/providers/Microsoft.PowerPlatform/enterprisePolicies/$PolicyName"

# ─── Step 1: Unlink the enterprise policy from the Power Platform environment ─

Write-Host "`n[1/3] Disabling subnet injection on environment '$EnvironmentId'..."
Write-Host "      Policy ARM ID: $PolicyArmId"

if ($PSCmdlet.ShouldProcess($EnvironmentId, "Disable-SubnetInjection")) {
    Disable-SubnetInjection `
        -EnvironmentId $EnvironmentId
}

# ─── Step 2: Delete the enterprise policy ARM resource ───────────────────────
# The policy must be unlinked from all environments before it can be deleted.

Write-Host "`n[2/3] Deleting enterprise policy '$PolicyName'..."
Write-Host "      Subscription  : $SubscriptionId"
Write-Host "      Resource group: $ResourceGroupName"

if ($PSCmdlet.ShouldProcess($PolicyArmId, "Remove-AzResource")) {
    Remove-AzResource `
        -ResourceId $PolicyArmId `
        -Force
}

# ─── Step 3: Remove the subnet delegation registrations from Power Platform ───
# This releases Power Platform's hold on both subnets so Terraform can delete the VNets.

Write-Host "`n[3/3] Removing subnet delegation registration (primary)..."
Write-Host "      VNet  : $VirtualNetworkName"
Write-Host "      Subnet: $SubnetName"

if ($PSCmdlet.ShouldProcess("$VirtualNetworkName/$SubnetName", "Remove-VnetForSubnetDelegation")) {
    $removeParams = @{
        SubscriptionId     = $SubscriptionId
        ResourceGroupName  = $ResourceGroupName
        VirtualNetworkName = $VirtualNetworkName
        SubnetName         = $SubnetName
    }
    Remove-VnetForSubnetDelegation @removeParams
}

Write-Host "`n[3b/3] Removing subnet delegation registration (secondary)..."
Write-Host "      VNet  : $SecondaryVirtualNetworkName"
Write-Host "      Subnet: $SecondarySubnetName"

if ($PSCmdlet.ShouldProcess("$SecondaryVirtualNetworkName/$SecondarySubnetName", "Remove-VnetForSubnetDelegation")) {
    $removeSecondaryParams = @{
        SubscriptionId     = $SubscriptionId
        ResourceGroupName  = $ResourceGroupName
        VirtualNetworkName = $SecondaryVirtualNetworkName
        SubnetName         = $SecondarySubnetName
    }
    Remove-VnetForSubnetDelegation @removeSecondaryParams
}

Write-Host "`nDone. Power Platform VNet integration has been removed." -ForegroundColor Yellow
Write-Host "You can now safely run: terraform destroy" -ForegroundColor Yellow
