param([string]$Target = 'lib/main.dart')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
flutter build windows --release --target $Target
if ($LASTEXITCODE -ne 0) {
    # Flutter may select an incomplete newer Visual Studio installation.
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $instances = & $vswhere -all -products '*' -format json | ConvertFrom-Json
    $vs = $instances | Where-Object { $_.isComplete -and $_.installationVersion.StartsWith('17.') } | Select-Object -First 1
    if (!$vs) { throw 'Install Visual Studio 2022 Desktop development with C++ and Windows SDK.' }
    $cmake = Join-Path $vs.installationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    flutter build windows --release --config-only --target $Target
    & $cmake --fresh -S windows -B build/windows/x64 -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_GENERATOR_INSTANCE=$($vs.installationPath.Replace('\','/'))"
    if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed' }
    & $cmake --build build/windows/x64 --config Release --target INSTALL
    if ($LASTEXITCODE -ne 0) { throw 'CMake build failed' }
}
Write-Host 'Ready: build\windows\x64\runner\Release\pulse_battery.exe'
