<#
  Launcher interactivo para dispositivos Lefant propios.
  No distribuye APKs ni inicia sesión: abre la app oficial y después ejecuta
  el extractor Frida contra el dispositivo Android que el usuario controla.
#>
[CmdletBinding()]
param(
    [string]$Serial,
    [string]$Adb,
    [string]$Avd = "Pixel_6",
    [string]$EmulatorPath = "C:\Android\Sdk\emulator\emulator.exe",
    [string[]]$EmulatorArgs = @("-no-snapshot", "-gpu", "swiftshader_indirect"),
    [string]$FridaServerPath,
    [string]$FridaAddress,
    [string]$Output = "devices.json",
    [switch]$ShowKey
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$PackageName = "com.yunshi.robotlife"
$ValidatedVersion = "3.3.25"
$Root = $PSScriptRoot

function Stop-Launcher([string]$Message) {
    [Console]::Error.WriteLine("Error: $Message")
    exit 1
}

function Find-Adb {
    param([string]$Requested)
    if ($Requested) {
        if (-not (Test-Path -LiteralPath $Requested -PathType Leaf)) {
            Stop-Launcher "No existe ADB: $Requested"
        }
        return (Resolve-Path -LiteralPath $Requested).Path
    }
    $command = Get-Command adb.exe -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command adb -ErrorAction SilentlyContinue }
    if ($command) { return $command.Source }
    $bundled = Join-Path (Split-Path -Parent $Root) "adb.exe"
    if (Test-Path -LiteralPath $bundled -PathType Leaf) { return $bundled }
    Stop-Launcher "No se encontró adb. Instala Android platform-tools o usa -Adb RUTA."
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $command = @($script:AdbPath)
    if ($script:TargetSerial) { $command += @("-s", $script:TargetSerial) }
    $command += $Arguments
    $result = & $command[0] $command[1..($command.Length - 1)] 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb $($Arguments -join ' ') falló: $($result -join [Environment]::NewLine)"
    }
    return ($result -join [Environment]::NewLine).Trim()
}

function Get-AdbDevices {
    $raw = & $script:AdbPath devices
    if ($LASTEXITCODE -ne 0) { Stop-Launcher "No se pudo ejecutar adb devices." }
    return @($raw | Select-Object -Skip 1 | ForEach-Object {
        $parts = $_ -split '\s+'
        if ($parts.Count -ge 2 -and $parts[0]) { [pscustomobject]@{ Serial = $parts[0]; State = $parts[1] } }
    })
}

function Find-Emulator {
    $candidates = @($EmulatorPath)
    foreach ($variable in @("ANDROID_SDK_ROOT", "ANDROID_HOME")) {
        if ([Environment]::GetEnvironmentVariable($variable)) {
            $candidates += (Join-Path ([Environment]::GetEnvironmentVariable($variable)) "emulator\emulator.exe")
        }
    }
    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    Stop-Launcher "No se encontró emulator.exe. Usa -EmulatorPath 'C:\Android\Sdk\emulator\emulator.exe'."
}

function Wait-ForBootedEmulator([string]$StartedAvd) {
    $deadline = (Get-Date).AddMinutes(5)
    $target = $null
    Write-Host "Esperando a que el emulador aparezca en ADB..."
    while ((Get-Date) -lt $deadline) {
        $online = @(Get-AdbDevices | Where-Object { $_.Serial -match '^emulator-\d+$' -and $_.State -eq "device" })
        if ($online.Count -gt 0) {
            $target = $online[0].Serial
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $target) { Stop-Launcher "El AVD $StartedAvd no llegó al estado 'device' en ADB." }
    return Wait-ForBootCompleted $target
}

function Wait-ForBootCompleted([string]$Target) {
    $deadline = (Get-Date).AddMinutes(5)
    Write-Host "Emulador ADB operativo: $target. Esperando sys.boot_completed..."
    while ((Get-Date) -lt $deadline) {
        $boot = (& $script:AdbPath -s $target shell getprop sys.boot_completed 2>$null | Out-String).Trim()
        if ($boot -eq "1") { return $target }
        Start-Sleep -Seconds 2
    }
    Stop-Launcher "El emulador $target no completó el arranque (sys.boot_completed != 1)."
}

function Select-OrStartEmulator {
    $devices = @(Get-AdbDevices)
    # Los estados offline se ignoran por completo: no prueban que el AVD funcione.
    $online = @($devices | Where-Object { $_.Serial -match '^emulator-\d+$' -and $_.State -eq "device" })
    if ($Serial) {
        $requested = $online | Where-Object Serial -eq $Serial | Select-Object -First 1
        if ($requested) {
            Write-Host "Reutilizando emulador ADB operativo: $($requested.Serial)"
            return Wait-ForBootCompleted $requested.Serial
        }
    }
    if ($online.Count -gt 0) {
        Write-Host "Reutilizando emulador ADB operativo: $($online[0].Serial)"
        return Wait-ForBootCompleted $online[0].Serial
    }
    $emulator = Find-Emulator
    Write-Host "No hay emulador ADB operativo; arrancando AVD $Avd..."
    Start-Process -FilePath $emulator -ArgumentList (@("-avd", $Avd) + $EmulatorArgs) | Out-Null
    return Wait-ForBootedEmulator $Avd
}

function Find-PythonExecutable {
    $python = Get-Command py.exe -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python.exe -ErrorAction SilentlyContinue }
    if (-not $python) { Stop-Launcher "No se encontró Python para ejecutar Frida y lefant_devicebean_export.py." }
    return $python.Source
}

function Get-FridaClientVersion([string]$PythonPath) {
    $result = & $PythonPath -c "import frida; print(frida.__version__)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo detectar el cliente Frida instalado: $($result -join [Environment]::NewLine)"
    }
    return ($result -join "").Trim()
}

function Get-FridaPlatform([string]$Abi) {
    switch ($Abi.Trim()) {
        "x86_64" { return "android-x86_64" }
        "arm64-v8a" { return "android-arm64" }
        default { throw "ABI no compatible para este launcher: $Abi (se esperaba x86_64 o arm64-v8a)." }
    }
}

function Find-FridaServer([string]$Version, [string]$Platform) {
    $expectedName = "frida-server-$Version-$Platform"
    if ($FridaServerPath) {
        if (-not (Test-Path -LiteralPath $FridaServerPath -PathType Leaf)) {
            throw "No existe -FridaServerPath: $FridaServerPath"
        }
        return (Get-Item -LiteralPath $FridaServerPath)
    }
    $named = Join-Path $Root "frida\$expectedName"
    if (Test-Path -LiteralPath $named -PathType Leaf) { return (Get-Item -LiteralPath $named) }
    # Los dos nombres sin sufijo se validan tras desplegarlos con --version;
    # no se elige nunca un binario con sufijo de ABI/versión diferente.
    foreach ($path in @((Join-Path $Root "frida-server"), (Join-Path $Root "frida\frida-server"))) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return (Get-Item -LiteralPath $path) }
    }
    return $null
}

function Get-RemoteFridaVersion {
    $savedErrorAction = $ErrorActionPreference
    $nativePreferenceSupported = $PSVersionTable.PSVersion.Major -ge 7
    if ($nativePreferenceSupported) { $savedNativeErrorAction = $PSNativeCommandUseErrorActionPreference }
    try {
        $ErrorActionPreference = "Continue"
        if ($nativePreferenceSupported) { $PSNativeCommandUseErrorActionPreference = $false }
        $result = & $script:AdbPath -s $script:TargetSerial shell /data/local/tmp/frida-server --version 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorAction
        if ($nativePreferenceSupported) { $PSNativeCommandUseErrorActionPreference = $savedNativeErrorAction }
    }
    if ($code -ne 0) { return "" }
    return ($result -join "").Trim()
}

function Get-RemoteFridaPid {
    $savedErrorAction = $ErrorActionPreference
    $nativePreferenceSupported = $PSVersionTable.PSVersion.Major -ge 7
    if ($nativePreferenceSupported) { $savedNativeErrorAction = $PSNativeCommandUseErrorActionPreference }
    try {
        $ErrorActionPreference = "Continue"
        if ($nativePreferenceSupported) { $PSNativeCommandUseErrorActionPreference = $false }
        $result = & $script:AdbPath -s $script:TargetSerial shell pidof frida-server 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorAction
        if ($nativePreferenceSupported) { $PSNativeCommandUseErrorActionPreference = $savedNativeErrorAction }
    }
    if ($code -ne 0) { return "" }
    return ($result -join " ").Trim()
}

function Wait-ForAdbReconnect {
    $deadline = (Get-Date).AddMinutes(1)
    while ((Get-Date) -lt $deadline) {
        $state = (& $script:AdbPath -s $script:TargetSerial get-state 2>$null | Out-String).Trim()
        if ($state -eq "device") { return }
        Start-Sleep -Seconds 2
    }
    throw "ADB no reconectó tras adb root para $script:TargetSerial."
}

function Ensure-FridaServer([string]$PythonPath) {
    $abi = (Invoke-Adb shell getprop ro.product.cpu.abi).Trim()
    $platform = Get-FridaPlatform $abi
    $version = Get-FridaClientVersion $PythonPath
    $expectedName = "frida-server-$version-$platform"
    Write-Host "Frida cliente: $version | ABI: $abi"

    $remoteVersion = Get-RemoteFridaVersion
    $server = $null
    if ($remoteVersion -ne $version) {
        $server = Find-FridaServer $version $platform
        if (-not $server) {
            throw "No se encontró frida-server compatible. Cliente Frida: $version; ABI: $abi; nombre esperado: $expectedName. Usa -FridaServerPath PATH."
        }
    }
    $rootOutput = & $script:AdbPath -s $script:TargetSerial root 2>&1
    if ($LASTEXITCODE -ne 0) { throw "adb root falló: $($rootOutput -join [Environment]::NewLine)" }
    Wait-ForAdbReconnect
    if ($server) {
        # Detiene cualquier servidor previo antes de reemplazar el binario.
        & $script:AdbPath -s $script:TargetSerial shell pkill -f frida-server 2>$null | Out-Null
        $pushOutput = & $script:AdbPath -s $script:TargetSerial push $server.FullName /data/local/tmp/frida-server 2>&1
        if ($LASTEXITCODE -ne 0) { throw "adb push de frida-server falló: $($pushOutput -join [Environment]::NewLine)" }
        $chmodOutput = & $script:AdbPath -s $script:TargetSerial shell chmod 755 /data/local/tmp/frida-server 2>&1
        if ($LASTEXITCODE -ne 0) { throw "chmod de frida-server falló: $($chmodOutput -join [Environment]::NewLine)" }
        $remoteVersion = Get-RemoteFridaVersion
        if ($remoteVersion -ne $version) {
            throw "frida-server no coincide con el cliente. Cliente: $version; servidor detectado: $remoteVersion; esperado: $expectedName."
        }
    }

    if (-not (Get-RemoteFridaPid)) {
        $startOutput = & $script:AdbPath -s $script:TargetSerial shell "/data/local/tmp/frida-server >/dev/null 2>&1 &" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "No se pudo arrancar frida-server: $($startOutput -join [Environment]::NewLine)" }
        Start-Sleep -Seconds 2
    }
    if (-not (Get-RemoteFridaPid)) { throw "frida-server no quedó ejecutándose en /data/local/tmp/frida-server." }

    $verify = & $PythonPath -c "import frida; print(frida.get_usb_device(timeout=5000).id)" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Frida no responde desde Windows: $($verify -join [Environment]::NewLine)" }
    Write-Host "frida-server preparado y verificado."
}

function Test-LefantInstalled {
    # Android puede devolver código distinto de cero para un paquete inexistente.
    # Eso significa simplemente "no instalado", no un fallo del launcher.
    $result = & $script:AdbPath -s $script:TargetSerial shell pm path $PackageName 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($result -join [Environment]::NewLine).Trim()
    if ($text -match '(?m)^package:') { return $true }
    if ($exitCode -eq 0) { return $false }

    # Un fallo de transporte/shell sí impide continuar con seguridad.
    if ($text -match '(?i)(device offline|device not found|no devices/emulators found|device unauthorized|error: closed|transport.*error|protocol fault)') {
        throw "adb shell pm path no pudo acceder a $script:TargetSerial: $text"
    }
    return $false
}

function Get-LefantVersion {
    $dump = Invoke-Adb shell dumpsys package $PackageName
    $name = [regex]::Match($dump, '(?m)^\s*versionName=(.+)$').Groups[1].Value.Trim()
    $codeLine = [regex]::Match($dump, '(?m)^\s*versionCode=(.+)$').Groups[1].Value.Trim()
    $code = [regex]::Match($codeLine, '^\d+').Value
    if (-not $name) { $name = "desconocida" }
    if (-not $code) { $code = "desconocido" }
    return [pscustomobject]@{ Name = $name; Code = $code }
}

function Find-ApkInspector {
    $aapt = Get-Command aapt.exe -ErrorAction SilentlyContinue
    if (-not $aapt) { $aapt = Get-Command aapt -ErrorAction SilentlyContinue }
    if ($aapt) { return [pscustomobject]@{ Type = "aapt"; Path = $aapt.Source } }
    $analyzer = Get-Command apkanalyzer.bat -ErrorAction SilentlyContinue
    if (-not $analyzer) { $analyzer = Get-Command apkanalyzer -ErrorAction SilentlyContinue }
    if ($analyzer) { return [pscustomobject]@{ Type = "apkanalyzer"; Path = $analyzer.Source } }
    $sdkRoot = Split-Path -Parent (Split-Path -Parent $EmulatorPath)
    $buildTools = Join-Path $sdkRoot "build-tools"
    if (Test-Path -LiteralPath $buildTools -PathType Container) {
        $bundledAapt = Get-ChildItem -LiteralPath $buildTools -Directory | Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "aapt.exe" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($bundledAapt) { return [pscustomobject]@{ Type = "aapt"; Path = $bundledAapt } }
    }
    return $null
}

function Test-ApkIsLefant([System.IO.FileInfo]$Apk, $Inspector) {
    if (-not $Inspector) { return $false }
    if ($Inspector.Type -eq "aapt") {
        $result = & $Inspector.Path dump badging $Apk.FullName 2>&1
        if ($LASTEXITCODE -ne 0) { return $false }
        return (($result -join [Environment]::NewLine) -match "package: name='$([regex]::Escape($PackageName))'")
    }
    $result = & $Inspector.Path manifest application-id $Apk.FullName 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    return (($result -join [Environment]::NewLine).Trim() -eq $PackageName)
}

function Find-ApkCandidates {
    $priority = @(
        (Join-Path $Root "lefant.apk"),
        (Join-Path $Root "apk\lefant.apk")
    )
    $exact = @($priority | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { Get-Item -LiteralPath $_ })
    $inspector = Find-ApkInspector
    if (-not $inspector) {
        Write-Warning "No se encontró aapt ni apkanalyzer; no se instalará ningún APK sin validar su package."
        return @()
    }
    if ($exact.Count -gt 0) {
        # La prioridad exacta se respeta en este orden; no se pasa a comodines.
        foreach ($candidate in $exact) {
            if (Test-ApkIsLefant $candidate $inspector) { return @($candidate) }
        }
        return @()
    }
    $rawCandidates = @()
    foreach ($folder in @($Root, (Join-Path $Root "apk"))) {
        if (Test-Path -LiteralPath $folder -PathType Container) {
            $rawCandidates += Get-ChildItem -LiteralPath $folder -File -Filter "*.apk" | Where-Object {
                $_.Name -notin @("lefant-key-poc-debug.apk", "app-debug.apk") -and
                $_.Name -notlike "*keyextractor*.apk" -and $_.Name -notlike "*poc*.apk"
            }
        }
    }
    return @($rawCandidates | Sort-Object FullName -Unique | Where-Object { Test-ApkIsLefant $_ $inspector })
}

function Select-Apk([System.IO.FileInfo[]]$Candidates) {
    if ($Candidates.Count -eq 1) { return $Candidates[0] }
    Write-Host "Se encontraron varios APK candidatos; no se seleccionará ninguno automáticamente:"
    for ($i = 0; $i -lt $Candidates.Count; $i++) { Write-Host "  $($i + 1). $($Candidates[$i].FullName)" }
    while ($true) {
        $answer = Read-Host "Indica el número del APK que quieres instalar (o Q para cancelar)"
        if ($answer -match '^[Qq]$') { Stop-Launcher "Instalación cancelada por el usuario." }
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Candidates.Count) {
            return $Candidates[$number - 1]
        }
        Write-Warning "Selecciona un número entre 1 y $($Candidates.Count), o Q."
    }
}

function Install-LefantApk([System.IO.FileInfo]$Apk) {
    $splits = @(Get-ChildItem -LiteralPath $Apk.DirectoryName -File -Filter "split_config*.apk" | Sort-Object Name)
    if ($splits.Count -gt 0) {
        $files = @($Apk) + $splits
        Write-Host "APK Lefant con splits detectado"
        $files | ForEach-Object { Write-Host "  $($_.FullName)" }
        $result = & $script:AdbPath -s $script:TargetSerial install-multiple -r $files.FullName 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "adb install-multiple -r falló: $($result -join [Environment]::NewLine)"
        }
        ($result -join [Environment]::NewLine) | Write-Host
        return
    }

    $result = & $script:AdbPath -s $script:TargetSerial install -r $Apk.FullName 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($result -join [Environment]::NewLine).Trim()
    if ($exitCode -eq 0) {
        $text | Write-Host
        return
    }
    # Si aparecen splits entre el primer intento y el fallo, reintenta con ellos.
    $retrySplits = @(Get-ChildItem -LiteralPath $Apk.DirectoryName -File -Filter "split_config*.apk" | Sort-Object Name)
    if ($text -match "INSTALL_FAILED_MISSING_SPLIT" -and $retrySplits.Count -gt 0) {
        $files = @($Apk) + $retrySplits
        Write-Host "APK Lefant con splits detectado"
        $files | ForEach-Object { Write-Host "  $($_.FullName)" }
        $result = & $script:AdbPath -s $script:TargetSerial install-multiple -r $files.FullName 2>&1
        if ($LASTEXITCODE -eq 0) {
            ($result -join [Environment]::NewLine) | Write-Host
            return
        }
        throw "adb install-multiple -r falló: $($result -join [Environment]::NewLine)"
    }
    throw "adb install -r falló: $text"
}

function Install-LefantIfNeeded {
    if (Test-LefantInstalled) {
        Write-Host "Lefant ya está instalada; no se reinstalará."
        return
    }
    $candidates = @(Find-ApkCandidates)
    if ($candidates.Count -eq 0) {
        Write-Host "No se encontró una APK oficial de Lefant."
        Write-Host "Coloca lefant.apk junto al launcher o en .\apk\lefant.apk,"
        Write-Host "o instala Lefant manualmente en el emulador."
        Read-Host "Cuando la hayas instalado, pulsa ENTER para volver a comprobar" | Out-Null
        if (-not (Test-LefantInstalled)) {
            Stop-Launcher "Lefant sigue sin estar instalada (se esperaba $PackageName). No se puede continuar."
        }
        return
    }
    $apk = Select-Apk $candidates
    Write-Host "APK encontrado: $($apk.FullName)"
    Write-Host "Instalando Lefant..."
    Install-LefantApk $apk
    if (-not (Test-LefantInstalled)) {
        Stop-Launcher "El APK instalado no corresponde a $PackageName. No se continuará."
    }
}

try {
    $script:AdbPath = Find-Adb $Adb
    $script:TargetSerial = Select-OrStartEmulator
    Write-Host "Dispositivo ADB: $TargetSerial"
    Install-LefantIfNeeded
    $version = Get-LefantVersion
    Write-Host "Lefant detectada: versionName=$($version.Name), versionCode=$($version.Code)"
    $normalizedVersion = $version.Name.Trim() -replace '^[vV]', ''
    if ($normalizedVersion -ne $ValidatedVersion) {
        Write-Warning "Versión no validada. Puede funcionar, pero fue probada con 3.3.25."
    }

    Write-Host "Abriendo Lefant oficial..."
    # monkey escribe su diagnóstico normal por stderr. Se captura, pero nunca
    # se interpreta: únicamente su código de salida determina el resultado.
    $savedErrorAction = $ErrorActionPreference
    $nativePreferenceSupported = $PSVersionTable.PSVersion.Major -ge 7
    if ($nativePreferenceSupported) { $savedNativeErrorAction = $PSNativeCommandUseErrorActionPreference }
    try {
        $ErrorActionPreference = "Continue"
        if ($nativePreferenceSupported) { $PSNativeCommandUseErrorActionPreference = $false }
        $monkeyOutput = & $script:AdbPath -s $script:TargetSerial shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 2>&1
        $monkeyCode = $LASTEXITCODE
        if ($monkeyCode -ne 0) {
            throw "No se pudo abrir Lefant con monkey (exit code $monkeyCode): $($monkeyOutput -join [Environment]::NewLine)"
        }

        $appPid = ""
        for ($attempt = 0; $attempt -lt 2 -and -not $appPid; $attempt++) {
            if ($attempt -gt 0) { Start-Sleep -Seconds 2 }
            $pidOutput = & $script:AdbPath -s $script:TargetSerial shell pidof $PackageName 2>&1
            $appPid = ($pidOutput -join " ").Trim()
        }
        if (-not $appPid) {
            throw "monkey terminó correctamente, pero $PackageName no tiene proceso activo."
        }
    } finally {
        $ErrorActionPreference = $savedErrorAction
        if ($nativePreferenceSupported) { $PSNativeCommandUseErrorActionPreference = $savedNativeErrorAction }
    }
    Write-Host "Inicia sesión manualmente si hace falta y espera a que cargue la lista de tus dispositivos."
    Read-Host "Cuando esté lista, pulsa ENTER para exportar" | Out-Null

    $python = Find-PythonExecutable
    Ensure-FridaServer $python
    $extractor = Join-Path $Root "lefant_devicebean_export.py"
    $arguments = @($extractor, "--adb", $script:AdbPath, "--serial", $script:TargetSerial, "--output", $Output)
    if ($FridaAddress) { $arguments += @("--frida-address", $FridaAddress) }
    if ($ShowKey) { $arguments += "--show-key" }
    & $python @arguments
    exit $LASTEXITCODE
} catch {
    Stop-Launcher $_.Exception.Message
}
