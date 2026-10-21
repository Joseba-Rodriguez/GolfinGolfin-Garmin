param(
    [string]$SdkBin = $env:GARMIN_SDK_BIN,
    [string]$DeveloperKey = $env:GARMIN_DEVELOPER_KEY,
    [switch]$Export
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($SdkBin)) {
    throw 'Falta el SDK de Garmin. Instala SDK Manager y el perfil Instinct E 40mm; indica -SdkBin.'
}
if ([string]::IsNullOrWhiteSpace($DeveloperKey) -or -not (Test-Path -LiteralPath $DeveloperKey -PathType Leaf)) {
    throw 'Indica -DeveloperKey con tu clave privada existente, fuera del repositorio.'
}
$compiler = Join-Path $SdkBin 'monkeyc.bat'
$runner = Join-Path $SdkBin 'monkeydo.bat'
foreach ($executable in @($compiler, $runner)) {
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "No se encuentra la herramienta oficial: $executable"
    }
}
$compiler = (Resolve-Path -LiteralPath $compiler).Path
$runner = (Resolve-Path -LiteralPath $runner).Path
$DeveloperKey = (Resolve-Path -LiteralPath $DeveloperKey).Path

Push-Location $projectRoot
try {
    [xml]$manifest = Get-Content -LiteralPath 'manifest.xml' -Raw
    $products = @($manifest.manifest.application.products.product)
    if ($products.Count -ne 1 -or $products[0].id -ne 'instincte40mm') {
        throw 'La verificacion solo admite el Garmin Instinct E 40mm (instincte40mm).'
    }
    $expectedTests = 0
    Get-ChildItem -LiteralPath 'source' -Filter '*.mc' | ForEach-Object {
        $expectedTests += [regex]::Matches((Get-Content -LiteralPath $_.FullName -Raw), '\(:test\)').Count
    }
    if ($expectedTests -eq 0) {
        throw 'No se han encontrado pruebas Monkey C.'
    }
    New-Item -ItemType Directory -Path 'bin' -Force | Out-Null
    & $compiler -f monkey.jungle -d instincte40mm -y $DeveloperKey -w -t -o bin\GolfTests.prg
    if ($LASTEXITCODE -ne 0) {
        throw 'La compilacion de pruebas ha fallado. No se exporta la app.'
    }
    Write-Host 'Ejecutando pruebas. El simulador oficial debe estar abierto (connectiq.bat).'
    $testOutput = & $runner bin\GolfTests.prg instincte40mm /t 2>&1
    $testExitCode = $LASTEXITCODE
    $testOutput | Tee-Object -FilePath 'bin\test-results.log' | Out-Host
    $resultText = $testOutput | Out-String
    $testCount = [regex]::Match($resultText, 'Ran\s+(\d+)\s+tests?')
    if ($testExitCode -ne 0 -or $resultText -notmatch 'PASSED\s*\((?:failures=0,\s*errors=0|passed=\d+,\s*failed=0,\s*errors=0)\)' -or
        -not $testCount.Success -or [int]$testCount.Groups[1].Value -ne $expectedTests) {
        throw 'No se confirma que TODAS las pruebas pasen. Revisa bin/test-results.log; no se exporta.'
    }
    & $compiler -f monkey.jungle -d instincte40mm -y $DeveloperKey -w -r -o bin\GolfInstinct.prg
    if ($LASTEXITCODE -ne 0) {
        throw 'La compilacion release para Instinct E 40mm ha fallado.'
    }
    Write-Host "Compilacion y $expectedTests pruebas unitarias correctas para instincte40mm."
    Write-Host 'Faltan las pruebas visuales, GPS, red real y memoria del simulador; esto no certifica el reloj fisico.'
    if ($Export) {
        & $compiler -f monkey.jungle -y $DeveloperKey -w -r -e -o bin\GolfInstinct.iq
        if ($LASTEXITCODE -ne 0) {
            throw 'La exportacion IQ ha fallado.'
        }
        Write-Host 'Paquete generado: bin/GolfInstinct.iq. No se ha publicado en ninguna tienda.'
    }
} finally {
    Pop-Location
}