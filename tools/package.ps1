$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
$release = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$destination = Join-Path $projectRoot 'dist\Pulse'
if (!(Test-Path (Join-Path $release 'pulse_battery.exe'))) { throw 'Run tools/build.ps1 first.' }
$configuration = Join-Path $projectRoot 'windows\flutter\ephemeral\generated_config.cmake'
if ((Get-Content -LiteralPath $configuration -Raw) -match 'capture_screenshots\.dart') {
    throw 'Screenshot build detected. Run tools/build.ps1 with its default target before packaging.'
}
New-Item -ItemType Directory -Force $destination | Out-Null
Copy-Item -Path "$release\*" -Destination $destination -Recurse -Force
# Include the app-local VC runtime so the portable app needs no VS installation.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$instances = & $vswhere -all -products '*' -format json | ConvertFrom-Json
$crt = $null
foreach ($instance in $instances) {
    $redist = Join-Path $instance.installationPath 'VC\Redist\MSVC'
    if (Test-Path $redist) {
        $crt = Get-ChildItem $redist -Directory | Where-Object Name -Match '^14\.' | Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\Microsoft.VC143.CRT' } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($crt) { break }
    }
}
if (!$crt) { throw 'VC143 redistributable directory was not found.' }
Copy-Item -Path "$crt\*.dll" -Destination $destination -Force
Copy-Item README.md (Join-Path $destination 'README.md') -Force
$docs = Join-Path $destination 'docs'
New-Item -ItemType Directory -Path $docs -Force | Out-Null
Copy-Item -Path 'docs\*' -Destination $docs -Recurse -Force
Compress-Archive -Path $destination -DestinationPath (Join-Path $projectRoot 'dist\Pulse-Windows-x64.zip') -Force
Get-FileHash 'dist\Pulse-Windows-x64.zip' -Algorithm SHA256
