<#
.SYNOPSIS
    Configures Power Platform VNet integration enterprise policy after Terraform apply.

.DESCRIPTION
    Implements the three-step PowerShell setup from:
    https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure?pivots=powershell

    Step 1 – Register the existing delegated subnet with Power Platform.
    Step 2 – Create the enterprise policy in the resource group.
    Step 3 – Link the policy to the target Power Platform environment.

.PREREQUISITES
    - Power Platform administrator role (Entra)
    - Network Contributor (or equivalent) on the Azure subscription
    - The Power Platform environment must be a Managed Environment.
    - Terraform must have been applied successfully so the VNet/subnet exist.

.PARAMETER EnvironmentId
    The Power Platform environment ID (GUID).
    Find it in: Power Platform admin center > Environments > <env> > Settings > Details.

.PARAMETER TenantId
    Azure AD tenant ID. Run: az account show --query tenantId
    Required to ensure Connect-AzAccount targets the correct tenant.

.PARAMETER SubscriptionId
    Azure subscription ID. Run: az account show --query id

.PARAMETER ResourceGroupName
    Azure resource group name. Defaults to the Terraform default.

.PARAMETER VirtualNetworkName
    Name of the primary VNet (eastus) created by Terraform. Defaults to the Terraform default.

.PARAMETER SubnetName
    Name of the Power Platform delegated subnet in the primary VNet. Defaults to the Terraform default.

.PARAMETER SecondaryVirtualNetworkName
    Name of the secondary VNet (westus). Required for US geography (unitedstates).
    Defaults to the Terraform default. Set enable_secondary_vnet = true in tfvars first.

.PARAMETER SecondarySubnetName
    Name of the Power Platform delegated subnet in the secondary VNet.

.PARAMETER PolicyName
    Name to give the new enterprise policy resource.

.PARAMETER PolicyLocation
    Power Platform geography for the enterprise policy.
    This is a Power Platform-specific value — NOT an Azure region name.
    Find it in Power Platform admin center > Environments > <env> > Settings > Details > Region.
    Examples: "unitedstates", "japan", "europe", "australia"
    See: https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions

.EXAMPLE
    .\setup-powerplatform-vnet.ps1 `
        -EnvironmentId  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -TenantId       "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -SubscriptionId "zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz"
#>

[CmdletBinding(SupportsShouldProcess)]
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
    [string] $PolicyName                 = "azppf-enterprise-policy",

    [Parameter(Mandatory = $true)]
    [string] $PolicyLocation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Connect to the correct tenant so the module uses the right Azure context.
# Without -TenantId the module may pick up a cached context from a different tenant.
if ($PSCmdlet.ShouldProcess("tenant $TenantId", "Connect-AzAccount")) {
    Connect-AzAccount -TenantId $TenantId -Subscription $SubscriptionId | Out-Null
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

# ─── Step 1: Register the existing delegated subnets with Power Platform ──────────────────
# Docs: "Configure your virtual network and subnet for delegation to Power Platform."
# Run once per virtual network that contains a delegated subnet.
# US geography (unitedstates) requires both a primary (eastus) and secondary (westus) VNet.

Write-Host "`n[1/3] Registering subnet delegation (primary)..."
Write-Host "      Subscription : $SubscriptionId"
Write-Host "      VNet         : $VirtualNetworkName"
Write-Host "      Subnet       : $SubnetName"

if ($PSCmdlet.ShouldProcess("$VirtualNetworkName/$SubnetName", "New-VnetForSubnetDelegation")) {
    New-VnetForSubnetDelegation `
        -SubscriptionId     $SubscriptionId `
        -VirtualNetworkName $VirtualNetworkName `
        -SubnetName         $SubnetName
}

Write-Host "`n[1b/3] Registering subnet delegation (secondary)..."
Write-Host "      VNet  : $SecondaryVirtualNetworkName"
Write-Host "      Subnet: $SecondarySubnetName"

if ($PSCmdlet.ShouldProcess("$SecondaryVirtualNetworkName/$SecondarySubnetName", "New-VnetForSubnetDelegation")) {
    New-VnetForSubnetDelegation `
        -SubscriptionId     $SubscriptionId `
        -VirtualNetworkName $SecondaryVirtualNetworkName `
        -SubnetName         $SecondarySubnetName
}

# ─── Step 2: Create the enterprise policy ────────────────────────────────────
# Docs: "Create your enterprise policy using the virtual networks and subnets you delegated."
# US geography (unitedstates) requires both a primary (eastus) and secondary (westus) VNet.

$VNetResourceId          = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" +
                           "/providers/Microsoft.Network/virtualNetworks/$VirtualNetworkName"
$SecondaryVNetResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" +
                           "/providers/Microsoft.Network/virtualNetworks/$SecondaryVirtualNetworkName"

Write-Host "`n[2/3] Creating enterprise policy '$PolicyName'..."
Write-Host "      Resource group       : $ResourceGroupName"
Write-Host "      Policy location      : $PolicyLocation"
Write-Host "      Primary VNet ID      : $VNetResourceId"
Write-Host "      Secondary VNet ID    : $SecondaryVNetResourceId"

if ($PSCmdlet.ShouldProcess($PolicyName, "New-SubnetInjectionEnterprisePolicy")) {
    New-SubnetInjectionEnterprisePolicy `
        -SubscriptionId            $SubscriptionId `
        -ResourceGroupName         $ResourceGroupName `
        -PolicyName                $PolicyName `
        -PolicyLocation            $PolicyLocation `
        -VirtualNetworkId          $VNetResourceId `
        -SubnetName                $SubnetName `
        -SecondaryVirtualNetworkId $SecondaryVNetResourceId `
        -SecondarySubnetName       $SecondarySubnetName
}

# ─── Step 3: Link the policy to the Power Platform environment ────────────────
# Docs: "To link your newly created policy, run the following command."

$PolicyArmId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" +
               "/providers/Microsoft.PowerPlatform/enterprisePolicies/$PolicyName"

Write-Host "`n[3/3] Enabling subnet injection on environment '$EnvironmentId'..."
Write-Host "      Policy ARM ID: $PolicyArmId"

if ($PSCmdlet.ShouldProcess($EnvironmentId, "Enable-SubnetInjection")) {
    Enable-SubnetInjection `
        -EnvironmentId $EnvironmentId `
        -PolicyArmId   $PolicyArmId
}

Write-Host "`nDone. Power Platform VNet integration is configured." -ForegroundColor Green
