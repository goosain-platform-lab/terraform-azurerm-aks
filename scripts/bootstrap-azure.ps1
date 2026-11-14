<#
.SYNOPSIS
    One-time Azure setup so HCP Terraform can deploy with OIDC (no client secret).

.DESCRIPTION
    MAKES CHANGES. Run in Windows PowerShell 5.1 or PowerShell 7 on your own
    machine, after `az login` with an account that can create app
    registrations and assign roles on the subscription.

    Creates (or reuses, if they already exist):
      1. An Entra app registration + service principal for HCP Terraform.
      2. Federated credentials for each workspace (plan and apply phases).
      3. Subscription role assignments: Contributor and Role Based Access
         Control Administrator (+ Resource Policy Contributor with
         -IncludePolicyRole, needed by the landing zone's guardrails).
      4. An Entra admin group (for SQL admin and jumpbox sign-in) containing you.

    Stops at the first error. Prints the non-secret values to enter in HCP
    Terraform; nothing is written to disk except a temp JSON file per
    federated credential, deleted straight after use.

.EXAMPLE
    .\bootstrap-azure.ps1 -SubscriptionId <id> -HcpOrganization my-org -Workspaces ai-stt-lab
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]   $SubscriptionId,
    [Parameter(Mandatory = $true)] [string]   $HcpOrganization,
    [Parameter(Mandatory = $true)] [string[]] $Workspaces,
    [string] $HcpProject = 'Default Project',
    [string] $AppName = 'hcp-terraform-ai-lab',
    [string] $AdminGroupName = 'ai-lab-admins',
    [switch] $IncludePolicyRole
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Invoke-Az {
    param([Parameter(Mandatory = $true)] [string[]] $AzArgs)
    # az writes warnings to stderr; capture them without tripping Stop, then
    # fail on the exit code rather than on stderr noise.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = & az @AzArgs --only-show-errors 2>&1
    }
    finally {
        $ErrorActionPreference = $prev
    }
    $code = $LASTEXITCODE
    $errs = @($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.ToString() })
    $out = @($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { [string]$_ })
    if ($code -ne 0) {
        throw ('az {0} failed (exit {1}): {2}' -f ($AzArgs -join ' '), $code, ($errs -join ' '))
    }
    return ($out -join "`n").Trim()
}

# Emits one trimmed line per pipeline item. Always call it inside @( ... ) so
# an empty or single result is still an array under Windows PowerShell 5.1.
function Get-Lines([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $Text -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() }
}

# --- 0. Preconditions --------------------------------------------------------
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) is not on PATH.' }
Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
$who = Invoke-Az @('account', 'show', '--query', 'user.name', '-o', 'tsv')
$tenantId = Invoke-Az @('account', 'show', '--query', 'tenantId', '-o', 'tsv')
if (-not $who -or -not $tenantId) { throw 'Could not read the signed-in account. Run az login first.' }

Write-Host ''
Write-Host ('Signed in as : {0}' -f $who)
Write-Host ('Subscription : {0}' -f $SubscriptionId)
Write-Host ('Workspaces   : {0}' -f ($Workspaces -join ', '))
$answer = Read-Host 'This makes changes in Entra ID and the subscription. Type YES to continue'
if ($answer -ne 'YES') { throw 'Aborted by user.' }

$scope = '/subscriptions/{0}' -f $SubscriptionId

# --- 1. App registration + service principal ---------------------------------
$appIds = @(Get-Lines (Invoke-Az @('ad', 'app', 'list', '--display-name', $AppName, '--query', '[].appId', '-o', 'tsv')))
if ($appIds.Count -gt 1) { throw ('More than one app registration is named {0}; rename or delete the extras.' -f $AppName) }
if ($appIds.Count -eq 1) {
    $appId = $appIds[0]
    Write-Host ('[=] App registration exists: {0}' -f $appId)
}
else {
    $appId = Invoke-Az @('ad', 'app', 'create', '--display-name', $AppName, '--query', 'appId', '-o', 'tsv')
    Write-Host ('[+] Created app registration: {0}' -f $appId)
}

$spIds = @(Get-Lines (Invoke-Az @('ad', 'sp', 'list', '--filter', ("appId eq '{0}'" -f $appId), '--query', '[].id', '-o', 'tsv')))
if ($spIds.Count -eq 1) {
    $spId = $spIds[0]
    Write-Host ('[=] Service principal exists: {0}' -f $spId)
}
elseif ($spIds.Count -eq 0) {
    $spId = Invoke-Az @('ad', 'sp', 'create', '--id', $appId, '--query', 'id', '-o', 'tsv')
    Write-Host ('[+] Created service principal: {0}' -f $spId)
}
else {
    throw 'Unexpected: more than one service principal for the app.'
}

# --- 2. Federated credentials (one per workspace per run phase) --------------
$existing = @(Get-Lines (Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $appId, '--query', '[].name', '-o', 'tsv')))
foreach ($ws in $Workspaces) {
    foreach ($phase in @('plan', 'apply')) {
        $name = ('hcp-{0}-{1}' -f $ws, $phase)
        if ($existing -contains $name) {
            Write-Host ('[=] Federated credential exists: {0}' -f $name)
            continue
        }
        $subject = 'organization:{0}:project:{1}:workspace:{2}:run_phase:{3}' -f $HcpOrganization, $HcpProject, $ws, $phase
        $body = @{
            name      = $name
            issuer    = 'https://app.terraform.io'
            subject   = $subject
            audiences = @('api://AzureADTokenExchange')
        } | ConvertTo-Json
        $tmp = Join-Path $env:TEMP ('fic-{0}.json' -f [guid]::NewGuid())
        Set-Content -Path $tmp -Value $body -Encoding ascii
        try {
            Invoke-Az @('ad', 'app', 'federated-credential', 'create', '--id', $appId, '--parameters', ('@' + $tmp)) | Out-Null
        }
        finally {
            Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
        }
        Write-Host ('[+] Federated credential: {0} -> {1}' -f $name, $subject)
    }
}

# --- 3. Subscription roles for the deployer ----------------------------------
$roles = @('Contributor', 'Role Based Access Control Administrator')
if ($IncludePolicyRole) { $roles += 'Resource Policy Contributor' }
$have = @(Get-Lines (Invoke-Az @('role', 'assignment', 'list', '--assignee', $spId, '--scope', $scope, '--query', '[].roleDefinitionName', '-o', 'tsv')))
foreach ($role in $roles) {
    if ($have -contains $role) {
        Write-Host ('[=] Role exists: {0}' -f $role)
        continue
    }
    Invoke-Az @('role', 'assignment', 'create', '--assignee-object-id', $spId, '--assignee-principal-type', 'ServicePrincipal', '--role', $role, '--scope', $scope) | Out-Null
    Write-Host ('[+] Role assigned: {0}' -f $role)
}

# --- 4. Admin group (SQL Entra admin + jumpbox sign-in) ----------------------
$groupIds = @(Get-Lines (Invoke-Az @('ad', 'group', 'list', '--display-name', $AdminGroupName, '--query', '[].id', '-o', 'tsv')))
if ($groupIds.Count -gt 1) { throw ('More than one group is named {0}.' -f $AdminGroupName) }
if ($groupIds.Count -eq 1) {
    $groupId = $groupIds[0]
    Write-Host ('[=] Admin group exists: {0}' -f $groupId)
}
else {
    $groupId = Invoke-Az @('ad', 'group', 'create', '--display-name', $AdminGroupName, '--mail-nickname', $AdminGroupName, '--query', 'id', '-o', 'tsv')
    Write-Host ('[+] Created admin group: {0}' -f $groupId)
}
$me = Invoke-Az @('ad', 'signed-in-user', 'show', '--query', 'id', '-o', 'tsv')
$isMember = Invoke-Az @('ad', 'group', 'member', 'check', '--group', $groupId, '--member-id', $me, '--query', 'value', '-o', 'tsv')
if ($isMember -ne 'true') {
    Invoke-Az @('ad', 'group', 'member', 'add', '--group', $groupId, '--member-id', $me) | Out-Null
    Write-Host '[+] Added you to the admin group'
}

# --- 5. What to enter in HCP Terraform ---------------------------------------
Write-Host ''
Write-Host 'Done. Add these as ENVIRONMENT variables in each HCP Terraform workspace:'
Write-Host '  TFC_AZURE_PROVIDER_AUTH = true'
Write-Host ('  TFC_AZURE_RUN_CLIENT_ID = {0}' -f $appId)
Write-Host ('  ARM_SUBSCRIPTION_ID     = {0}' -f $SubscriptionId)
Write-Host ('  ARM_TENANT_ID           = {0}' -f $tenantId)
Write-Host ''
Write-Host 'And these as TERRAFORM variables (HCL enabled):'
Write-Host ('  sql_entra_admin            = {{ login_username = "{0}", object_id = "{1}" }}   (batch and landing zone)' -f $AdminGroupName, $groupId)
Write-Host ('  jumpbox_admin_principal_id = "{0}"   (landing zone only)' -f $groupId)
Write-Host ''
Write-Host 'None of these values is a secret. No client secret was created.'
