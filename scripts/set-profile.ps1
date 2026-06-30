param(
    [Parameter(Mandatory = $true)]
    [string]$Profile,

    [string]$ApiBaseUrl = "http://localhost:25555",

    [string]$ExePath = "",

    [int]$StartupTimeoutSeconds = 20
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ExePath = Join-Path $scriptDir "..\publish\win-x64\open-cue-service.exe"
}

function Test-ServiceReady {
    param([string]$BaseUrl)

    try {
        Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/profiles" | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Wait-ServiceReady {
    param(
        [string]$BaseUrl,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-ServiceReady -BaseUrl $BaseUrl) {
            return
        }
        Start-Sleep -Milliseconds 500
    }

    throw "Service did not become ready within $TimeoutSeconds seconds at $BaseUrl"
}

if (-not (Test-ServiceReady -BaseUrl $ApiBaseUrl)) {
    if (-not (Test-Path $ExePath)) {
        throw "Service exe not found at '$ExePath'. Build it first with: dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o .\\publish\\win-x64"
    }

    Start-Process -FilePath $ExePath -WindowStyle Hidden | Out-Null
    Wait-ServiceReady -BaseUrl $ApiBaseUrl -TimeoutSeconds $StartupTimeoutSeconds
}

$profiles = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/api/profiles"
$target = $profiles | Where-Object { $_.name -ieq $Profile } | Select-Object -First 1

if (-not $target) {
    $available = ($profiles | ForEach-Object { $_.name }) -join ", "
    throw "Profile '$Profile' not found. Available profiles: $available"
}

# Ensure only the selected profile is active.
Invoke-RestMethod -Method Post -Uri "$ApiBaseUrl/api/sdk/deactivate-all-profiles" | Out-Null
$setResult = Invoke-RestMethod -Method Put -Uri "$ApiBaseUrl/api/profiles/$($target.name)/state/true"

"Activated profile: $($setResult.name)"
"Priority: $($setResult.priority)"
"State: $($setResult.state)"
