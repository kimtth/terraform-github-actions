<#
.SYNOPSIS
    Configures Power Platform VNet integration enterprise policy after Terraform apply.

.DESCRIPTION
    Implements the three-step PowerShell setup from:
    https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-setup-configure?pivots=powershell

    Step 1 - Register the existing delegated subnet with Power Platform.
    Step 2 - Create the enterprise policy in the resource group.
    Step 3 - Link the policy to the target Power Platform environment.

.PREREQUISITES
    - Power Platform administrator role (Entra)
    - Network Contributor (or equivalent) on the Azure subscription
    - The Power Platform environment must be a Managed Environment.
    - Terraform must have been applied successfully so the VNet/subnet exist.

.PARAMETER EnvironmentId
    The Power Platform environment ID.
    Find it in: Power Platform admin center > Environments > <env> > Settings > Details.
    For the default environment the value includes a "Default-" prefix (e.g. "Default-<guid>").
    For non-default environments it is a plain GUID.

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
    Name of the secondary VNet. Required for two-region geographies (e.g. US, Japan).
    Defaults to the Terraform default. Set enable_secondary_vnet = true in tfvars first.

.PARAMETER SecondarySubnetName
    Name of the Power Platform delegated subnet in the secondary VNet.

.PARAMETER PolicyName
    Name to give the new enterprise policy resource.

.PARAMETER PolicyLocation
    Power Platform geography for the enterprise policy.
    This is a Power Platform-specific value - NOT an Azure region name.
    Find it in Power Platform admin center > Environments > <env> > Settings > Details > Region.
    Examples: "unitedstates", "japan", "europe", "australia"
    See: https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions

.EXAMPLE
    .\setup-powerplatform-vnet.ps1 `
        -EnvironmentId  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -TenantId       "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -SubscriptionId "zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz" `
        -PolicyLocation "japan"

    Note: For the default environment the ID includes a "Default-" prefix.
    For non-default environments use a plain GUID.
    Find the value in: Power Platform admin center > Environments > <env> > Settings > Details > Environment ID.
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true)]
    [string] $EnvironmentId,

    [Parameter(Mandatory = $true)]
    [string] $TenantId,

    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,

    [string] $ResourceGroupName           = "azppf-rg",
    [string] $VirtualNetworkName          = "azppf-vnet",
    [string] $SubnetName                  = "azppf-ppf-subnet",
    [string] $SecondaryVirtualNetworkName = "azppf-vnet-secondary",
    [string] $SecondarySubnetName         = "azppf-ppf-subnet",
    [string] $PolicyName                  = "azppf-enterprise-policy",

    [Parameter(Mandatory = $true)]
    [string] $PolicyLocation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Clear all cached Az contexts to prevent a previously cached account from being reused.
# This forces an interactive login where the correct account can be selected.
if ($PSCmdlet.ShouldProcess("existing Az contexts", "Clear-AzContext")) {
    Clear-AzContext -Force | Out-Null
}
if ($PSCmdlet.ShouldProcess("tenant $TenantId", "Connect-AzAccount")) {
    Connect-AzAccount -TenantId $TenantId -Subscription $SubscriptionId | Out-Null
    Set-AzContext -TenantId $TenantId -Subscription $SubscriptionId | Out-Null
}

# --- Step 0: Install / import the module -------------------------------------

# Workaround: Microsoft.PowerPlatform.EnterprisePolicies references $Global:InPesterExecution
# without initialising it. StrictMode -Version Latest treats this as a terminating error.
$Global:InPesterExecution = $false

if (-not (Get-Module -ListAvailable -Name "Microsoft.PowerPlatform.EnterprisePolicies")) {
    Write-Host "Installing Microsoft.PowerPlatform.EnterprisePolicies module..."
    Install-Module Microsoft.PowerPlatform.EnterprisePolicies -Scope CurrentUser -Force
}
Set-StrictMode -Off
Import-Module Microsoft.PowerPlatform.EnterprisePolicies
Set-StrictMode -Version Latest

# Pre-compute resource IDs used across steps.
$VNetResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" +
                  "/providers/Microsoft.Network/virtualNetworks/$VirtualNetworkName"
$SecondaryVNetResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" +
                           "/providers/Microsoft.Network/virtualNetworks/$SecondaryVirtualNetworkName"

# --- Step 1: Register the existing delegated subnets with Power Platform -----

Write-Host "`n[1/3] Registering subnet delegation (primary)..."
Write-Host "      Subscription : $SubscriptionId"
Write-Host "      VNet         : $VirtualNetworkName"
Write-Host "      Subnet       : $SubnetName"

if ($PSCmdlet.ShouldProcess("$VirtualNetworkName/$SubnetName", "New-VnetForSubnetDelegation")) {
    New-VnetForSubnetDelegation `
        -SubscriptionId     $SubscriptionId `
        -ResourceGroupName  $ResourceGroupName `
        -VirtualNetworkName $VirtualNetworkName `
        -SubnetName         $SubnetName
}

Write-Host "`n[1b/3] Registering subnet delegation (secondary)..."
Write-Host "      VNet  : $SecondaryVirtualNetworkName"
Write-Host "      Subnet: $SecondarySubnetName"

if ($PSCmdlet.ShouldProcess("$SecondaryVirtualNetworkName/$SecondarySubnetName", "New-VnetForSubnetDelegation")) {
    New-VnetForSubnetDelegation `
        -SubscriptionId     $SubscriptionId `
        -ResourceGroupName  $ResourceGroupName `
        -VirtualNetworkName $SecondaryVirtualNetworkName `
        -SubnetName         $SecondarySubnetName
}

# --- Step 2: Create the enterprise policy ------------------------------------

Write-Host "`n[2/3] Creating enterprise policy '$PolicyName'..."
Write-Host "      Resource group    : $ResourceGroupName"
Write-Host "      Policy location   : $PolicyLocation"
Write-Host "      Primary VNet ID   : $VNetResourceId"
Write-Host "      Secondary VNet ID : $SecondaryVNetResourceId"

if ($PSCmdlet.ShouldProcess($PolicyName, "New-SubnetInjectionEnterprisePolicy")) {
    $policyParams = @{
        SubscriptionId    = $SubscriptionId
        ResourceGroupName = $ResourceGroupName
        PolicyName        = $PolicyName
        PolicyLocation    = $PolicyLocation
        VirtualNetworkId  = $VNetResourceId
        SubnetName        = $SubnetName
    }

    # The secondary VNet parameter name varies across module versions - detect at runtime.
    $cmdMeta = Get-Command New-SubnetInjectionEnterprisePolicy
    if ($cmdMeta.Parameters.ContainsKey("VirtualNetworkId2")) {
        # v0.12.0+ uses VirtualNetworkId2 / SubnetName2
        $policyParams["VirtualNetworkId2"] = $SecondaryVNetResourceId
        $policyParams["SubnetName2"]        = $SecondarySubnetName
    }
    elseif ($cmdMeta.Parameters.ContainsKey("SecondaryVirtualNetworkId")) {
        $policyParams["SecondaryVirtualNetworkId"] = $SecondaryVNetResourceId
        $policyParams["SecondarySubnetName"]        = $SecondarySubnetName
    }
    elseif ($cmdMeta.Parameters.ContainsKey("SecondaryVirtualNetworkResourceId")) {
        $policyParams["SecondaryVirtualNetworkResourceId"] = $SecondaryVNetResourceId
        $policyParams["SecondarySubnetName"]                = $SecondarySubnetName
    }
    else {
        $available = ($cmdMeta.Parameters.Keys | Where-Object { $_ -like "*econdary*" -or $_ -like "*2" }) -join ", "
        Write-Warning "Could not find a secondary VNet parameter (module v$($cmdMeta.Module.Version)). Available: $available"
        Write-Warning "Proceeding without secondary VNet - update the parameter name in this script if needed."
    }

    New-SubnetInjectionEnterprisePolicy @policyParams
}

# --- Step 3: Link the policy to the Power Platform environment ----------------

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