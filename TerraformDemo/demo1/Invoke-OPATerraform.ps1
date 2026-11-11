#Requires -Version 5.1
<#
.SYNOPSIS
Checks a saved Terraform plan with OPA and optionally applies it.
.DESCRIPTION
Run from the demo folder. By default this performs a policy check only.
Use -Apply to deploy the saved plan after a successful OPA check.
The policy covers the standalone ingress resource used in this demonstration.
.EXAMPLE
.\Invoke-OPATerraform.ps1 -PlanFile .\ssh-before.tfplan
.EXAMPLE
.\Invoke-OPATerraform.ps1 -PlanFile .\ssh-after.tfplan -Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PlanFile,

    [string]$PolicyFile = (Join-Path $PSScriptRoot 'ssh-policy.rego'),

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$terraformExe = (Get-Command terraform -CommandType Application -ErrorAction Stop).Source
$opaExe = (Get-Command opa -CommandType Application -ErrorAction Stop).Source
$planPath = (Resolve-Path -LiteralPath $PlanFile -ErrorAction Stop).ProviderPath
$policyPath = (Resolve-Path -LiteralPath $PolicyFile -ErrorAction Stop).ProviderPath
if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
    throw 'PlanFile must name a saved Terraform plan file.'
}
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
    throw 'PolicyFile must name the Rego policy file.'
}

$workDirectory = $null
Push-Location -LiteralPath $PSScriptRoot
try {
    # Export and apply the same temporary copy of the binary plan.
    $workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('opa-terraform-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDirectory | Out-Null
    $snapshotPlan = Join-Path $workDirectory 'reviewed.tfplan'
    $jsonPath = Join-Path $workDirectory 'reviewed.json'
    Copy-Item -LiteralPath $planPath -Destination $snapshotPlan
    $planHash = (Get-FileHash -LiteralPath $snapshotPlan -Algorithm SHA256).Hash

    Write-Host "Reading saved plan: $planPath"
    $planJson = & $terraformExe show -json $snapshotPlan
    if ($LASTEXITCODE -ne 0) {
        throw 'Terraform could not export the saved plan. Apply was not run.'
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($jsonPath, ($planJson -join "`n"), $utf8)

    $opaJson = & $opaExe eval --format=json --data $policyPath --input $jsonPath 'data.terraform.ssh.decision'
    if ($LASTEXITCODE -ne 0) {
        throw 'OPA evaluation failed. Apply was not run.'
    }

    $evaluation = ($opaJson -join "`n") | ConvertFrom-Json -ErrorAction Stop
    $results = @($evaluation.result)
    if ($results.Count -ne 1) {
        throw 'OPA did not return exactly one decision. Apply was not run.'
    }
    $expressions = @($results[0].expressions)
    if ($expressions.Count -ne 1) {
        throw 'OPA returned an unexpected decision structure. Apply was not run.'
    }
    $decision = $expressions[0].value
    if ($decision.allow -isnot [bool]) {
        throw 'OPA allow must be a Boolean. Apply was not run.'
    }
    if (-not $decision.allow) {
        foreach ($reason in $decision.deny) {
            Write-Host "DENY: $reason" -ForegroundColor Red
        }
        throw 'OPA denied this plan. Terraform apply was not run.'
    }
    if (@($decision.deny).Count -ne 0) {
        throw 'OPA returned an inconsistent decision. Apply was not run.'
    }

    Write-Host 'OPA allowed this plan.' -ForegroundColor Green
    if (-not $Apply) {
        Write-Host 'Check only. Run again with -Apply to deploy through this gate.'
        return
    }

    if ((Get-FileHash -LiteralPath $snapshotPlan -Algorithm SHA256).Hash -ne $planHash) {
        throw 'The reviewed plan changed during the check. Apply was not run.'
    }
    Write-Host 'Applying the same saved plan checked by OPA.'
    & $terraformExe apply $snapshotPlan
    if ($LASTEXITCODE -ne 0) {
        throw 'Terraform apply failed. Inspect the output and state before retrying.'
    }
}
finally {
    if ($null -ne $workDirectory -and (Test-Path -LiteralPath $workDirectory)) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
