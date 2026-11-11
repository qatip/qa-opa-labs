<#
.SYNOPSIS
Disable blocking for the owner and/or non-root Gatekeeper constraints.
.DESCRIPTION
Sets Gatekeeper enforcementAction to dryrun for the Owner and/or NonRoot demo
constraints. Gatekeeper keeps running. Only these named constraints are changed.
All selected constraints are checked before any changes are applied.
If the matching YAML exists, its enforcementAction is updated after a successful
cluster patch. Other YAML content is preserved. Missing YAML does not prevent a
cluster update and is reported explicitly.
.EXAMPLE
.\Disable-OPAConstraints.ps1
.EXAMPLE
.\Disable-OPAConstraints.ps1 -Constraint Owner
.EXAMPLE
.\Disable-OPAConstraints.ps1 -Constraint NonRoot
#>
[CmdletBinding()]
param(
    [ValidateSet('Both', 'Owner', 'NonRoot')]
    [string]$Constraint = 'Both',

    [ValidateNotNullOrEmpty()]
    [string]$Context = 'docker-desktop',

    [ValidateNotNullOrEmpty()]
    [string]$ManifestDirectory = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$mode = 'dryrun'
$kubectlExe = (Get-Command kubectl -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source
$utf8 = New-Object System.Text.UTF8Encoding($false)
$modePattern = '(?m)^([ \t]*enforcementAction:[ \t]*)(deny|dryrun|warn)([ \t]*(?:#[^\r\n]*)?)(\r?)$'

$selected = @(
    if ($Constraint -in @('Both', 'Owner')) {
        [pscustomobject]@{
            Label = 'Owner'
            Kind = 'k8sdemorequiredlabels.constraints.gatekeeper.sh'
            Name = 'pods-must-have-owner'
            File = '02-owner-required.yaml'
            UpdatedYaml = $null
            Path = $null
        }
    }
    if ($Constraint -in @('Both', 'NonRoot')) {
        [pscustomobject]@{
            Label = 'NonRoot'
            Kind = 'k8sdemononroot.constraints.gatekeeper.sh'
            Name = 'pods-must-run-as-nonroot'
            File = '04-nonroot-required.yaml'
            UpdatedYaml = $null
            Path = $null
        }
    }
)

# Check every selected resource and saved file before changing the cluster.
foreach ($item in $selected) {
    $currentJson = & $kubectlExe --context $Context get $item.Kind $item.Name -o json
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot read $($item.Name) in context '$Context'. No changes applied."
    }
    $current = ($currentJson -join [Environment]::NewLine) | ConvertFrom-Json
    if ($current.metadata.name -ne $item.Name) {
        throw "Unexpected constraint response. No changes applied."
    }

    $item.Path = Join-Path $ManifestDirectory $item.File
    if (Test-Path -LiteralPath $item.Path -PathType Leaf) {
        $originalYaml = [IO.File]::ReadAllText($item.Path)
        if ([regex]::Matches($originalYaml, $modePattern).Count -ne 1) {
            throw "Expected one enforcementAction in '$($item.Path)'. No changes applied."
        }
        $item.UpdatedYaml = [regex]::Replace(
            $originalYaml, $modePattern, '${1}' + $mode + '${3}${4}'
        )
    }
}

Write-Host "Context: $Context | Requested enforcementAction: $mode"
$patchFile = [IO.Path]::GetTempFileName()
try {
    $patch = @{ spec = @{ enforcementAction = $mode } } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($patchFile, $patch, $utf8)

    foreach ($item in $selected) {
        & $kubectlExe --context $Context patch $item.Kind $item.Name `
            --type merge --patch-file $patchFile
        if ($LASTEXITCODE -ne 0) {
            throw "Patch failed for $($item.Name). Earlier successful changes remain applied."
        }

        if ($null -ne $item.UpdatedYaml) {
            try {
                [IO.File]::WriteAllText($item.Path, $item.UpdatedYaml, $utf8)
            } catch {
                throw "Cluster updated for $($item.Name), but saving '$($item.Path)' failed: $_"
            }
            Write-Host "$($item.Label): $mode | Saved YAML updated: $($item.File)"
        } else {
            Write-Host "$($item.Label): $mode | Saved YAML not found: $($item.Path)"
        }
    }
} finally {
    Remove-Item -LiteralPath $patchFile -Force -ErrorAction SilentlyContinue
}

Write-Host 'Configured. Allow Gatekeeper controllers to reconcile before testing new Pods.'
Write-Host 'Matching requests are allowed by these rules; violations remain available through audit.'
