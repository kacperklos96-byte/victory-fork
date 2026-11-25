# GTX 1650 / six-core CPU experiment runner.
# This is a tuning harness, not a graphics fix. Do not put game data in this repo.
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GameExe,

    [ValidateSet("visuals", "balanced", "fast-experimental", "v3")]
    [string]$Profile = "v3",

    [string]$DataRoot = "D:\VIctoryForkData",

    [ValidateRange(1, 8)]
    [int]$Workers = 2,

    [ValidateRange(128, 1024)]
    [int]$CardBufferMB = 512,

    [ValidateRange(0, 8192)]
    [int]$TargetReserveMB = 2048,

    [switch]$OnDemandMips,
    [switch]$CopyQueue,
    [switch]$AsyncSubmit,

    [switch]$Capture
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$binary = Join-Path $root "target\release\victory.exe"

if (-not (Test-Path -LiteralPath $GameExe -PathType Leaf)) {
    throw "Game executable not found: $GameExe"
}
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) {
    throw "Build first: cargo build --release -p victory (from $root)"
}

$variables = @(
    "VICTORY_CACHE_DIR",
    "VICTORY_DATA_DIR",
    "VICTORY_PIPELINE_WORKERS",
    "VICTORY_PIPELINE_WAIT_MS",
    "VICTORY_CARD_BUFFERS_MB",
    "VICTORY_RELAY",
    "VICTORY_CAPTURE",
    "VICTORY_LEVELS_ON_DEMAND",
    "VICTORY_CARD_ROOM_FOR_TARGETS_MB",
    "VICTORY_CARD_BUFFERS_MIN_MB",
    "VICTORY_WIDE_BACK",
    "VICTORY_QUEUE2",
    "VICTORY_ASYNC_SUBMIT",
    "VICTORY_INDIRECT_WINDOW",
    "VICTORY_CARD_FETCH_INFLIGHT"
)
$original = @{}
foreach ($name in $variables) {
    $original[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
    $cacheDir = Join-Path $DataRoot "cache"
    $dataDir = Join-Path $DataRoot "data"
    New-Item -ItemType Directory -Path $cacheDir, $dataDir -Force | Out-Null
    $env:VICTORY_CACHE_DIR = $cacheDir
    $env:VICTORY_DATA_DIR = $dataDir

    # The i5-9400F has six cores. Reserve some CPU capacity for the title.
    $env:VICTORY_PIPELINE_WORKERS = [string]$Workers

    # New upstream defaults to 1024 MiB. Keep a smaller starting cap on 4 GB
    # hardware, but allow comparisons with the old 384 MiB cap.
    $env:VICTORY_CARD_BUFFERS_MB = [string]$CardBufferMB

    # Experimental: allocate only texture mip levels actually held by the title.
    # Keep this an explicit opt-in until tested on the GTX 1650.
    $env:VICTORY_LEVELS_ON_DEMAND = if ($OnDemandMips) { "1" } else { "0" }

    # Keep experimental combinations isolated for repeatable runs.
    $env:VICTORY_QUEUE2 = if ($CopyQueue) { "1" } else { "0" }
    $env:VICTORY_ASYNC_SUBMIT = if ($AsyncSubmit) { "1" } else { "0" }
    $env:VICTORY_INDIRECT_WINDOW = "0"
    $env:VICTORY_CARD_FETCH_INFLIGHT = "0"

    switch ($Profile) {
        "v3" {
            # V2 visuals forced relay off, causing synchronous copy-back.
            # Use the upstream stage-2 path and retain a conservative wait.
            $env:VICTORY_RELAY = "2"
            $env:VICTORY_PIPELINE_WAIT_MS = "500"
            $env:VICTORY_WIDE_BACK = "1"
            $env:VICTORY_CARD_BUFFERS_MIN_MB = "1"
            # The 3072 MiB upstream reservation was measured on a 4070.
            $env:VICTORY_CARD_ROOM_FOR_TARGETS_MB = [string]$TargetReserveMB
        }
        "visuals" {
            # Give one-off graphics passes more opportunity to get compiled.
            # More complete frames may mean even lower FPS.
            $env:VICTORY_PIPELINE_WAIT_MS = "1200"
            $env:VICTORY_RELAY = "0"
        }
        "balanced" {
            $env:VICTORY_PIPELINE_WAIT_MS = "500"
            $env:VICTORY_RELAY = "0"
        }
        "fast-experimental" {
            # Relayed submissions have helped the developer's GPU, but
            # may expose crashes on a GTX 1650. Try only after stable runs.
            $env:VICTORY_PIPELINE_WAIT_MS = "250"
            $env:VICTORY_RELAY = "2"
        }
    }

    if ($Capture) {
        $captureDir = Join-Path $DataRoot ("captures\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        New-Item -ItemType Directory -Path $captureDir -Force | Out-Null
        $env:VICTORY_CAPTURE = $captureDir
        Write-Host "Screenshots (not safe to commit): $captureDir"
    } else {
        Remove-Item Env:VICTORY_CAPTURE -ErrorAction SilentlyContinue
    }

    Write-Host "VIctory profile: $Profile"
    Write-Host "Pipeline workers: $env:VICTORY_PIPELINE_WORKERS"
    Write-Host "Pipeline wait budget: $env:VICTORY_PIPELINE_WAIT_MS ms/frame"
    Write-Host "Card buffer cap: $env:VICTORY_CARD_BUFFERS_MB MiB"
    Write-Host "Copy-back relay: $env:VICTORY_RELAY; copy queue: $env:VICTORY_QUEUE2; async submit: $env:VICTORY_ASYNC_SUBMIT"
    Write-Host "Render-target reserve (MiB): $env:VICTORY_CARD_ROOM_FOR_TARGETS_MB (blank = upstream default)"
    Write-Host "On-demand texture levels: $env:VICTORY_LEVELS_ON_DEMAND"
    Write-Host "Pipeline cache: $cacheDir"
    Write-Host "Game data and crashes: $dataDir"
    & $binary run $GameExe --execute
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "VIctory exited with code $LASTEXITCODE. Check crashes.log in $dataDir."
    }
}
finally {
    foreach ($name in $variables) {
        [Environment]::SetEnvironmentVariable($name, $original[$name], "Process")
    }
}
