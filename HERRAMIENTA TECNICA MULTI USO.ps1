<#
================================================================================
 MULTI HERRAMIENTA TECNICA - PowerShell
 Version 2.0.0
 Autor original: BMA  |  Refactor: interfaz + auto-actualizacion remota
================================================================================
 USO
   powershell -ExecutionPolicy Bypass -File .\herramienta_tecnica.ps1
   (click derecho > "Ejecutar con PowerShell" o mejor: como Administrador)

 PARAMETROS
   -SkipUpdateCheck   No consulta el servidor de actualizaciones al arrancar
   -UpdatedRestart    Uso interno: indica que venimos de una actualizacion

 ACTUALIZACION REMOTA
   Ver la seccion CONFIGURACION y la opcion [20] del menu.
================================================================================
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$SkipUpdateCheck,
    [switch]$UpdatedRestart
)

# ==============================================================================
# CONFIGURACION
# ==============================================================================

# Version de ESTE archivo. Subela cada vez que publiques cambios.
$script:Version = '2.0.0'

$script:Config = [ordered]@{
    # URL del manifiesto JSON (raw). Ejemplo GitHub:
    # https://raw.githubusercontent.com/USUARIO/REPO/main/version.json
    UpdateManifestUrl = ''

    # Consultar actualizaciones automaticamente al iniciar
    AutoCheck         = $true

    # Segundos maximos de espera al consultar el manifiesto
    TimeoutSec        = 6

    # Exigir que el hash SHA256 del manifiesto coincida con el archivo bajado.
    # Dejalo en $true: es lo que evita que te inyecten un script modificado.
    RequireHash       = $true
}

# Cuando corre como .ps1, $PSCommandPath y $PSScriptRoot estan disponibles.
# Cuando corre como .exe compilado (ps2exe u otro), no siempre lo estan, asi
# que se cae al ejecutable real del proceso en curso.
$script:ExePath = $null
try { $script:ExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { }

$script:SelfPath  = if ($PSCommandPath) { $PSCommandPath } else { $script:ExePath }
$script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot }
                    elseif ($script:SelfPath) { Split-Path $script:SelfPath -Parent }
                    else { (Get-Location).Path }

$script:Paths = @{
    Self      = $script:SelfPath
    Dir       = $script:ScriptDir
    ConfigFile= ''
    LogFile   = ''
}
$script:Paths.ConfigFile = Join-Path $script:Paths.Dir 'herramienta.config.json'

$script:Ctx = @{
    Computer   = $env:COMPUTERNAME
    User       = $env:USERNAME
    Fecha      = (Get-Date -Format 'yyyy-MM-dd')
    Hora       = (Get-Date -Format 'HH-mm-ss')
    IsAdmin    = $false
    PSVersion  = $PSVersionTable.PSVersion.ToString()
    Update     = $null          # manifiesto si hay version nueva
    OrigColors = @{ FG = $Host.UI.RawUI.ForegroundColor; BG = $Host.UI.RawUI.BackgroundColor }
}
$script:Paths.LogFile = Join-Path $script:Paths.Dir ("diagnostico_{0}_{1}.txt" -f $script:Ctx.Fecha, $script:Ctx.Hora)

# Paleta
$script:T = @{
    Accent = 'Cyan'
    Title  = 'White'
    Dim    = 'DarkGray'
    Ok     = 'Green'
    Warn   = 'Yellow'
    Err    = 'Red'
    Key    = 'Gray'
    Val    = 'White'
    Num    = 'DarkCyan'
}

# Caracteres de dibujo por codigo, para no depender de la codificacion del archivo
$script:B = @{
    H  = [char]0x2500; V  = [char]0x2502
    TL = [char]0x256D; TR = [char]0x256E; BL = [char]0x2570; BR = [char]0x256F
    LT = [char]0x251C; RT = [char]0x2524
    Full = [char]0x2588; Light = [char]0x2591
    Dot  = [char]0x00B7; Arrow = [char]0x00BB
}

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$script:Width = 78

# ==============================================================================
# INFRAESTRUCTURA DE UI
# ==============================================================================

function Write-Rule {
    param([ValidateSet('Top','Mid','Bottom','Plain')]$Style = 'Plain', [string]$Label)
    $line = [string]$script:B.H * ($script:Width - 2)
    switch ($Style) {
        'Top'    { Write-Host ("{0}{1}{2}" -f $script:B.TL, $line, $script:B.TR) -ForegroundColor $script:T.Accent }
        'Mid'    { Write-Host ("{0}{1}{2}" -f $script:B.LT, $line, $script:B.RT) -ForegroundColor $script:T.Accent }
        'Bottom' { Write-Host ("{0}{1}{2}" -f $script:B.BL, $line, $script:B.BR) -ForegroundColor $script:T.Accent }
        default  { Write-Host ([string]$script:B.H * $script:Width) -ForegroundColor $script:T.Accent }
    }
}

function Write-BoxLine {
    param([string]$Text = '', [string]$Color = 'White')
    $inner = $script:Width - 4
    if ($Text.Length -gt $inner) { $Text = $Text.Substring(0, $inner - 1) + [char]0x2026 }
    Write-Host ("{0} " -f $script:B.V) -ForegroundColor $script:T.Accent -NoNewline
    Write-Host $Text.PadRight($inner) -ForegroundColor $Color -NoNewline
    Write-Host (" {0}" -f $script:B.V) -ForegroundColor $script:T.Accent
}

function Show-Header {
    param([string]$Subtitle)
    Clear-Host
    Write-Rule -Style Top
    Write-BoxLine ("MULTI HERRAMIENTA TECNICA  v{0}" -f $script:Version) $script:T.Title
    Write-BoxLine "Diagnostico, mantenimiento y reportes de Windows" $script:T.Dim
    Write-Rule -Style Mid

    $admin = if ($script:Ctx.IsAdmin) { 'Administrador' } else { 'Usuario limitado' }
    $adminColor = if ($script:Ctx.IsAdmin) { $script:T.Ok } else { $script:T.Warn }

    Write-Host ("{0} " -f $script:B.V) -ForegroundColor $script:T.Accent -NoNewline
    Write-Host ("Equipo: ") -ForegroundColor $script:T.Key -NoNewline
    Write-Host ($script:Ctx.Computer.PadRight(18)) -ForegroundColor $script:T.Val -NoNewline
    Write-Host ("Usuario: ") -ForegroundColor $script:T.Key -NoNewline
    Write-Host ($script:Ctx.User.PadRight(16)) -ForegroundColor $script:T.Val -NoNewline
    Write-Host ("PS ") -ForegroundColor $script:T.Key -NoNewline
    Write-Host ($script:Ctx.PSVersion.PadRight($script:Width - 4 - 8 - 18 - 9 - 16 - 3)) -ForegroundColor $script:T.Val -NoNewline
    Write-Host (" {0}" -f $script:B.V) -ForegroundColor $script:T.Accent

    Write-Host ("{0} " -f $script:B.V) -ForegroundColor $script:T.Accent -NoNewline
    Write-Host ("Sesion: ") -ForegroundColor $script:T.Key -NoNewline
    Write-Host ($admin.PadRight(18)) -ForegroundColor $adminColor -NoNewline
    $upd = if ($script:Ctx.Update) { ("Actualizacion {0} disponible" -f $script:Ctx.Update.version) } else { 'Al dia' }
    $updColor = if ($script:Ctx.Update) { $script:T.Warn } else { $script:T.Dim }
    Write-Host ("Estado: ") -ForegroundColor $script:T.Key -NoNewline
    Write-Host ($upd.PadRight($script:Width - 4 - 8 - 18 - 8)) -ForegroundColor $updColor -NoNewline
    Write-Host (" {0}" -f $script:B.V) -ForegroundColor $script:T.Accent

    if ($Subtitle) {
        Write-Rule -Style Mid
        Write-BoxLine ("{0} {1}" -f $script:B.Arrow, $Subtitle.ToUpper()) $script:T.Warn
    }
    Write-Rule -Style Bottom
    Write-Host ''
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host ''
    Write-Host ("{0}{0} " -f $script:B.H) -ForegroundColor $script:T.Accent -NoNewline
    Write-Host $Text.ToUpper() -ForegroundColor $script:T.Accent -NoNewline
    $pad = $script:Width - $Text.Length - 4
    if ($pad -lt 1) { $pad = 1 }
    Write-Host (" " + ([string]$script:B.H * $pad)) -ForegroundColor $script:T.Accent
}

function Write-KV {
    param([string]$Key, $Value, [string]$Color)
    if ($null -eq $Value -or "$Value" -eq '') { $Value = 'No disponible' }
    if (-not $Color) { $Color = $script:T.Val }
    Write-Host ("  {0} " -f $script:B.Dot) -ForegroundColor $script:T.Dim -NoNewline
    Write-Host ($Key + ': ').PadRight(26) -ForegroundColor $script:T.Key -NoNewline
    Write-Host $Value -ForegroundColor $Color
}

function Write-Bar {
    param(
        [Parameter(Mandatory)][double]$Percent,
        [string]$Label = '',
        [int]$Size = 30,
        [switch]$InvertColors   # para "% libre": mucho = bueno
    )
    $p = [math]::Max(0, [math]::Min(100, $Percent))
    $filled = [int][math]::Round($Size * $p / 100)
    $color = if ($InvertColors) {
        if ($p -lt 10) { $script:T.Err } elseif ($p -lt 20) { $script:T.Warn } else { $script:T.Ok }
    } else {
        if ($p -gt 90) { $script:T.Err } elseif ($p -gt 75) { $script:T.Warn } else { $script:T.Ok }
    }
    Write-Host ("  " + $Label.PadRight(24)) -ForegroundColor $script:T.Key -NoNewline
    Write-Host ([string]$script:B.Full * $filled) -ForegroundColor $color -NoNewline
    Write-Host ([string]$script:B.Light * ($Size - $filled)) -ForegroundColor $script:T.Dim -NoNewline
    Write-Host ("  {0,6:N2} %" -f $p) -ForegroundColor $color
}

function Write-Status {
    param([Parameter(Mandatory)][string]$Text, [ValidateSet('ok','warn','err','info','work')]$Level = 'info')
    $map = @{
        ok   = @{ s = '[ OK ]'; c = $script:T.Ok }
        warn = @{ s = '[ !  ]'; c = $script:T.Warn }
        err  = @{ s = '[ X  ]'; c = $script:T.Err }
        info = @{ s = '[ i  ]'; c = $script:T.Accent }
        work = @{ s = '[ .. ]'; c = $script:T.Dim }
    }
    Write-Host ("  {0} " -f $map[$Level].s) -ForegroundColor $map[$Level].c -NoNewline
    Write-Host $Text -ForegroundColor $script:T.Val
}

function Wait-Key {
    param([string]$Text = 'Presione cualquier tecla para volver')
    Write-Host ''
    Write-Host ("  {0} {1}..." -f $script:B.Arrow, $Text) -ForegroundColor $script:T.Dim
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { Read-Host | Out-Null }
}

function Read-Choice {
    param([string]$Prompt = 'Opcion')
    Write-Host ''
    Write-Host ("  {0} {1}: " -f $script:B.Arrow, $Prompt) -ForegroundColor $script:T.Accent -NoNewline
    return (Read-Host)
}

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Question)
    Write-Host ''
    Write-Host ("  {0} {1} [S/N]: " -f $script:B.Arrow, $Question) -ForegroundColor $script:T.Warn -NoNewline
    $r = Read-Host
    return ($r -match '^[SsYy]')
}

function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Assert-Admin {
    if ($script:Ctx.IsAdmin) { return $true }
    Write-Status 'Esta funcion necesita privilegios de Administrador.' 'err'
    Write-Status 'Cierre y vuelva a abrir con "Ejecutar como administrador".' 'info'
    return $false
}

function Get-Cim {
    param([Parameter(Mandatory)][string]$Class, [string]$Namespace = 'root\cimv2', [string]$Filter)
    $p = @{ ClassName = $Class; Namespace = $Namespace; ErrorAction = 'SilentlyContinue' }
    if ($Filter) { $p.Filter = $Filter }
    $r = Get-CimInstance @p
    if (-not $r) { $r = Get-WmiObject -Class $Class -Namespace $Namespace -ErrorAction SilentlyContinue }
    return $r
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path (Join-Path $script:Paths.Dir 'herramienta.log') -Value $line -Encoding UTF8 } catch { }
}

# ==============================================================================
# CONFIGURACION PERSISTENTE
# ==============================================================================

function Import-AppConfig {
    if (-not (Test-Path $script:Paths.ConfigFile)) { return }
    try {
        $j = Get-Content $script:Paths.ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @('UpdateManifestUrl','AutoCheck','TimeoutSec','RequireHash')) {
            if ($null -ne $j.$k) { $script:Config[$k] = $j.$k }
        }
        Write-Log "Configuracion cargada"
    } catch { Write-Log "No se pudo leer la configuracion: $_" 'WARN' }
}

function Export-AppConfig {
    try {
        [pscustomobject]$script:Config | ConvertTo-Json -Depth 4 |
            Out-File -FilePath $script:Paths.ConfigFile -Encoding UTF8 -Force
        return $true
    } catch { Write-Status "No se pudo guardar la configuracion: $_" 'err'; return $false }
}

# ==============================================================================
# ACTUALIZACION REMOTA
# ==============================================================================
<#
  Como funciona
  -------------
  1. El script consulta un manifiesto JSON publicado en una URL (GitHub raw,
     un bucket S3, tu propio servidor... cualquier cosa que sirva un archivo
     estatico por HTTPS).

     version.json:
     {
       "version":   "2.1.0",
       "url":       "https://raw.githubusercontent.com/USER/REPO/main/herramienta_tecnica.ps1",
       "sha256":    "A1B2C3...",
       "notes":     "Se agrego monitoreo de SMART",
       "mandatory": false,
       "minVersion":"2.0.0"
     }

  2. Compara la version del manifiesto con la propia. Si es mayor, avisa.
  3. Al aceptar: descarga el .ps1 a un temporal, verifica SHA256, respalda el
     archivo actual y lanza un proceso auxiliar que espera a que este proceso
     termine, reemplaza el archivo y vuelve a abrir la herramienta.

  Para publicar una version nueva usa la opcion [20] > "Generar manifiesto":
  calcula el hash y te deja el version.json listo para subir.

  Nota de seguridad: la verificacion de hash solo protege contra corrupcion o
  contra que alguien altere el .ps1 sin poder tocar el manifiesto. Si controlas
  ambos desde el mismo repositorio, lo que realmente te protege es HTTPS mas el
  control de acceso de ese repositorio. Para algo mas serio, firma el script
  con un certificado de Authenticode y valida con Get-AuthenticodeSignature.
#>

function Initialize-Tls {
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
}

function Get-UpdateManifest {
    param([int]$TimeoutSec = 0)
    if ([string]::IsNullOrWhiteSpace($script:Config.UpdateManifestUrl)) { return $null }
    if ($TimeoutSec -le 0) { $TimeoutSec = [int]$script:Config.TimeoutSec }
    Initialize-Tls
    try {
        $m = Invoke-RestMethod -Uri $script:Config.UpdateManifestUrl `
                               -TimeoutSec $TimeoutSec `
                               -Headers @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' } `
                               -UseBasicParsing -ErrorAction Stop
        if (-not $m.version -or -not $m.url) { Write-Log 'Manifiesto incompleto' 'WARN'; return $null }
        return $m
    } catch {
        Write-Log "Fallo la consulta de actualizaciones: $_" 'WARN'
        return $null
    }
}

function Test-NewerVersion {
    param([Parameter(Mandatory)]$Manifest)
    try {
        return ([version]$Manifest.version -gt [version]$script:Version)
    } catch { return $false }
}

function Invoke-UpdateCheck {
    param([switch]$Quiet)
    if (-not $Quiet) { Write-Status 'Consultando servidor de actualizaciones...' 'work' }
    $m = Get-UpdateManifest
    if (-not $m) {
        if (-not $Quiet) {
            if ([string]::IsNullOrWhiteSpace($script:Config.UpdateManifestUrl)) {
                Write-Status 'No hay URL de actualizaciones configurada (opcion 31).' 'warn'
            } else {
                Write-Status 'No se pudo contactar el servidor.' 'err'
            }
        }
        return $null
    }
    if (Test-NewerVersion $m) {
        $script:Ctx.Update = $m
        if (-not $Quiet) { Write-Status ("Version {0} disponible (actual {1})" -f $m.version, $script:Version) 'warn' }
        return $m
    }
    $script:Ctx.Update = $null
    if (-not $Quiet) { Write-Status ("Ya tiene la ultima version ({0})" -f $script:Version) 'ok' }
    return $null
}

function Install-Update {
    param([Parameter(Mandatory)]$Manifest)

    if ([string]::IsNullOrWhiteSpace($script:Paths.Self)) {
        Write-Status 'No se puede autoactualizar: el script no se ejecuta desde un archivo.' 'err'
        return $false
    }

    # La extension del destino manda: si el manifiesto sirve un .exe, se valida
    # y se relanza como .exe; si sirve un .ps1, como script de PowerShell.
    $ext = [System.IO.Path]::GetExtension($Manifest.url)
    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = [System.IO.Path]::GetExtension($script:Paths.Self) }
    if ([string]::IsNullOrWhiteSpace($ext)) { $ext = '.ps1' }

    $tmp = Join-Path $env:TEMP ("ht_update_{0}{1}" -f ([guid]::NewGuid().ToString('N')), $ext)
    Initialize-Tls

    Write-Status ("Descargando version {0}..." -f $Manifest.version) 'work'
    try {
        Invoke-WebRequest -Uri $Manifest.url -OutFile $tmp -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Status "Fallo la descarga: $_" 'err'
        return $false
    }

    $size = (Get-Item $tmp).Length
    if ($size -lt 1024) {
        Write-Status "El archivo descargado es sospechosamente pequeno ($size bytes). Se aborta." 'err'
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return $false
    }
    Write-Status ("Descargado: {0:N1} KB" -f ($size / 1KB)) 'ok'

    # Verificacion de integridad
    if ($Manifest.sha256) {
        $hash = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash
        if ($hash -ne ($Manifest.sha256 -replace '\s','').ToUpper()) {
            Write-Status 'El hash SHA256 NO coincide. Actualizacion abortada.' 'err'
            Write-KV 'Esperado' $Manifest.sha256 $script:T.Dim
            Write-KV 'Obtenido' $hash $script:T.Dim
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            return $false
        }
        Write-Status 'Hash SHA256 verificado.' 'ok'
    } elseif ($script:Config.RequireHash) {
        Write-Status 'El manifiesto no trae sha256 y RequireHash esta activo. Abortado.' 'err'
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return $false
    }

    # Sanity check: valida segun el tipo de archivo descargado
    $valid = $false
    if ($ext -ieq '.ps1') {
        try {
            $null = [scriptblock]::Create((Get-Content $tmp -Raw -Encoding UTF8))
            $valid = $true
            Write-Status 'Sintaxis del script validada.' 'ok'
        } catch {
            Write-Status 'El archivo descargado no es un script de PowerShell valido.' 'err'
        }
    } elseif ($ext -ieq '.exe') {
        try {
            $fs = [System.IO.File]::OpenRead($tmp)
            $buf = New-Object byte[] 2
            [void]$fs.Read($buf, 0, 2)
            $fs.Close()
            if ($buf[0] -eq 0x4D -and $buf[1] -eq 0x5A) {   # cabecera 'MZ' de un .exe de Windows
                $valid = $true
                Write-Status 'Cabecera de ejecutable (.exe) valida.' 'ok'
            } else {
                Write-Status 'El archivo descargado no tiene cabecera de ejecutable valida.' 'err'
            }
        } catch { Write-Status "No se pudo inspeccionar el archivo: $_" 'err' }
    } else {
        # Extension desconocida: nos quedamos solo con la verificacion de hash de arriba
        $valid = $true
    }
    if (-not $valid) {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return $false
    }

    # Respaldo
    $backupDir = Join-Path $script:Paths.Dir 'backup'
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $selfExt = [System.IO.Path]::GetExtension($script:Paths.Self)
    $backup = Join-Path $backupDir ("herramienta_tecnica_v{0}_{1}{2}" -f $script:Version, (Get-Date -Format 'yyyyMMdd-HHmmss'), $selfExt)
    try {
        Copy-Item $script:Paths.Self $backup -Force
        Write-Status ("Respaldo guardado en backup\{0}" -f (Split-Path $backup -Leaf)) 'ok'
    } catch {
        Write-Status "No se pudo respaldar el archivo actual: $_" 'warn'
        if (-not (Confirm-Action 'Continuar sin respaldo?')) { return $false }
    }

    # Proceso auxiliar: espera a que este PID muera, reemplaza y relanza.
    # El helper decide en tiempo de ejecucion si el destino es .exe o .ps1.
    $helper = Join-Path $env:TEMP ("ht_swap_{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
    $helperCode = @'
param([int]$TargetPid, [string]$Src, [string]$Dst)
try { Wait-Process -Id $TargetPid -Timeout 60 -ErrorAction SilentlyContinue } catch { }
Start-Sleep -Milliseconds 700
for ($i = 0; $i -lt 10; $i++) {
    try { Copy-Item -LiteralPath $Src -Destination $Dst -Force; break }
    catch { Start-Sleep -Milliseconds 800 }
}
Remove-Item -LiteralPath $Src -Force -ErrorAction SilentlyContinue
if ($Dst -match '\.exe$') {
    Start-Process -FilePath $Dst -ArgumentList @('-SkipUpdateCheck','-UpdatedRestart')
} else {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$Dst`"",'-SkipUpdateCheck','-UpdatedRestart')
}
Start-Sleep -Seconds 2
Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
'@
    Set-Content -Path $helper -Value $helperCode -Encoding UTF8

    Write-Host ''
    Write-Status 'Reiniciando la herramienta con la version nueva...' 'info'
    Start-Sleep -Seconds 2

    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$helper`"",
        '-TargetPid', $PID, '-Src', "`"$tmp`"", '-Dst', "`"$($script:Paths.Self)`""
    )
    Write-Log ("Actualizando de {0} a {1}" -f $script:Version, $Manifest.version)
    exit 0
}

function Show-UpdateScreen {
    while ($true) {
        Show-Header 'Actualizaciones'
        Write-KV 'Version instalada' $script:Version
        Write-KV 'URL del manifiesto' $(if ($script:Config.UpdateManifestUrl) { $script:Config.UpdateManifestUrl } else { '(sin configurar)' })
        Write-KV 'Chequeo automatico' $(if ($script:Config.AutoCheck) { 'Activado' } else { 'Desactivado' })

        Write-Section 'Estado'
        $m = Invoke-UpdateCheck

        if ($m) {
            Write-Section ("Version {0}" -f $m.version)
            if ($m.notes)     { Write-KV 'Cambios' $m.notes $script:T.Warn }
            if ($m.mandatory) { Write-Status 'El autor marco esta actualizacion como obligatoria.' 'warn' }
            Write-KV 'Origen' $m.url $script:T.Dim
            if ($m.sha256)    { Write-KV 'SHA256' $m.sha256 $script:T.Dim }

            Write-Host ''
            Write-Host '  [1] Instalar ahora' -ForegroundColor $script:T.Val
            Write-Host '  [2] Recordarme luego' -ForegroundColor $script:T.Val
            Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim
            switch (Read-Choice) {
                '1' { if (Install-Update $m) { return } else { Wait-Key } }
                '2' { return }
                '0' { return }
                default { }
            }
        } else {
            Write-Host ''
            Write-Host '  [1] Volver a consultar' -ForegroundColor $script:T.Val
            Write-Host '  [0] Volver al menu' -ForegroundColor $script:T.Dim
            $c = Read-Choice
            if ($c -eq '0' -or $c -eq '') { return }
        }
    }
}

function Show-UpdateConfigScreen {
    while ($true) {
        Show-Header 'Configuracion de actualizaciones'
        Write-KV 'URL del manifiesto' $(if ($script:Config.UpdateManifestUrl) { $script:Config.UpdateManifestUrl } else { '(sin configurar)' })
        Write-KV 'Chequeo al iniciar' $(if ($script:Config.AutoCheck) { 'Si' } else { 'No' })
        Write-KV 'Exigir hash SHA256' $(if ($script:Config.RequireHash) { 'Si' } else { 'No' })
        Write-KV 'Timeout (s)' $script:Config.TimeoutSec
        Write-KV 'Archivo de config' $script:Paths.ConfigFile $script:T.Dim

        Write-Section 'Opciones'
        Write-Host '  [1] Cambiar URL del manifiesto'            -ForegroundColor $script:T.Val
        Write-Host '  [2] Activar/desactivar chequeo automatico' -ForegroundColor $script:T.Val
        Write-Host '  [3] Activar/desactivar exigencia de hash'  -ForegroundColor $script:T.Val
        Write-Host '  [4] Probar conexion con el servidor'       -ForegroundColor $script:T.Val
        Write-Host '  [5] Generar manifiesto (para publicar)'    -ForegroundColor $script:T.Val
        Write-Host '  [6] Restaurar una version de respaldo'     -ForegroundColor $script:T.Val
        Write-Host '  [0] Volver'                                -ForegroundColor $script:T.Dim

        switch (Read-Choice) {
            '1' {
                Write-Host ''
                Write-Host '  Pegue la URL raw del version.json (vacio = desactivar):' -ForegroundColor $script:T.Key
                $u = Read-Choice 'URL'
                if ($u -eq '' -or $u -match '^https://') {
                    $script:Config.UpdateManifestUrl = $u.Trim()
                    if (Export-AppConfig) { Write-Status 'Guardado.' 'ok' }
                } else {
                    Write-Status 'Solo se aceptan URLs https://' 'err'
                }
                Wait-Key
            }
            '2' {
                $script:Config.AutoCheck = -not $script:Config.AutoCheck
                Export-AppConfig | Out-Null
                Write-Status ("Chequeo automatico: {0}" -f $(if ($script:Config.AutoCheck) { 'activado' } else { 'desactivado' })) 'ok'
                Wait-Key
            }
            '3' {
                $script:Config.RequireHash = -not $script:Config.RequireHash
                Export-AppConfig | Out-Null
                if (-not $script:Config.RequireHash) {
                    Write-Status 'Cuidado: sin verificacion de hash aceptara cualquier archivo que sirva esa URL.' 'warn'
                }
                Wait-Key
            }
            '4' {
                Write-Host ''
                $m = Get-UpdateManifest
                if ($m) {
                    Write-Status 'Manifiesto recibido correctamente.' 'ok'
                    Write-KV 'version'   $m.version
                    Write-KV 'url'       $m.url
                    Write-KV 'sha256'    $m.sha256 $script:T.Dim
                    Write-KV 'notes'     $m.notes
                    Write-KV 'mandatory' $m.mandatory
                } else {
                    Write-Status 'Sin respuesta valida. Revise la URL y la conexion.' 'err'
                }
                Wait-Key
            }
            '5' { New-UpdateManifest; Wait-Key }
            '6' { Restore-Backup; Wait-Key }
            '0' { return }
            ''  { return }
            default { }
        }
    }
}

function New-UpdateManifest {
    Write-Section 'Generar manifiesto de publicacion'
    Write-Host '  Calcula el hash del .ps1 y escribe el version.json que debe subir' -ForegroundColor $script:T.Dim
    Write-Host '  junto al script para que las otras PCs reciban la actualizacion.' -ForegroundColor $script:T.Dim

    $src = Read-Choice ("Ruta del .ps1 a publicar (Enter = {0})" -f (Split-Path $script:Paths.Self -Leaf))
    if ([string]::IsNullOrWhiteSpace($src)) { $src = $script:Paths.Self }
    $src = $src.Trim('"')
    if (-not (Test-Path $src)) { Write-Status 'No existe ese archivo.' 'err'; return }

    # Lee la version declarada dentro del script
    $ver = '0.0.0'
    try {
        $mm = [regex]::Match((Get-Content $src -Raw), "script:Version\s*=\s*'([^']+)'")
        if ($mm.Success) { $ver = $mm.Groups[1].Value }
    } catch { }

    $verIn = Read-Choice ("Version a publicar (Enter = {0})" -f $ver)
    if ($verIn) { $ver = $verIn.Trim() }
    try { $null = [version]$ver } catch { Write-Status 'Formato de version invalido (use X.Y.Z).' 'err'; return }

    $url = Read-Choice 'URL raw del .ps1 publicado'
    if ($url -notmatch '^https://') { Write-Status 'Se requiere una URL https.' 'err'; return }

    $notes = Read-Choice 'Notas del cambio'
    $mand  = Confirm-Action 'Marcar como obligatoria?'

    $hash = (Get-FileHash -Path $src -Algorithm SHA256).Hash

    $manifest = [ordered]@{
        version    = $ver
        url        = $url.Trim()
        sha256     = $hash
        notes      = $notes
        mandatory  = [bool]$mand
        publishedAt= (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')
    }

    $out = Join-Path (Split-Path $src -Parent) 'version.json'
    try {
        [pscustomobject]$manifest | ConvertTo-Json -Depth 4 | Out-File $out -Encoding UTF8 -Force
        Write-Host ''
        Write-Status 'Manifiesto generado.' 'ok'
        Write-KV 'Archivo' $out
        Write-KV 'SHA256'  $hash $script:T.Dim
        Write-Host ''
        Write-Host '  Siguiente paso: suba el .ps1 y el version.json a su repositorio.' -ForegroundColor $script:T.Key
        Write-Host '  Las PCs con la herramienta lo detectaran al iniciar.' -ForegroundColor $script:T.Key
    } catch {
        Write-Status "No se pudo escribir el manifiesto: $_" 'err'
    }
}

function Restore-Backup {
    Write-Section 'Restaurar version anterior'
    $dir = Join-Path $script:Paths.Dir 'backup'
    if (-not (Test-Path $dir)) { Write-Status 'No hay respaldos.' 'warn'; return }
    $selfExt = [System.IO.Path]::GetExtension($script:Paths.Self)
    if ([string]::IsNullOrWhiteSpace($selfExt)) { $selfExt = '.ps1' }
    $files = Get-ChildItem $dir -Filter ("*{0}" -f $selfExt) | Sort-Object LastWriteTime -Descending
    if (-not $files) { Write-Status 'No hay respaldos.' 'warn'; return }

    $i = 1
    foreach ($f in $files) {
        Write-Host ("  [{0}] {1}  ({2:dd/MM/yyyy HH:mm})" -f $i, $f.Name, $f.LastWriteTime) -ForegroundColor $script:T.Val
        $i++
    }
    $sel = Read-Choice 'Numero a restaurar (0 = cancelar)'
    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $files.Count) { return }
    $pick = $files[[int]$sel - 1]
    if (-not (Confirm-Action ("Reemplazar el archivo actual por {0}?" -f $pick.Name))) { return }
    try {
        Copy-Item $script:Paths.Self (Join-Path $dir ("pre-restore_{0}{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $selfExt)) -Force
        Copy-Item $pick.FullName $script:Paths.Self -Force
        Write-Status 'Restaurado. Cierre y vuelva a abrir la herramienta.' 'ok'
    } catch { Write-Status "Error al restaurar: $_" 'err' }
}

# ==============================================================================
# [01] DIAGNOSTICO GENERAL A TXT
# ==============================================================================

function Get-FullDiagnostic {
    Show-Header 'Diagnostico general'
    Write-Status 'Recopilando informacion. Esto puede tardar un minuto...' 'work'

    $sb = New-Object System.Text.StringBuilder
    $add = { param($t) [void]$sb.AppendLine($t) }

    & $add ('=' * 70)
    & $add 'DIAGNOSTICO COMPLETO DEL SISTEMA'
    & $add ("Herramienta : v{0}" -f $script:Version)
    & $add ("Equipo      : {0}" -f $script:Ctx.Computer)
    & $add ("Usuario     : {0}" -f $script:Ctx.User)
    & $add ("Fecha       : {0}" -f (Get-Date))
    & $add ("Admin       : {0}" -f $script:Ctx.IsAdmin)
    & $add ('=' * 70)

    Write-Status 'Sistema operativo...' 'work'
    $os = Get-Cim Win32_OperatingSystem
    & $add "`n=== SISTEMA OPERATIVO ==="
    & $add ("Nombre       : {0}" -f $os.Caption)
    & $add ("Version      : {0} (build {1})" -f $os.Version, $os.BuildNumber)
    & $add ("Arquitectura : {0}" -f $os.OSArchitecture)
    & $add ("Instalado    : {0}" -f $os.InstallDate)
    & $add ("Ultimo inicio: {0}" -f $os.LastBootUpTime)

    Write-Status 'Hardware...' 'work'
    $cpu = Get-Cim Win32_Processor | Select-Object -First 1
    $cs  = Get-Cim Win32_ComputerSystem
    $bb  = Get-Cim Win32_BaseBoard
    $bios= Get-Cim Win32_BIOS

    & $add "`n=== HARDWARE ==="
    & $add ("[CPU] {0}" -f $cpu.Name)
    & $add ("  Nucleos/Hilos: {0}/{1}   Max: {2} MHz" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors, $cpu.MaxClockSpeed)
    & $add ("[Placa] {0} {1}  S/N: {2}" -f $bb.Manufacturer, $bb.Product, $bb.SerialNumber)
    & $add ("[BIOS] {0} {1}" -f $bios.Manufacturer, $bios.SMBIOSBIOSVersion)
    & $add ("[Equipo] {0} {1}" -f $cs.Manufacturer, $cs.Model)

    $totalRAM = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $freeRAM  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    & $add "`n[RAM]"
    & $add ("  Total: {0} GB   Libre: {1} GB   En uso: {2} GB" -f $totalRAM, $freeRAM, [math]::Round($totalRAM - $freeRAM, 2))
    foreach ($m in (Get-Cim Win32_PhysicalMemory)) {
        & $add ("  {0}: {1} GB @ {2} MHz  {3} {4}" -f $m.BankLabel, [math]::Round($m.Capacity/1GB,2), $m.Speed, $m.Manufacturer, $m.PartNumber)
    }

    Write-Status 'Discos...' 'work'
    & $add "`n=== ALMACENAMIENTO ==="
    foreach ($d in (Get-Cim Win32_LogicalDisk -Filter 'DriveType=3')) {
        $pl = if ($d.Size) { [math]::Round(($d.FreeSpace / $d.Size) * 100, 2) } else { 0 }
        & $add ("{0} {1}" -f $d.DeviceID, $d.VolumeName)
        & $add ("  Total: {0} GB  Libre: {1} GB  ({2}% libre)" -f [math]::Round($d.Size/1GB,2), [math]::Round($d.FreeSpace/1GB,2), $pl)
    }
    foreach ($pd in (Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
        & $add ("[Fisico] {0}  {1}  {2} GB  Salud: {3}" -f $pd.FriendlyName, $pd.MediaType, [math]::Round($pd.Size/1GB,0), $pd.HealthStatus)
    }

    Write-Status 'Red...' 'work'
    & $add "`n=== RED ==="
    foreach ($a in (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')) {
        & $add ("[{0}] {1}" -f $a.Name, $a.InterfaceDescription)
        & $add ("  MAC: {0}   Velocidad: {1}" -f $a.MacAddress, $a.LinkSpeed)
        $c = Get-NetIPConfiguration -InterfaceAlias $a.Name -ErrorAction SilentlyContinue
        if ($c) {
            & $add ("  IPv4: {0}" -f ($c.IPv4Address.IPAddress -join ', '))
            & $add ("  Gateway: {0}" -f $c.IPv4DefaultGateway.NextHop)
            & $add ("  DNS: {0}" -f ($c.DNSServer.ServerAddresses -join ', '))
        }
    }

    Write-Status 'Programas instalados...' 'work'
    $programas = Get-InstalledProgramList
    & $add ("`n=== PROGRAMAS INSTALADOS ({0}) ===" -f $programas.Count)
    foreach ($p in $programas) {
        & $add ("- {0}  v{1}  [{2}]" -f $p.DisplayName, $p.DisplayVersion, $p.Publisher)
    }

    Write-Status 'Errores recientes del sistema...' 'work'
    & $add "`n=== ERRORES DEL SISTEMA (72 h) ==="
    $ev = Get-WinEvent -FilterHashtable @{ LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-72) } -MaxEvents 40 -ErrorAction SilentlyContinue
    if ($ev) {
        foreach ($e in $ev) {
            & $add ("{0:dd/MM HH:mm} [{1}] {2}" -f $e.TimeCreated, $e.Id, ($e.Message -split "`r?`n")[0])
        }
    } else { & $add 'Sin errores registrados o sin permisos.' }

    try {
        $sb.ToString() | Out-File -FilePath $script:Paths.LogFile -Encoding UTF8 -Force
        Write-Host ''
        Write-Status 'Informe generado.' 'ok'
        Write-KV 'Archivo' $script:Paths.LogFile
        Write-KV 'Tamano' ("{0:N1} KB" -f ((Get-Item $script:Paths.LogFile).Length / 1KB))
        if (Confirm-Action 'Abrir el informe?') { Start-Process notepad.exe $script:Paths.LogFile }
    } catch {
        Write-Status "No se pudo guardar el informe: $_" 'err'
    }
    Wait-Key
}

# ==============================================================================
# [02] SISTEMA
# ==============================================================================

function Get-SystemInfoScreen {
    Show-Header 'Informacion del sistema'
    $os = Get-Cim Win32_OperatingSystem
    $cs = Get-Cim Win32_ComputerSystem

    Write-Section 'Sistema operativo'
    Write-KV 'Nombre'        $os.Caption
    Write-KV 'Version'       ("{0} (build {1})" -f $os.Version, $os.BuildNumber)
    Write-KV 'Arquitectura'  $os.OSArchitecture
    Write-KV 'Instalacion'   $os.InstallDate
    Write-KV 'Serie'         $os.SerialNumber
    Write-KV 'Idioma'        (Get-Culture).DisplayName

    Write-Section 'Equipo'
    Write-KV 'Fabricante'    $cs.Manufacturer
    Write-KV 'Modelo'        $cs.Model
    Write-KV 'Tipo'          $(switch ([int]$cs.PCSystemType) { 1 {'Escritorio'} 2 {'Portatil'} 3 {'Workstation'} 4 {'Servidor'} default {'Desconocido'} })
    Write-KV 'Dominio/Grupo' $cs.Domain
    Write-KV 'Usuario activo' $cs.UserName

    Write-Section 'Tiempo de actividad'
    try {
        $up = (Get-Date) - $os.LastBootUpTime
        Write-KV 'Ultimo inicio' $os.LastBootUpTime
        Write-KV 'Encendido hace' ("{0} dias, {1} h, {2} min" -f $up.Days, $up.Hours, $up.Minutes)
        if ($up.Days -gt 7) { Write-Status 'Lleva mas de una semana sin reiniciar. Considere reiniciar.' 'warn' }
    } catch { }

    Write-Host ''
    if (Confirm-Action 'Ver la salida completa de systeminfo?') {
        Write-Host ''
        systeminfo | Out-Host
    }
    Wait-Key
}

# ==============================================================================
# [03] RED
# ==============================================================================

function Get-NetworkInfoScreen {
    Show-Header 'Red y conectividad'

    Write-Section 'IP publica'
    try {
        Initialize-Tls
        $pub = Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 5 -ErrorAction Stop
        Write-KV 'Direccion' $pub $script:T.Ok
    } catch { Write-Status 'Sin conexion a Internet o servicio no disponible.' 'warn' }

    Write-Section 'Adaptadores activos'
    $ad = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
    if (-not $ad) { Write-Status 'No hay adaptadores activos.' 'err' }
    foreach ($a in $ad) {
        Write-Host ''
        Write-Host ("  [{0}]" -f $a.Name) -ForegroundColor $script:T.Accent
        Write-KV 'Descripcion' $a.InterfaceDescription
        Write-KV 'MAC'         $a.MacAddress
        Write-KV 'Velocidad'   $a.LinkSpeed
        $c = Get-NetIPConfiguration -InterfaceAlias $a.Name -ErrorAction SilentlyContinue
        if ($c) {
            Write-KV 'IPv4'    ($c.IPv4Address.IPAddress -join ', ') $script:T.Ok
            Write-KV 'Gateway' $c.IPv4DefaultGateway.NextHop
            Write-KV 'DNS'     ($c.DNSServer.ServerAddresses -join ', ')
        }
    }

    Write-Section 'Prueba de conectividad'
    foreach ($t in @(@{n='Gateway';h=(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop},
                     @{n='DNS Google';h='8.8.8.8'},
                     @{n='Internet';h='1.1.1.1'})) {
        if (-not $t.h) { continue }
        $r = Test-Connection -ComputerName $t.h -Count 2 -Quiet -ErrorAction SilentlyContinue
        if ($r) {
            $ms = (Test-Connection -ComputerName $t.h -Count 2 -ErrorAction SilentlyContinue | Measure-Object -Property ResponseTime -Average).Average
            Write-Status ("{0} ({1}): responde, {2} ms promedio" -f $t.n, $t.h, [math]::Round($ms,0)) 'ok'
        } else {
            Write-Status ("{0} ({1}): sin respuesta" -f $t.n, $t.h) 'err'
        }
    }

    Write-Host ''
    Write-Host '  [1] Ver conexiones TCP establecidas' -ForegroundColor $script:T.Val
    Write-Host '  [2] Ver tabla de rutas' -ForegroundColor $script:T.Val
    Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim
    switch (Read-Choice) {
        '1' {
            Write-Section 'Conexiones establecidas'
            Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
                Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort,
                    @{n='Proceso';e={ (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName }} |
                Sort-Object Proceso | Format-Table -AutoSize | Out-Host
            Wait-Key
        }
        '2' {
            Write-Section 'Tabla de rutas'
            Get-NetRoute -ErrorAction SilentlyContinue |
                Select-Object DestinationPrefix, NextHop, RouteMetric, InterfaceAlias |
                Format-Table -AutoSize | Out-Host
            Wait-Key
        }
        default { }
    }
}

# ==============================================================================
# [04] DISCOS
# ==============================================================================

function Get-DiskInfoScreen {
    Show-Header 'Almacenamiento'

    Write-Section 'Unidades logicas'
    foreach ($d in (Get-Cim Win32_LogicalDisk -Filter 'DriveType=3')) {
        if (-not $d.Size) { continue }
        $freePct = ($d.FreeSpace / $d.Size) * 100
        $label = if ($d.VolumeName) { "{0} ({1})" -f $d.DeviceID, $d.VolumeName } else { $d.DeviceID }
        Write-Host ''
        Write-Host ("  {0}" -f $label) -ForegroundColor $script:T.Accent
        Write-KV 'Total' ("{0:N2} GB" -f ($d.Size/1GB))
        Write-KV 'Libre' ("{0:N2} GB" -f ($d.FreeSpace/1GB))
        Write-KV 'Sistema de archivos' $d.FileSystem
        Write-Bar $freePct 'Espacio libre' -InvertColors
        if ($freePct -lt 10) { Write-Status 'Espacio critico: libere disco o Windows empezara a fallar.' 'err' }
        elseif ($freePct -lt 20) { Write-Status 'Poco espacio libre.' 'warn' }
    }

    Write-Section 'Discos fisicos y salud'
    $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($pd) {
        foreach ($p in $pd) {
            $color = if ($p.HealthStatus -eq 'Healthy') { $script:T.Ok } else { $script:T.Err }
            Write-Host ''
            Write-Host ("  {0}" -f $p.FriendlyName) -ForegroundColor $script:T.Accent
            Write-KV 'Tipo'   $p.MediaType
            Write-KV 'Tamano' ("{0:N0} GB" -f ($p.Size/1GB))
            Write-KV 'Salud'  $p.HealthStatus $color
            Write-KV 'Estado' ($p.OperationalStatus -join ', ')
            Write-KV 'Bus'    $p.BusType
        }
    } else { Write-Status 'No se pudo consultar Storage Spaces (requiere Windows 8+).' 'warn' }

    Write-Section 'SMART (resumen)'
    try {
        $smart = Get-Cim MSStorageDriver_FailurePredictStatus -Namespace 'root\wmi'
        if ($smart) {
            foreach ($s in $smart) {
                if ($s.PredictFailure) { Write-Status ("{0}: SMART predice FALLO. Respalde ya." -f $s.InstanceName) 'err' }
                else { Write-Status ("{0}: sin prediccion de fallo" -f $s.InstanceName) 'ok' }
            }
        } else { Write-Status 'El controlador no expone datos SMART por WMI.' 'warn' }
    } catch { Write-Status 'SMART no disponible.' 'warn' }

    Wait-Key
}

# ==============================================================================
# [05] RAM
# ==============================================================================

function Get-RAMInfoScreen {
    Show-Header 'Memoria RAM'
    $os = Get-Cim Win32_OperatingSystem
    $cs = Get-Cim Win32_ComputerSystem

    $total = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $free  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $used  = [math]::Round($total - $free, 2)
    $pct   = if ($total -gt 0) { ($used / $total) * 100 } else { 0 }

    Write-Section 'Resumen'
    Write-KV 'Total instalada' ("{0:N2} GB" -f $total)
    Write-KV 'En uso'          ("{0:N2} GB" -f $used)
    Write-KV 'Disponible'      ("{0:N2} GB" -f $free)
    Write-Bar $pct 'Uso de memoria'
    if ($pct -gt 90)      { Write-Status 'Memoria saturada. Cierre aplicaciones o amplie la RAM.' 'err' }
    elseif ($pct -gt 80)  { Write-Status 'Uso de memoria elevado.' 'warn' }

    Write-Section 'Archivo de paginacion'
    foreach ($pf in (Get-Cim Win32_PageFileUsage)) {
        Write-KV $pf.Name ("{0} MB asignados, {1} MB en uso (pico {2} MB)" -f $pf.AllocatedBaseSize, $pf.CurrentUsage, $pf.PeakUsage)
    }

    Write-Section 'Modulos instalados'
    $mods = Get-Cim Win32_PhysicalMemory
    Write-KV 'Ranuras usadas' ("{0} de {1}" -f @($mods).Count, ((Get-Cim Win32_PhysicalMemoryArray).MemoryDevices))
    $mods | Select-Object BankLabel, DeviceLocator,
        @{n='GB';e={[math]::Round($_.Capacity/1GB,2)}}, Speed, Manufacturer, PartNumber |
        Format-Table -AutoSize | Out-Host

    Write-Section 'Top 10 procesos por memoria'
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 |
        Select-Object @{n='Proceso';e={$_.ProcessName}},
                      @{n='MB';e={[math]::Round($_.WorkingSet64/1MB,1)}},
                      @{n='Handles';e={$_.HandleCount}}, Id |
        Format-Table -AutoSize | Out-Host

    Wait-Key
}

# ==============================================================================
# [06] PROGRAMAS
# ==============================================================================

function Get-InstalledProgramList {
    $keys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation |
        Sort-Object DisplayName -Unique
}

function Get-InstalledProgramsScreen {
    $programas = Get-InstalledProgramList
    $page = 0
    $pageSize = 20

    while ($true) {
        Show-Header 'Programas instalados'
        Write-KV 'Total detectado' $programas.Count
        $totalPages = [math]::Max(1, [math]::Ceiling($programas.Count / $pageSize))
        Write-KV 'Pagina' ("{0} de {1}" -f ($page + 1), $totalPages)

        Write-Section 'Listado'
        $programas | Select-Object -Skip ($page * $pageSize) -First $pageSize |
            Select-Object @{n='Programa';e={$_.DisplayName}},
                          @{n='Version';e={$_.DisplayVersion}},
                          @{n='Editor';e={$_.Publisher}} |
            Format-Table -AutoSize | Out-Host

        Write-Host '  [1] Pagina siguiente    [2] Pagina anterior' -ForegroundColor $script:T.Val
        Write-Host '  [3] Buscar              [4] Exportar a CSV' -ForegroundColor $script:T.Val
        Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim

        switch (Read-Choice) {
            '1' { if ($page -lt $totalPages - 1) { $page++ } }
            '2' { if ($page -gt 0) { $page-- } }
            '3' {
                $q = Read-Choice 'Texto a buscar'
                Write-Section ("Resultados para '{0}'" -f $q)
                $hits = $programas | Where-Object { $_.DisplayName -like "*$q*" -or $_.Publisher -like "*$q*" }
                if ($hits) {
                    $hits | Format-Table DisplayName, DisplayVersion, Publisher -AutoSize | Out-Host
                } else { Write-Status 'Sin coincidencias.' 'warn' }
                Wait-Key
            }
            '4' {
                $csv = Join-Path $script:Paths.Dir ("programas_{0}_{1}.csv" -f $script:Ctx.Computer, $script:Ctx.Fecha)
                try {
                    $programas | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
                    Write-Status ("Exportado: {0}" -f $csv) 'ok'
                } catch { Write-Status "Error al exportar: $_" 'err' }
                Wait-Key
            }
            '0' { return }
            ''  { return }
            default { }
        }
    }
}

# ==============================================================================
# [07] HARDWARE  /  [08] BIOS
# ==============================================================================

function Get-HardwareInfoScreen {
    Show-Header 'Hardware'

    Write-Section 'Procesador'
    foreach ($c in (Get-Cim Win32_Processor)) {
        Write-KV 'Modelo'        $c.Name
        Write-KV 'Fabricante'    $c.Manufacturer
        Write-KV 'Nucleos'       $c.NumberOfCores
        Write-KV 'Hilos'         $c.NumberOfLogicalProcessors
        Write-KV 'Frecuencia max' ("{0} MHz" -f $c.MaxClockSpeed)
        Write-KV 'Cache L2/L3'   ("{0} KB / {1} KB" -f $c.L2CacheSize, $c.L3CacheSize)
        Write-KV 'Socket'        $c.SocketDesignation
        if ($c.LoadPercentage -ne $null) { Write-Bar $c.LoadPercentage 'Carga actual' }
    }

    Write-Section 'Placa base'
    $bb = Get-Cim Win32_BaseBoard
    Write-KV 'Fabricante' $bb.Manufacturer
    Write-KV 'Modelo'     $bb.Product
    Write-KV 'Serie'      $bb.SerialNumber

    Write-Section 'Video'
    foreach ($g in (Get-Cim Win32_VideoController)) {
        Write-KV 'GPU'    $g.Name
        Write-KV 'Driver' $g.DriverVersion
    }

    Write-Section 'Perifericos de almacenamiento'
    Get-Cim Win32_DiskDrive | Select-Object Model, InterfaceType,
        @{n='GB';e={[math]::Round($_.Size/1GB,0)}}, SerialNumber |
        Format-Table -AutoSize | Out-Host

    Write-Section 'Audio'
    foreach ($a in (Get-Cim Win32_SoundDevice)) { Write-KV 'Dispositivo' $a.Name }

    Wait-Key
}

function Get-BiosInfoScreen {
    Show-Header 'BIOS / UEFI'
    $bios = Get-Cim Win32_BIOS

    Write-Section 'Firmware'
    Write-KV 'Fabricante'   $bios.Manufacturer
    Write-KV 'Version'      $bios.SMBIOSBIOSVersion
    Write-KV 'Fecha'        $bios.ReleaseDate
    Write-KV 'Serie equipo' $bios.SerialNumber

    Write-Section 'Modo de arranque'
    $mode = if ($env:firmware_type) { $env:firmware_type } elseif (Test-Path 'HKLM:\System\CurrentControlSet\Control\SecureBoot\State') { 'UEFI' } else { 'Legacy/Desconocido' }
    Write-KV 'Firmware' $mode ($(if ($mode -match 'UEFI') { $script:T.Ok } else { $script:T.Warn }))
    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        Write-KV 'Secure Boot' $(if ($sb) { 'Activado' } else { 'Desactivado' }) $(if ($sb) { $script:T.Ok } else { $script:T.Warn })
    } catch { Write-KV 'Secure Boot' 'No consultable (BIOS legacy o sin permisos)' $script:T.Dim }

    Write-Section 'TPM'
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        Write-KV 'Presente'  $tpm.TpmPresent
        Write-KV 'Habilitado' $tpm.TpmEnabled
        Write-KV 'Listo'     $tpm.TpmReady
    } catch { Write-Status 'TPM no consultable (requiere Administrador).' 'warn' }

    Wait-Key
}

# ==============================================================================
# [09] PROCESOS
# ==============================================================================

function Get-RunningProcessesScreen {
    while ($true) {
        Show-Header 'Procesos en ejecucion'
        $procs = Get-Process | Sort-Object -Property WorkingSet64 -Descending
        Write-KV 'Procesos activos' $procs.Count

        Write-Section 'Top 15 por memoria'
        $procs | Select-Object -First 15 |
            Select-Object @{n='Proceso';e={$_.ProcessName}}, Id,
                          @{n='MB';e={[math]::Round($_.WorkingSet64/1MB,1)}},
                          @{n='CPU(s)';e={ if ($_.CPU) { [math]::Round($_.CPU,1) } else { 0 } }},
                          @{n='Inicio';e={ try { $_.StartTime.ToString('HH:mm') } catch { '-' } }} |
            Format-Table -AutoSize | Out-Host

        Write-Host '  [1] Ver todos            [2] Buscar proceso' -ForegroundColor $script:T.Val
        Write-Host '  [3] Finalizar proceso    [4] Refrescar' -ForegroundColor $script:T.Val
        Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim

        switch (Read-Choice) {
            '1' {
                $procs | Sort-Object ProcessName |
                    Format-Table @{n='Proceso';e={$_.ProcessName}}, Id,
                                 @{n='MB';e={[math]::Round($_.WorkingSet64/1MB,1)}} -AutoSize | Out-Host
                Wait-Key
            }
            '2' {
                $q = Read-Choice 'Nombre del proceso'
                Get-Process -Name "*$q*" -ErrorAction SilentlyContinue |
                    Format-Table ProcessName, Id, @{n='MB';e={[math]::Round($_.WorkingSet64/1MB,1)}}, Path -AutoSize | Out-Host
                Wait-Key
            }
            '3' {
                $target = Read-Choice 'PID o nombre a finalizar'
                if (-not $target) { break }
                try {
                    if ($target -match '^\d+$') {
                        $p = Get-Process -Id ([int]$target) -ErrorAction Stop
                    } else {
                        $p = Get-Process -Name $target -ErrorAction Stop
                    }
                    Write-Host ''
                    $p | Format-Table ProcessName, Id -AutoSize | Out-Host
                    if (Confirm-Action 'Confirma finalizar estos procesos?') {
                        $p | Stop-Process -Force -ErrorAction Stop
                        Write-Status 'Proceso finalizado.' 'ok'
                    }
                } catch { Write-Status "No se pudo finalizar: $_" 'err' }
                Wait-Key
            }
            '4' { }
            '0' { return }
            ''  { return }
            default { }
        }
    }
}

# ==============================================================================
# [10] SERVICIOS
# ==============================================================================

function Get-ServicesInfoScreen {
    while ($true) {
        Show-Header 'Servicios de Windows'
        $svc = Get-Service
        $run = @($svc | Where-Object Status -eq 'Running').Count
        $stp = @($svc | Where-Object Status -eq 'Stopped').Count
        Write-KV 'Total'        $svc.Count
        Write-KV 'En ejecucion' $run $script:T.Ok
        Write-KV 'Detenidos'    $stp $script:T.Dim

        Write-Section 'Servicios automaticos detenidos (posible problema)'
        $prob = Get-Cim Win32_Service -Filter "StartMode='Auto' AND State='Stopped'"
        if ($prob) {
            $prob | Select-Object @{n='Servicio';e={$_.Name}}, @{n='Nombre';e={$_.DisplayName}} |
                Format-Table -AutoSize | Out-Host
        } else { Write-Status 'Todos los servicios automaticos estan corriendo.' 'ok' }

        Write-Host '  [1] Buscar servicio      [2] Iniciar servicio' -ForegroundColor $script:T.Val
        Write-Host '  [3] Detener servicio     [4] Reiniciar servicio' -ForegroundColor $script:T.Val
        Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim

        $op = Read-Choice
        if ($op -eq '0' -or $op -eq '') { return }

        if ($op -eq '1') {
            $q = Read-Choice 'Texto a buscar'
            Get-Service | Where-Object { $_.DisplayName -like "*$q*" -or $_.Name -like "*$q*" } |
                Format-Table Name, DisplayName, Status, StartType -AutoSize | Out-Host
            Wait-Key
            continue
        }

        if ($op -in @('2','3','4')) {
            if (-not (Assert-Admin)) { Wait-Key; continue }
            $name = Read-Choice 'Nombre corto del servicio'
            if (-not $name) { continue }
            try {
                switch ($op) {
                    '2' { Start-Service   -Name $name -ErrorAction Stop; Write-Status 'Servicio iniciado.'   'ok' }
                    '3' { Stop-Service    -Name $name -Force -ErrorAction Stop; Write-Status 'Servicio detenido.'  'ok' }
                    '4' { Restart-Service -Name $name -Force -ErrorAction Stop; Write-Status 'Servicio reiniciado.' 'ok' }
                }
                Get-Service -Name $name | Format-Table Name, DisplayName, Status -AutoSize | Out-Host
            } catch { Write-Status "Error: $_" 'err' }
            Wait-Key
        }
    }
}

# ==============================================================================
# [11] WIFI
# ==============================================================================

function Get-WifiInfoScreen {
    Show-Header 'Redes WiFi'

    $wifi = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11' -or $_.Name -match 'Wi-?Fi' }
    if (-not $wifi) {
        Write-Status 'No se detecto adaptador WiFi en este equipo.' 'err'
        Wait-Key; return
    }

    Write-Section 'Adaptador'
    foreach ($w in $wifi) {
        Write-KV 'Nombre'    $w.Name
        Write-KV 'Chipset'   $w.InterfaceDescription
        Write-KV 'Estado'    $w.Status ($(if ($w.Status -eq 'Up') { $script:T.Ok } else { $script:T.Warn }))
        Write-KV 'Velocidad' $w.LinkSpeed
    }

    Write-Section 'Conexion actual'
    $iface = netsh wlan show interfaces 2>$null
    if ($iface) {
        $ssid   = ($iface | Select-String -Pattern '^\s*SSID\s*:' | Select-Object -First 1) -replace '.*:\s*',''
        $signal = ($iface | Select-String -Pattern 'Se.al|Signal' | Select-Object -First 1) -replace '.*:\s*',''
        $canal  = ($iface | Select-String -Pattern 'Canal|Channel' | Select-Object -First 1) -replace '.*:\s*',''
        $radio  = ($iface | Select-String -Pattern 'Tipo de radio|Radio type' | Select-Object -First 1) -replace '.*:\s*',''
        Write-KV 'SSID'   $ssid
        Write-KV 'Canal'  $canal
        Write-KV 'Radio'  $radio
        if ($signal -match '(\d+)') {
            $s = [int]$Matches[1]
            Write-Bar $s 'Calidad de senal'
            if ($s -lt 40) { Write-Status 'Senal debil: acerquese al router o revise interferencias.' 'warn' }
        }
    }

    Write-Section 'Analisis de canales'
    $nets = netsh wlan show networks mode=bssid 2>$null
    if ($nets) {
        $canales = @{}
        foreach ($line in ($nets | Select-String -Pattern 'Canal|Channel')) {
            if ($line -match '(\d+)\s*$') {
                $c = [int]$Matches[1]
                if ($canales.ContainsKey($c)) { $canales[$c]++ } else { $canales[$c] = 1 }
            }
        }
        if ($canales.Count -gt 0) {
            Write-Host ''
            foreach ($k in ($canales.Keys | Sort-Object)) {
                $bar = [string]$script:B.Full * [math]::Min(30, $canales[$k] * 3)
                Write-Host ("  Canal {0,3}  " -f $k) -ForegroundColor $script:T.Key -NoNewline
                Write-Host $bar -ForegroundColor $(if ($canales[$k] -gt 3) { $script:T.Err } elseif ($canales[$k] -gt 1) { $script:T.Warn } else { $script:T.Ok }) -NoNewline
                Write-Host ("  {0} red(es)" -f $canales[$k]) -ForegroundColor $script:T.Dim
            }
            $libres = @(1,6,11) | Where-Object { -not $canales.ContainsKey($_) -or $canales[$_] -le 1 }
            Write-Host ''
            if ($libres) { Write-Status ("Canales 2.4 GHz mas despejados: {0}" -f ($libres -join ', ')) 'ok' }
            else { Write-Status 'Los canales 1, 6 y 11 estan congestionados. Considere usar 5 GHz.' 'warn' }
        }
    } else {
        Write-Status 'No se pudo escanear. El servicio WLAN puede estar detenido.' 'warn'
    }

    Write-Host ''
    Write-Host '  [1] Ver escaneo completo' -ForegroundColor $script:T.Val
    Write-Host '  [2] Guardar escaneo en archivo' -ForegroundColor $script:T.Val
    Write-Host '  [3] Ver perfiles guardados' -ForegroundColor $script:T.Val
    Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim

    switch (Read-Choice) {
        '1' { Write-Host ''; $nets | Out-Host; Wait-Key }
        '2' {
            $f = Join-Path $script:Paths.Dir ("wifi_scan_{0}_{1}.txt" -f $script:Ctx.Fecha, $script:Ctx.Hora)
            $nets | Out-File $f -Encoding UTF8
            Write-Status ("Guardado: {0}" -f $f) 'ok'
            Wait-Key
        }
        '3' {
            Write-Section 'Perfiles WiFi guardados'
            netsh wlan show profiles 2>$null | Out-Host
            Write-Status 'Para ver una clave guardada use: netsh wlan show profile name="SSID" key=clear' 'info'
            Write-Status 'Requiere Administrador y solo funciona en el equipo donde se guardo.' 'info'
            Wait-Key
        }
        default { }
    }
}

# ==============================================================================
# [12] LIMPIEZA DE RED
# ==============================================================================

function Clear-NetworkScreen {
    while ($true) {
        Show-Header 'Limpieza de red y DNS'
        if (-not $script:Ctx.IsAdmin) { Write-Status 'Sin privilegios de Administrador varias acciones fallaran.' 'warn' }

        Write-Section 'Acciones'
        Write-Host '  [1] Vaciar cache DNS (seguro, sin cortes)'      -ForegroundColor $script:T.Val
        Write-Host '  [2] Renovar IP (release + renew)'               -ForegroundColor $script:T.Val
        Write-Host '  [3] Reset completo: Winsock + TCP/IP (reinicio)' -ForegroundColor $script:T.Warn
        Write-Host '  [4] Reiniciar adaptadores de red'               -ForegroundColor $script:T.Val
        Write-Host '  [5] Ver cache DNS actual'                       -ForegroundColor $script:T.Val
        Write-Host '  [0] Volver'                                     -ForegroundColor $script:T.Dim

        switch (Read-Choice) {
            '1' {
                Write-Host ''
                Clear-DnsClientCache -ErrorAction SilentlyContinue
                ipconfig /flushdns | Out-Null
                Write-Status 'Cache DNS vaciada.' 'ok'
                Wait-Key
            }
            '2' {
                if (-not (Assert-Admin)) { Wait-Key; break }
                Write-Host ''
                Write-Status 'Liberando y renovando direccion. Puede perder la conexion unos segundos.' 'work'
                ipconfig /release | Out-Null
                ipconfig /renew   | Out-Null
                ipconfig /flushdns | Out-Null
                Write-Status 'Listo.' 'ok'
                Get-NetIPConfiguration | Where-Object IPv4Address |
                    Format-Table InterfaceAlias, @{n='IPv4';e={$_.IPv4Address.IPAddress}} -AutoSize | Out-Host
                Wait-Key
            }
            '3' {
                if (-not (Assert-Admin)) { Wait-Key; break }
                Write-Host ''
                Write-Status 'Esto restablece el stack de red. Requiere reiniciar el equipo.' 'warn'
                if (-not (Confirm-Action 'Continuar?')) { break }
                ipconfig /release   | Out-Null
                ipconfig /flushdns  | Out-Null
                netsh winsock reset | Out-Null
                netsh int ip reset  | Out-Null
                netsh int ipv6 reset| Out-Null
                ipconfig /renew     | Out-Null
                Write-Status 'Reset aplicado. Reinicie para completarlo.' 'ok'
                if (Confirm-Action 'Reiniciar el equipo ahora?') { Restart-Computer -Force }
                Wait-Key
            }
            '4' {
                if (-not (Assert-Admin)) { Wait-Key; break }
                Write-Host ''
                Write-Status 'Reiniciando adaptadores activos...' 'work'
                Get-NetAdapter | Where-Object Status -eq 'Up' | Restart-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 4
                Write-Status 'Hecho.' 'ok'
                Wait-Key
            }
            '5' {
                Write-Section 'Cache DNS'
                Get-DnsClientCache -ErrorAction SilentlyContinue |
                    Select-Object -First 30 Entry, Data, TimeToLive | Format-Table -AutoSize | Out-Host
                Wait-Key
            }
            '0' { return }
            ''  { return }
            default { }
        }
    }
}

# ==============================================================================
# [13] REPARACION DEL SISTEMA
# ==============================================================================

function Repair-SystemScreen {
    while ($true) {
        Show-Header 'Reparacion del sistema'
        if (-not $script:Ctx.IsAdmin) { Write-Status 'Estas herramientas exigen Administrador.' 'warn' }

        Write-Section 'Herramientas'
        Write-Host '  [1] SFC /verifyonly   (solo comprueba, no modifica)' -ForegroundColor $script:T.Val
        Write-Host '  [2] SFC /scannow      (comprueba y repara)'          -ForegroundColor $script:T.Val
        Write-Host '  [3] DISM /CheckHealth (rapido)'                      -ForegroundColor $script:T.Val
        Write-Host '  [4] DISM /ScanHealth  (analisis profundo)'           -ForegroundColor $script:T.Val
        Write-Host '  [5] DISM /RestoreHealth (repara la imagen)'          -ForegroundColor $script:T.Val
        Write-Host '  [6] CHKDSK del disco de sistema (solo lectura)'      -ForegroundColor $script:T.Val

        Write-Section 'Limpieza de SO (almacen de componentes / WinSxS)'
        Write-Host '  [7] DISM /AnalyzeComponentStore (mide cuanto se puede liberar)' -ForegroundColor $script:T.Val
        Write-Host '  [8] DISM /StartComponentCleanup (libera ese espacio)'           -ForegroundColor $script:T.Val

        Write-Host ''
        Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim
        Write-Host ''
        Write-Host '  Orden recomendado si hay corrupcion: 5 y luego 2.' -ForegroundColor $script:T.Dim
        Write-Host '  Orden recomendado para limpiar espacio: 7 y luego 8.' -ForegroundColor $script:T.Dim

        $op = Read-Choice
        if ($op -eq '0' -or $op -eq '') { return }
        if ($op -notin @('1','2','3','4','5','6','7','8')) { continue }
        if (-not (Assert-Admin)) { Wait-Key; continue }

        Write-Host ''
        Write-Status 'Ejecutando. Puede tardar varios minutos, no cierre la ventana.' 'work'
        Write-Host ''
        switch ($op) {
            '1' { sfc /verifyonly }
            '2' { sfc /scannow }
            '3' { DISM.exe /Online /Cleanup-Image /CheckHealth }
            '4' { DISM.exe /Online /Cleanup-Image /ScanHealth }
            '5' { DISM.exe /Online /Cleanup-Image /RestoreHealth }
            '6' { chkdsk $env:SystemDrive }
            '7' { DISM.exe /Online /Cleanup-Image /AnalyzeComponentStore }
            '8' { DISM.exe /Online /Cleanup-Image /StartComponentCleanup }
        }
        Write-Host ''
        Write-Status 'Proceso finalizado.' 'ok'
        Wait-Key
    }
}

# ==============================================================================
# [14] EVENTOS
# ==============================================================================

function Get-SystemEventsScreen {
    while ($true) {
        Show-Header 'Visor de eventos'
        Write-Section 'Filtros'
        Write-Host '  [1] Errores criticos (72 h)'      -ForegroundColor $script:T.Val
        Write-Host '  [2] Errores (24 h)'               -ForegroundColor $script:T.Val
        Write-Host '  [3] Advertencias (24 h)'          -ForegroundColor $script:T.Val
        Write-Host '  [4] Inicios y apagados'           -ForegroundColor $script:T.Val
        Write-Host '  [5] Pantallas azules y cuelgues'  -ForegroundColor $script:T.Val
        Write-Host '  [6] Errores de aplicacion (24 h)' -ForegroundColor $script:T.Val
        Write-Host '  [0] Volver'                       -ForegroundColor $script:T.Dim

        $op = Read-Choice
        if ($op -eq '0' -or $op -eq '') { return }

        $filter = switch ($op) {
            '1' { @{ LogName='System'; Level=1; StartTime=(Get-Date).AddHours(-72) } }
            '2' { @{ LogName='System'; Level=2; StartTime=(Get-Date).AddHours(-24) } }
            '3' { @{ LogName='System'; Level=3; StartTime=(Get-Date).AddHours(-24) } }
            '4' { @{ LogName='System'; Id=6005,6006,6008,41,1074 } }
            '5' { @{ LogName='System'; Id=41,1001,6008 } }
            '6' { @{ LogName='Application'; Level=1,2; StartTime=(Get-Date).AddHours(-24) } }
            default { $null }
        }
        if (-not $filter) { continue }

        Write-Host ''
        try {
            $ev = Get-WinEvent -FilterHashtable $filter -MaxEvents 25 -ErrorAction Stop
            if (-not $ev) { Write-Status 'Sin eventos que coincidan. Buena senal.' 'ok' }
            foreach ($e in $ev) {
                $c = switch ($e.Level) { 1 { $script:T.Err } 2 { $script:T.Err } 3 { $script:T.Warn } default { $script:T.Val } }
                Write-Host ''
                Write-Host ("  {0:dd/MM/yyyy HH:mm:ss}  ID {1}  {2}" -f $e.TimeCreated, $e.Id, $e.ProviderName) -ForegroundColor $c
                $msg = ($e.Message -split "`r?`n" | Where-Object { $_.Trim() }) -join ' '
                if ($msg.Length -gt 220) { $msg = $msg.Substring(0,220) + '...' }
                Write-Host ("     {0}" -f $msg) -ForegroundColor $script:T.Dim
            }
        } catch {
            Write-Status "No se pudieron leer los eventos: $_" 'err'
        }
        Wait-Key
    }
}

# ==============================================================================
# [15] GPU
# ==============================================================================

function Get-GPUInfoScreen {
    Show-Header 'Tarjeta grafica'

    $gpus = Get-Cim Win32_VideoController
    if (-not $gpus) { Write-Status 'No se detectaron controladoras de video.' 'err'; Wait-Key; return }

    $i = 1
    foreach ($g in $gpus) {
        Write-Section ("GPU {0}" -f $i)
        Write-KV 'Nombre'      $g.Name
        Write-KV 'Fabricante'  $g.AdapterCompatibility
        if ($g.AdapterRAM -and $g.AdapterRAM -gt 0) {
            Write-KV 'Memoria' ("{0:N2} GB (reportada por WMI)" -f ($g.AdapterRAM / 1GB))
        } else {
            Write-KV 'Memoria' 'Compartida con el sistema'
        }
        Write-KV 'Driver'      $g.DriverVersion
        Write-KV 'Fecha driver' $g.DriverDate
        Write-KV 'Procesador'  $g.VideoProcessor
        Write-KV 'Resolucion'  $(if ($g.CurrentHorizontalResolution) { "{0}x{1} @ {2} Hz" -f $g.CurrentHorizontalResolution, $g.CurrentVerticalResolution, $g.CurrentRefreshRate } else { 'Inactiva' })
        Write-KV 'Estado'      $g.Status
        $i++
    }
    Write-Status 'WMI reporta mal la VRAM de tarjetas con mas de 4 GB. Use dxdiag o el panel del fabricante para el dato real.' 'info'

    Write-Section 'Controladores detectados'
    $found = $false
    foreach ($d in @(
        @{ p='HKLM:\SOFTWARE\NVIDIA Corporation\Global'; n='NVIDIA' },
        @{ p='HKLM:\SOFTWARE\AMD';                        n='AMD' },
        @{ p='HKLM:\SOFTWARE\Intel\GFX';                  n='Intel Graphics' }
    )) {
        if (Test-Path $d.p) { Write-Status ("{0}: instalado" -f $d.n) 'ok'; $found = $true }
    }
    if (-not $found) { Write-Status 'No se identificaron paquetes de driver conocidos.' 'warn' }

    Write-Section 'Monitores'
    Get-Cim Win32_DesktopMonitor | Select-Object Name, ScreenWidth, ScreenHeight | Format-Table -AutoSize | Out-Host

    Write-Host ''
    if (Confirm-Action 'Abrir dxdiag para un informe completo?') { Start-Process dxdiag.exe }
    Wait-Key
}

# ==============================================================================
# [16] TEMPERATURAS
# ==============================================================================

function Get-TemperaturesScreen {
    Show-Header 'Temperaturas y refrigeracion'
    Write-Status 'Windows no expone sensores de forma fiable. Se intentan varias vias.' 'info'

    $temps = @()

    Write-Section 'Sensores ACPI (WMI)'
    try {
        $tz = Get-Cim MSAcpi_ThermalZoneTemperature -Namespace 'root\wmi'
        if ($tz) {
            foreach ($t in $tz) {
                if ($null -ne $t.CurrentTemperature) {
                    $c = [math]::Round(($t.CurrentTemperature - 2732) / 10, 1)
                    $temps += $c
                    $color = if ($c -gt 85) { $script:T.Err } elseif ($c -gt 75) { $script:T.Warn } else { $script:T.Ok }
                    Write-KV 'Zona termica' ("{0} C" -f $c) $color
                }
            }
        } else { Write-Status 'El firmware no publica zonas termicas por WMI.' 'warn' }
    } catch { Write-Status 'Consulta ACPI fallida (suele requerir Administrador).' 'warn' }

    Write-Section 'LibreHardwareMonitor / OpenHardwareMonitor'
    $ohmFound = $false
    foreach ($ns in @('root\LibreHardwareMonitor','root\OpenHardwareMonitor')) {
        try {
            $s = Get-CimInstance -Namespace $ns -ClassName Sensor -Filter "SensorType='Temperature'" -ErrorAction Stop
            if ($s) {
                $ohmFound = $true
                foreach ($x in $s) {
                    $temps += [double]$x.Value
                    $color = if ($x.Value -gt 85) { $script:T.Err } elseif ($x.Value -gt 75) { $script:T.Warn } else { $script:T.Ok }
                    Write-KV $x.Name ("{0} C" -f [math]::Round($x.Value,1)) $color
                }
            }
        } catch { }
    }
    if (-not $ohmFound) { Write-Status 'No detectado. Es la forma mas fiable de leer CPU/GPU: instale LibreHardwareMonitor y dejelo abierto.' 'info' }

    Write-Section 'Ventiladores'
    $fans = Get-Cim Win32_Fan
    if ($fans) {
        foreach ($f in $fans) {
            $st = if ($f.ActiveCooling) { 'Activo' } else { 'Pasivo/Inactivo' }
            Write-KV ($f.DeviceID) $st ($(if ($f.ActiveCooling) { $script:T.Ok } else { $script:T.Warn }))
        }
    } else { Write-Status 'Sin datos de ventiladores por WMI (normal en la mayoria de equipos).' 'warn' }

    if ($temps.Count -gt 0) {
        $avg = [math]::Round(($temps | Measure-Object -Average).Average, 1)
        $max = [math]::Round(($temps | Measure-Object -Maximum).Maximum, 1)
        Write-Section 'Resumen'
        Write-KV 'Lecturas'  $temps.Count
        Write-KV 'Promedio'  ("{0} C" -f $avg)
        Write-KV 'Maxima'    ("{0} C" -f $max)
        Write-Bar ([math]::Min(100, $max)) 'Temperatura maxima'
        if ($max -gt 90)     { Write-Status 'Critico: el equipo puede apagarse. Revise refrigeracion ya.' 'err' }
        elseif ($max -gt 80) { Write-Status 'Temperatura alta bajo carga. Limpie polvo y revise ventiladores.' 'warn' }
        else                 { Write-Status 'Temperaturas dentro de rango.' 'ok' }
    }

    Write-Section 'Referencia'
    Write-Host '  CPU en reposo   30 - 50 C     CPU bajo carga   60 - 85 C' -ForegroundColor $script:T.Dim
    Write-Host '  Peligro        > 90 C         Thermal throttle ~ 95 - 100 C' -ForegroundColor $script:T.Dim
    Write-Host ''
    Write-Host '  Mantenimiento: limpiar polvo cada 6 meses, pasta termica cada 2-3 anos,' -ForegroundColor $script:T.Dim
    Write-Host '  verificar que todos los ventiladores giren, no obstruir rejillas.' -ForegroundColor $script:T.Dim

    Wait-Key
}

# ==============================================================================
# [17] BATERIA
# ==============================================================================

function Get-BatteryReportScreen {
    Show-Header 'Bateria'
    $bat = Get-Cim Win32_Battery

    if (-not $bat) {
        Write-Status 'No se detecto bateria. Esta funcion es para portatiles.' 'warn'
        Wait-Key; return
    }

    Write-Section 'Estado actual'
    $statusMap = @{
        1='Descargando'; 2='Conectada a la red'; 3='Cargada'; 4='Baja'; 5='Critica'
        6='Cargando'; 7='Cargando y alta'; 8='Cargando y baja'; 9='Cargando y critica'; 11='Parcialmente cargada'
    }
    Write-KV 'Nombre'    $bat.Name
    Write-KV 'Quimica'   $(switch ([int]$bat.Chemistry) { 3 {'NiMH'} 4 {'Ion Litio'} 6 {'Polimero de litio'} default {'Desconocida'} })
    Write-KV 'Estado'    ($statusMap[[int]$bat.BatteryStatus])
    $charge = [int]$bat.EstimatedChargeRemaining
    Write-Bar $charge 'Carga restante' -InvertColors
    if ($bat.EstimatedRunTime -and $bat.EstimatedRunTime -lt 71582788) {
        Write-KV 'Autonomia estimada' ("{0:N1} horas" -f ($bat.EstimatedRunTime / 60))
    }
    if ($charge -lt 20) { Write-Status 'Bateria baja: conecte el cargador.' 'warn' }

    Write-Section 'Salud (capacidad de diseno vs actual)'
    try {
        $full   = (Get-Cim BatteryFullChargedCapacity -Namespace 'root\wmi').FullChargedCapacity
        $design = (Get-Cim BatteryStaticData -Namespace 'root\wmi').DesignedCapacity
        if ($full -and $design) {
            $health = [math]::Round(($full / $design) * 100, 1)
            Write-KV 'Capacidad de diseno' ("{0} mWh" -f $design)
            Write-KV 'Capacidad actual'    ("{0} mWh" -f $full)
            Write-Bar $health 'Salud de la bateria' -InvertColors
            if ($health -lt 60)     { Write-Status 'Desgaste severo: conviene reemplazar la bateria.' 'err' }
            elseif ($health -lt 80) { Write-Status 'Desgaste notable.' 'warn' }
            else                    { Write-Status 'Bateria en buen estado.' 'ok' }
        } else { Write-Status 'El firmware no reporta capacidades. Use el informe HTML de abajo.' 'warn' }
    } catch { Write-Status 'No se pudo leer la salud por WMI.' 'warn' }

    Write-Host ''
    if (Confirm-Action 'Generar informe detallado de bateria (powercfg)?') {
        $out = Join-Path ([Environment]::GetFolderPath('Desktop')) ("battery_report_{0}_{1}.html" -f $script:Ctx.Fecha, $script:Ctx.Hora)
        try {
            powercfg /batteryreport /output "$out" | Out-Null
            if (Test-Path $out) {
                Write-Status 'Informe generado.' 'ok'
                Write-KV 'Archivo' $out
                if (Confirm-Action 'Abrirlo ahora?') { Start-Process $out }
            } else { Write-Status 'powercfg no genero el archivo.' 'err' }
        } catch { Write-Status "Error: $_" 'err' }
    }
    Wait-Key
}

# ==============================================================================
# [18] EXPORTAR A HTML
# ==============================================================================

function Export-ToHTMLScreen {
    Show-Header 'Exportar informe HTML'
    $out = Join-Path ([Environment]::GetFolderPath('Desktop')) ("informe_{0}_{1}_{2}.html" -f $script:Ctx.Computer, $script:Ctx.Fecha, $script:Ctx.Hora)

    Write-Status 'Recopilando datos...' 'work'
    $os   = Get-Cim Win32_OperatingSystem
    $cs   = Get-Cim Win32_ComputerSystem
    $cpu  = Get-Cim Win32_Processor | Select-Object -First 1
    $bb   = Get-Cim Win32_BaseBoard
    $bios = Get-Cim Win32_BIOS
    $gpus = Get-Cim Win32_VideoController
    $discos = Get-Cim Win32_LogicalDisk -Filter 'DriveType=3'
    $ad   = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up'
    $prog = Get-InstalledProgramList
    $reboot   = Test-PendingRebootInternal
    $fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    $startup  = Get-StartupItemList
    $bat      = Get-Cim Win32_Battery

    $totalRAM = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $freeRAM  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedRAM  = [math]::Round($totalRAM - $freeRAM, 2)
    $ramPct   = if ($totalRAM -gt 0) { [math]::Round(($usedRAM / $totalRAM) * 100, 1) } else { 0 }
    $uptime   = try { (Get-Date) - $os.LastBootUpTime } catch { $null }
    $uptimeTxt= if ($uptime) { "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes } else { 'n/d' }

    Write-Status 'Generando HTML...' 'work'

    $head = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Informe tecnico - $($script:Ctx.Computer)</title>
<style>
:root{
  --bg:#0f1419; --surface:#171d24; --surface-2:#1e262f; --line:#2a353f;
  --text:#e6edf3; --muted:#8b98a5; --accent:#4cc2ff; --ok:#3fb950; --warn:#d29922; --err:#f85149;
}
@media (prefers-color-scheme: light){
  :root{ --bg:#f4f6f8; --surface:#ffffff; --surface-2:#f0f3f6; --line:#dde3e9;
         --text:#1b232b; --muted:#5b6b7a; --accent:#0969da; }
}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',system-ui,-apple-system,sans-serif;background:var(--bg);color:var(--text);line-height:1.55;padding:28px 18px}
.wrap{max-width:1080px;margin:0 auto}
header{border-left:4px solid var(--accent);padding:6px 0 6px 18px;margin-bottom:28px}
header h1{font-size:1.7rem;font-weight:650;letter-spacing:-.02em}
header p{color:var(--muted);font-size:.9rem;margin-top:4px}
.meta{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
.chip{background:var(--surface-2);border:1px solid var(--line);border-radius:999px;padding:3px 12px;font-size:.78rem;color:var(--muted)}
.chip b{color:var(--text);font-weight:600}
section{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:20px 22px;margin-bottom:18px}
h2{font-size:1rem;text-transform:uppercase;letter-spacing:.06em;color:var(--accent);margin-bottom:16px;font-weight:650}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px}
.tile{background:var(--surface-2);border:1px solid var(--line);border-radius:9px;padding:14px}
.tile .lbl{font-size:.72rem;text-transform:uppercase;letter-spacing:.07em;color:var(--muted)}
.tile .val{font-size:1.15rem;font-weight:600;margin:5px 0;word-break:break-word}
.tile .sub{font-size:.8rem;color:var(--muted)}
.bar{height:6px;background:var(--line);border-radius:3px;overflow:hidden;margin:8px 0 5px}
.bar i{display:block;height:100%;border-radius:3px;background:var(--accent)}
.bar i.ok{background:var(--ok)} .bar i.warn{background:var(--warn)} .bar i.err{background:var(--err)}
table{width:100%;border-collapse:collapse;font-size:.87rem}
th{text-align:left;font-weight:600;font-size:.74rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);padding:9px 10px;border-bottom:1px solid var(--line)}
td{padding:9px 10px;border-bottom:1px solid var(--line)}
tr:last-child td{border-bottom:none}
tbody tr:hover{background:var(--surface-2)}
.tag{display:inline-block;padding:2px 9px;border-radius:5px;font-size:.73rem;font-weight:600}
.tag.ok{background:rgba(63,185,80,.15);color:var(--ok)}
.tag.warn{background:rgba(210,153,34,.15);color:var(--warn)}
.tag.err{background:rgba(248,81,73,.15);color:var(--err)}
.tag.neutral{background:var(--surface-2);color:var(--muted)}
.kv{display:grid;grid-template-columns:190px 1fr;gap:6px 16px;font-size:.88rem}
.kv dt{color:var(--muted)}
footer{color:var(--muted);font-size:.78rem;text-align:center;padding:24px 0 8px}
.scroll{overflow-x:auto}
@media print{body{background:#fff;color:#000;padding:0}section{break-inside:avoid;border-color:#ccc}}
</style>
</head>
<body><div class="wrap">
<header>
  <h1>Informe tecnico del sistema</h1>
  <p>Generado por Multi Herramienta Tecnica v$($script:Version)</p>
  <div class="meta">
    <span class="chip">Equipo <b>$($script:Ctx.Computer)</b></span>
    <span class="chip">Usuario <b>$($script:Ctx.User)</b></span>
    <span class="chip">Fecha <b>$(Get-Date -Format 'dd/MM/yyyy HH:mm')</b></span>
    <span class="chip">Encendido <b>$uptimeTxt</b></span>
  </div>
</header>
"@

    $ramClass = if ($ramPct -gt 90) { 'err' } elseif ($ramPct -gt 75) { 'warn' } else { 'ok' }
    $resumen = @"
<section>
  <h2>Resumen</h2>
  <div class="grid">
    <div class="tile"><div class="lbl">Sistema operativo</div><div class="val">$($os.Caption)</div><div class="sub">Build $($os.BuildNumber) $($os.OSArchitecture)</div></div>
    <div class="tile"><div class="lbl">Procesador</div><div class="val">$(($cpu.Name -split '@')[0].Trim())</div><div class="sub">$($cpu.NumberOfCores) nucleos / $($cpu.NumberOfLogicalProcessors) hilos</div></div>
    <div class="tile"><div class="lbl">Memoria RAM</div><div class="val">$totalRAM GB</div>
      <div class="bar"><i class="$ramClass" style="width:$ramPct%"></i></div>
      <div class="sub">$usedRAM GB en uso ($ramPct %)</div></div>
    <div class="tile"><div class="lbl">Equipo</div><div class="val">$($cs.Manufacturer)</div><div class="sub">$($cs.Model)</div></div>
  </div>
</section>
"@

    $sbDisk = New-Object System.Text.StringBuilder
    [void]$sbDisk.Append('<section><h2>Almacenamiento</h2><div class="scroll"><table><thead><tr><th>Unidad</th><th>Etiqueta</th><th>Total</th><th>Libre</th><th>Ocupacion</th><th>Estado</th></tr></thead><tbody>')
    foreach ($d in $discos) {
        if (-not $d.Size) { continue }
        $freePct = [math]::Round(($d.FreeSpace / $d.Size) * 100, 1)
        $usedPct = [math]::Round(100 - $freePct, 1)
        if ($freePct -gt 20)     { $tag = '<span class="tag ok">Optimo</span>';      $cls = 'ok' }
        elseif ($freePct -gt 10) { $tag = '<span class="tag warn">Atencion</span>';  $cls = 'warn' }
        else                     { $tag = '<span class="tag err">Critico</span>';    $cls = 'err' }
        [void]$sbDisk.Append("<tr><td><b>$($d.DeviceID)</b></td><td>$($d.VolumeName)</td><td>$([math]::Round($d.Size/1GB,1)) GB</td><td>$([math]::Round($d.FreeSpace/1GB,1)) GB</td><td><div class=""bar""><i class=""$cls"" style=""width:$usedPct%""></i></div>$usedPct % usado</td><td>$tag</td></tr>")
    }
    [void]$sbDisk.Append('</tbody></table></div></section>')

    $sbNet = New-Object System.Text.StringBuilder
    [void]$sbNet.Append('<section><h2>Red</h2><div class="grid">')
    foreach ($a in $ad) {
        $c = Get-NetIPConfiguration -InterfaceAlias $a.Name -ErrorAction SilentlyContinue
        $ip = if ($c) { ($c.IPv4Address.IPAddress -join ', ') } else { 'n/d' }
        $gw = if ($c) { $c.IPv4DefaultGateway.NextHop } else { 'n/d' }
        [void]$sbNet.Append("<div class=""tile""><div class=""lbl"">$($a.Name)</div><div class=""val"">$ip</div><div class=""sub"">$(($a.InterfaceDescription -split ',')[0])<br>Gateway: $gw<br>$($a.LinkSpeed)</div><div style=""margin-top:8px""><span class=""tag ok"">Conectado</span></div></div>")
    }
    if (-not $ad) { [void]$sbNet.Append('<div class="tile"><div class="val">Sin adaptadores activos</div></div>') }
    [void]$sbNet.Append('</div></section>')

    $sbHw = @"
<section>
  <h2>Hardware</h2>
  <div class="grid">
    <div class="tile"><div class="lbl">Placa base</div><div class="val">$($bb.Manufacturer)</div><div class="sub">$($bb.Product)<br>S/N: $($bb.SerialNumber)</div></div>
    <div class="tile"><div class="lbl">BIOS / UEFI</div><div class="val">$($bios.Manufacturer)</div><div class="sub">Version $($bios.SMBIOSBIOSVersion)<br>$($bios.ReleaseDate)</div></div>
    <div class="tile"><div class="lbl">Grafica</div><div class="val">$(($gpus | Select-Object -First 1).Name)</div><div class="sub">Driver $(($gpus | Select-Object -First 1).DriverVersion)</div></div>
  </div>
  <div style="margin-top:16px" class="kv">
    <dt>Frecuencia CPU</dt><dd>$($cpu.MaxClockSpeed) MHz</dd>
    <dt>Cache L3</dt><dd>$($cpu.L3CacheSize) KB</dd>
    <dt>Serie del equipo</dt><dd>$($bios.SerialNumber)</dd>
    <dt>Ultimo arranque</dt><dd>$($os.LastBootUpTime)</dd>
  </div>
</section>
"@

    $rebootTag = if ($reboot.Pending) { '<span class="tag warn">Pendiente</span>' } else { '<span class="tag ok">Sin pendientes</span>' }
    $rebootSub = if ($reboot.Pending) { ($reboot.Razones -join '<br>') } else { 'El equipo no necesita reiniciarse.' }

    $sbFw = New-Object System.Text.StringBuilder
    if ($fwProfiles) {
        foreach ($fp in $fwProfiles) {
            $fwTag = if ($fp.Enabled) { '<span class="tag ok">Activado</span>' } else { '<span class="tag err">Desactivado</span>' }
            [void]$sbFw.Append("<div class=""tile""><div class=""lbl"">Firewall $($fp.Name)</div><div class=""val"">$fwTag</div></div>")
        }
    } else {
        [void]$sbFw.Append('<div class="tile"><div class="lbl">Firewall</div><div class="val">No consultable</div></div>')
    }

    $batBlock = ''
    if ($bat) {
        $chargeVal = [int]$bat.EstimatedChargeRemaining
        $chargeCls = if ($chargeVal -lt 20) { 'err' } elseif ($chargeVal -lt 40) { 'warn' } else { 'ok' }
        $batBlock = @"
    <div class="tile"><div class="lbl">Bateria</div><div class="val">$chargeVal %</div>
      <div class="bar"><i class="$chargeCls" style="width:$chargeVal%"></i></div>
      <div class="sub">Equipo portatil</div></div>
"@
    }

    $sbEstado = @"
<section>
  <h2>Estado y seguridad</h2>
  <div class="grid">
    <div class="tile"><div class="lbl">Reinicio pendiente</div><div class="val">$rebootTag</div><div class="sub">$rebootSub</div></div>
    $($sbFw.ToString())
    $batBlock
  </div>
</section>
"@

    $sbStartup = New-Object System.Text.StringBuilder
    [void]$sbStartup.Append("<section><h2>Programas de inicio ($($startup.Count) detectados)</h2><div class=""scroll""><table><thead><tr><th>Nombre</th><th>Origen</th><th>Tipo</th></tr></thead><tbody>")
    if ($startup.Count -eq 0) {
        [void]$sbStartup.Append('<tr><td colspan="3">No se encontraron entradas de inicio automatico.</td></tr>')
    } else {
        foreach ($si in ($startup | Select-Object -First 20)) {
            [void]$sbStartup.Append("<tr><td>$($si.Nombre)</td><td>$($si.Origen)</td><td><span class=""tag neutral"">$($si.Tipo)</span></td></tr>")
        }
    }
    [void]$sbStartup.Append('</tbody></table></div></section>')

    $sbProg = New-Object System.Text.StringBuilder
    $show = $prog | Select-Object -First 40
    [void]$sbProg.Append("<section><h2>Programas instalados ($($prog.Count) en total, se listan $($show.Count))</h2><div class=""scroll""><table><thead><tr><th>Programa</th><th>Version</th><th>Editor</th><th>Instalado</th></tr></thead><tbody>")
    foreach ($p in $show) {
        $f = 'n/d'
        if ($p.InstallDate) { try { $f = [datetime]::ParseExact($p.InstallDate,'yyyyMMdd',$null).ToString('dd/MM/yyyy') } catch { } }
        [void]$sbProg.Append("<tr><td>$($p.DisplayName)</td><td><span class=""tag neutral"">$($p.DisplayVersion)</span></td><td>$($p.Publisher)</td><td>$f</td></tr>")
    }
    [void]$sbProg.Append('</tbody></table></div></section>')

    $foot = @"
<footer>Informe generado el $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') &middot; Multi Herramienta Tecnica v$($script:Version)</footer>
</div></body></html>
"@

    try {
        ($head + $resumen + $sbDisk.ToString() + $sbNet.ToString() + $sbHw + $sbEstado + $sbStartup.ToString() + $sbProg.ToString() + $foot) |
            Out-File -FilePath $out -Encoding UTF8 -Force
        Write-Host ''
        Write-Status 'Informe HTML generado.' 'ok'
        Write-KV 'Archivo' $out
        Write-KV 'Tamano' ("{0:N1} KB" -f ((Get-Item $out).Length / 1KB))
        if (Confirm-Action 'Abrir en el navegador?') { Start-Process $out }
    } catch {
        Write-Status "Error al guardar: $_" 'err'
    }
    Wait-Key
}

# ==============================================================================
# [11] PROGRAMAS DE INICIO
# ==============================================================================

function Get-StartupItemList {
    $items = New-Object System.Collections.Generic.List[object]

    $runKeys = @(
        @{ Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';  Scope='Equipo (HKLM)' },
        @{ Path='HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'; Scope='Equipo (HKLM 32-bit)' },
        @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';  Scope='Usuario (HKCU)' }
    )
    foreach ($rk in $runKeys) {
        if (-not (Test-Path $rk.Path)) { continue }
        $props = Get-ItemProperty -Path $rk.Path -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -match '^PS(Path|ParentPath|ChildName|Provider)$') { continue }
            $items.Add([pscustomobject]@{
                Nombre  = $p.Name
                Comando = "$($p.Value)"
                Origen  = $rk.Scope
                Tipo    = 'Registro'
                Ruta    = $rk.Path
            })
        }
    }

    $startupFolders = @(
        @{ Path=[Environment]::GetFolderPath('Startup');       Scope='Usuario (carpeta)' },
        @{ Path=[Environment]::GetFolderPath('CommonStartup');  Scope='Equipo (carpeta)' }
    )
    foreach ($sf in $startupFolders) {
        if (-not (Test-Path $sf.Path)) { continue }
        Get-ChildItem -Path $sf.Path -File -ErrorAction SilentlyContinue | ForEach-Object {
            $items.Add([pscustomobject]@{
                Nombre  = $_.BaseName
                Comando = $_.FullName
                Origen  = $sf.Scope
                Tipo    = 'Acceso directo'
                Ruta    = $_.FullName
            })
        }
    }

    return $items
}

function Get-StartupProgramsScreen {
    while ($true) {
        Show-Header 'Programas de inicio'
        $items = Get-StartupItemList
        Write-KV 'Total detectado' $items.Count

        Write-Section 'Listado'
        if ($items.Count -eq 0) {
            Write-Status 'No se encontraron entradas de inicio automatico.' 'info'
        } else {
            $i = 1
            foreach ($it in $items) {
                Write-Host ("  [{0,2}] {1}" -f $i, $it.Nombre) -ForegroundColor $script:T.Accent
                Write-KV '   Origen'  $it.Origen
                Write-KV '   Comando' $it.Comando $script:T.Dim
                $i++
            }
        }

        Write-Section 'Impacto en el arranque (si Task Scheduler lo reporta)'
        try {
            $impact = Get-CimInstance -ClassName Win32_StartupCommand -ErrorAction Stop
            if ($impact) {
                $impact | Select-Object Name, Location, User | Format-Table -AutoSize | Out-Host
            }
        } catch { Write-Status 'No disponible en este equipo.' 'info' }

        Write-Host ''
        Write-Host '  [1] Deshabilitar una entrada (registro)' -ForegroundColor $script:T.Val
        Write-Host '  [2] Abrir Administrador de tareas (pestana Inicio)' -ForegroundColor $script:T.Val
        Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim

        $op = Read-Choice
        if ($op -eq '0' -or $op -eq '') { return }

        if ($op -eq '2') { Start-Process taskmgr.exe; continue }

        if ($op -eq '1') {
            $regItems = $items | Where-Object Tipo -eq 'Registro'
            if (-not $regItems -or $regItems.Count -eq 0) {
                Write-Status 'No hay entradas de registro para deshabilitar (las de carpeta se quitan moviendo el acceso directo).' 'warn'
                Wait-Key; continue
            }
            $sel = Read-Choice ("Numero de la lista completa a deshabilitar (1-{0})" -f $items.Count)
            if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $items.Count) { continue }
            $target = $items[[int]$sel - 1]
            if ($target.Tipo -ne 'Registro') {
                Write-Status 'Esa entrada es un acceso directo. Muevala fuera de la carpeta de inicio manualmente:' 'warn'
                Write-KV 'Carpeta' (Split-Path $target.Ruta -Parent)
                Wait-Key; continue
            }
            if (-not (Confirm-Action ("Quitar '{0}' del inicio automatico?" -f $target.Nombre))) { continue }
            try {
                Remove-ItemProperty -Path $target.Ruta -Name $target.Nombre -ErrorAction Stop
                Write-Status 'Entrada eliminada del inicio automatico.' 'ok'
            } catch { Write-Status "No se pudo eliminar (pruebe como Administrador): $_" 'err' }
            Wait-Key
        }
    }
}

# ==============================================================================
# [12] TAREAS PROGRAMADAS
# ==============================================================================

function Get-ScheduledTasksScreen {
    while ($true) {
        Show-Header 'Tareas programadas'
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Sort-Object TaskPath, TaskName
        if (-not $tasks) {
            Write-Status 'No se pudo consultar el Programador de tareas.' 'err'
            Wait-Key; return
        }

        $ready   = @($tasks | Where-Object State -eq 'Ready').Count
        $running = @($tasks | Where-Object State -eq 'Running').Count
        $disabled= @($tasks | Where-Object State -eq 'Disabled').Count
        Write-KV 'Total'       $tasks.Count
        Write-KV 'Listas'      $ready $script:T.Ok
        Write-KV 'En ejecucion' $running
        Write-KV 'Deshabilitadas' $disabled $script:T.Dim

        Write-Section 'Tareas no de Microsoft (mas relevantes para diagnostico)'
        $custom = $tasks | Where-Object { $_.TaskPath -notmatch '\\Microsoft\\' }
        if ($custom) {
            $custom | Select-Object -First 25 TaskName, State,
                @{n='Ruta';e={$_.TaskPath}} | Format-Table -AutoSize | Out-Host
        } else { Write-Status 'Todas las tareas pertenecen a Microsoft.' 'info' }

        Write-Host ''
        Write-Host '  [1] Buscar tarea               [2] Ver detalle de una tarea' -ForegroundColor $script:T.Val
        Write-Host '  [3] Habilitar/Deshabilitar      [4] Ejecutar ahora' -ForegroundColor $script:T.Val
        Write-Host '  [5] Eliminar tarea              [0] Volver' -ForegroundColor $script:T.Dim

        $op = Read-Choice
        if ($op -eq '0' -or $op -eq '') { return }

        switch ($op) {
            '1' {
                $q = Read-Choice 'Texto a buscar'
                $tasks | Where-Object { $_.TaskName -like "*$q*" } |
                    Select-Object TaskName, State, TaskPath | Format-Table -AutoSize | Out-Host
                Wait-Key
            }
            '2' {
                $name = Read-Choice 'Nombre exacto de la tarea'
                $t = $tasks | Where-Object TaskName -eq $name | Select-Object -First 1
                if (-not $t) { Write-Status 'No encontrada.' 'err'; Wait-Key; continue }
                $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
                Write-Section $t.TaskName
                Write-KV 'Estado'        $t.State
                Write-KV 'Ruta'          $t.TaskPath
                Write-KV 'Autor'         $t.Author
                Write-KV 'Descripcion'   $t.Description
                if ($info) {
                    Write-KV 'Ultima ejecucion'   $info.LastRunTime
                    Write-KV 'Resultado'          $info.LastTaskResult
                    Write-KV 'Proxima ejecucion'  $info.NextRunTime
                }
                Wait-Key
            }
            '3' {
                if (-not (Assert-Admin)) { Wait-Key; continue }
                $name = Read-Choice 'Nombre exacto de la tarea'
                $t = $tasks | Where-Object TaskName -eq $name | Select-Object -First 1
                if (-not $t) { Write-Status 'No encontrada.' 'err'; Wait-Key; continue }
                try {
                    if ($t.State -eq 'Disabled') {
                        Enable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null
                        Write-Status 'Tarea habilitada.' 'ok'
                    } else {
                        Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null
                        Write-Status 'Tarea deshabilitada.' 'ok'
                    }
                } catch { Write-Status "Error: $_" 'err' }
                Wait-Key
            }
            '4' {
                $name = Read-Choice 'Nombre exacto de la tarea'
                $t = $tasks | Where-Object TaskName -eq $name | Select-Object -First 1
                if (-not $t) { Write-Status 'No encontrada.' 'err'; Wait-Key; continue }
                try {
                    Start-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop
                    Write-Status 'Tarea lanzada.' 'ok'
                } catch { Write-Status "Error: $_" 'err' }
                Wait-Key
            }
            '5' {
                if (-not (Assert-Admin)) { Wait-Key; continue }
                $name = Read-Choice 'Nombre exacto de la tarea'
                $t = $tasks | Where-Object TaskName -eq $name | Select-Object -First 1
                if (-not $t) { Write-Status 'No encontrada.' 'err'; Wait-Key; continue }
                if (-not (Confirm-Action ("Eliminar definitivamente '{0}'?" -f $t.TaskName))) { continue }
                try {
                    Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
                    Write-Status 'Tarea eliminada.' 'ok'
                } catch { Write-Status "Error: $_" 'err' }
                Wait-Key
            }
            default { }
        }
    }
}

# ==============================================================================
# [21] LIMPIEZA DE TEMPORALES Y DISCO
# ==============================================================================

function Measure-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $sum = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        if ($sum) { return $sum } else { return 0 }
    } catch { return 0 }
}

function Clear-TempFilesScreen {
    Show-Header 'Limpieza de temporales'
    Write-Status 'Calculando tamanos, puede tardar un momento...' 'work'

    $targets = New-Object System.Collections.Generic.List[object]
    $targets.Add([pscustomobject]@{ Nombre='Temporales del usuario'; Ruta=$env:TEMP })
    $targets.Add([pscustomobject]@{ Nombre='Temporales de Windows';  Ruta="$env:SystemRoot\Temp" })
    $targets.Add([pscustomobject]@{ Nombre='Cache de Windows Update'; Ruta="$env:SystemRoot\SoftwareDistribution\Download" })

    $chromeCache = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    if (Test-Path $chromeCache) { $targets.Add([pscustomobject]@{ Nombre='Cache de Chrome'; Ruta=$chromeCache }) }
    $edgeCache = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    if (Test-Path $edgeCache) { $targets.Add([pscustomobject]@{ Nombre='Cache de Edge'; Ruta=$edgeCache }) }

    Write-Section 'Tamano actual'
    $totalBytes = 0
    foreach ($t in $targets) {
        $sz = Measure-FolderSize $t.Ruta
        $totalBytes += $sz
        Write-KV $t.Nombre ("{0:N1} MB" -f ($sz / 1MB))
    }

    $recycleBytes = 0
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycle = $shell.Namespace(10)
        if ($recycle) {
            foreach ($it in $recycle.Items()) { $recycleBytes += $it.Size }
        }
    } catch { }
    Write-KV 'Papelera de reciclaje' ("{0:N1} MB" -f ($recycleBytes / 1MB))

    Write-Host ''
    Write-KV 'Total recuperable estimado' ("{0:N1} MB" -f (($totalBytes + $recycleBytes) / 1MB)) $script:T.Warn

    if (-not (Confirm-Action 'Limpiar todo lo anterior?')) { return }

    $freed = 0
    foreach ($t in $targets) {
        if (-not (Test-Path $t.Ruta)) { continue }
        Write-Status ("Limpiando {0}..." -f $t.Nombre) 'work'
        $before = Measure-FolderSize $t.Ruta
        Get-ChildItem -Path $t.Ruta -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $after = Measure-FolderSize $t.Ruta
        $freed += [math]::Max(0, $before - $after)
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        $freed += $recycleBytes
        Write-Status 'Papelera de reciclaje vaciada.' 'ok'
    } catch { Write-Status 'No se pudo vaciar la papelera (puede estar vacia ya).' 'warn' }

    Write-Host ''
    Write-Status ("Espacio liberado aproximado: {0:N1} MB" -f ($freed / 1MB)) 'ok'
    Write-Status 'Algunos archivos en uso no se pudieron borrar; es normal.' 'info'
    Wait-Key
}

# ==============================================================================
# [22] FIREWALL Y PUERTOS
# ==============================================================================

function Get-FirewallScreen {
    while ($true) {
        Show-Header 'Firewall y puertos'

        Write-Section 'Perfiles del Firewall de Windows'
        $profiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        if ($profiles) {
            foreach ($p in $profiles) {
                $color = if ($p.Enabled) { $script:T.Ok } else { $script:T.Err }
                Write-KV $p.Name $(if ($p.Enabled) { 'Activado' } else { 'Desactivado' }) $color
            }
        } else { Write-Status 'No se pudo consultar el Firewall.' 'err' }

        Write-Section 'Puertos en escucha (local)'
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Sort-Object LocalPort |
            Select-Object -First 20 LocalAddress, LocalPort,
                @{n='Proceso';e={ (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName }} |
            Format-Table -AutoSize | Out-Host

        Write-Host ''
        Write-Host '  [1] Activar/Desactivar un perfil' -ForegroundColor $script:T.Val
        Write-Host '  [2] Probar si un puerto remoto responde' -ForegroundColor $script:T.Val
        Write-Host '  [3] Ver reglas que bloquean trafico' -ForegroundColor $script:T.Val
        Write-Host '  [4] Ver reglas de un programa' -ForegroundColor $script:T.Val
        Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim

        $op = Read-Choice
        if ($op -eq '0' -or $op -eq '') { return }

        switch ($op) {
            '1' {
                if (-not (Assert-Admin)) { Wait-Key; continue }
                $name = Read-Choice 'Perfil (Domain / Private / Public)'
                if (-not $name) { continue }
                $accion = Read-Choice 'Accion (activar/desactivar)'
                try {
                    if ($accion -match '^des') {
                        Set-NetFirewallProfile -Name $name -Enabled False -ErrorAction Stop
                        Write-Status 'Perfil desactivado.' 'warn'
                    } else {
                        Set-NetFirewallProfile -Name $name -Enabled True -ErrorAction Stop
                        Write-Status 'Perfil activado.' 'ok'
                    }
                } catch { Write-Status "Error: $_" 'err' }
                Wait-Key
            }
            '2' {
                $host_ = Read-Choice 'Host o IP'
                $port  = Read-Choice 'Puerto'
                if ($host_ -and $port -match '^\d+$') {
                    $r = Test-NetConnection -ComputerName $host_ -Port ([int]$port) -WarningAction SilentlyContinue
                    if ($r.TcpTestSucceeded) { Write-Status ("{0}:{1} responde." -f $host_, $port) 'ok' }
                    else { Write-Status ("{0}:{1} no responde o esta bloqueado." -f $host_, $port) 'err' }
                }
                Wait-Key
            }
            '3' {
                Write-Section 'Reglas de bloqueo activas'
                Get-NetFirewallRule -Action Block -Enabled True -ErrorAction SilentlyContinue |
                    Select-Object -First 25 DisplayName, Direction, Profile |
                    Format-Table -AutoSize | Out-Host
                Wait-Key
            }
            '4' {
                $q = Read-Choice 'Texto a buscar en el nombre de la regla'
                Get-NetFirewallRule -ErrorAction SilentlyContinue |
                    Where-Object DisplayName -like "*$q*" |
                    Select-Object DisplayName, Direction, Action, Enabled |
                    Format-Table -AutoSize | Out-Host
                Wait-Key
            }
            default { }
        }
    }
}

# ==============================================================================
# [23] PUNTOS DE RESTAURACION
# ==============================================================================

function Get-RestorePointsScreen {
    Show-Header 'Puntos de restauracion'

    Write-Section 'Puntos existentes'
    $points = $null
    try { $points = Get-ComputerRestorePoint -ErrorAction Stop } catch { }
    if ($points) {
        $points | Select-Object SequenceNumber,
            @{n='Fecha';e={ [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) }},
            Description, RestorePointType |
            Sort-Object SequenceNumber -Descending | Format-Table -AutoSize | Out-Host
    } else {
        Write-Status 'No hay puntos de restauracion o la proteccion del sistema esta desactivada.' 'warn'
    }

    Write-Host ''
    Write-Host '  [1] Crear un punto de restauracion ahora' -ForegroundColor $script:T.Val
    Write-Host '  [2] Abrir el asistente de restauracion (rstrui)' -ForegroundColor $script:T.Val
    Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim

    switch (Read-Choice) {
        '1' {
            if (-not (Assert-Admin)) { Wait-Key; return }
            $desc = Read-Choice 'Descripcion del punto (Enter = generico)'
            if (-not $desc) { $desc = ("Manual {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) }
            try {
                Write-Status 'Creando punto de restauracion. Puede tardar un minuto...' 'work'
                Checkpoint-Computer -Description $desc -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
                Write-Status 'Punto de restauracion creado.' 'ok'
            } catch {
                Write-Status "No se pudo crear: $_" 'err'
                Write-Status 'Windows limita la creacion a uno cada 24 horas por defecto.' 'info'
            }
            Wait-Key
        }
        '2' { Start-Process rstrui.exe }
        default { }
    }
}

# ==============================================================================
# [24] WINDOWS UPDATE
# ==============================================================================

function Get-WindowsUpdateScreen {
    Show-Header 'Windows Update'

    Write-Section 'Estado general'
    try {
        $uso = Get-CimInstance -Namespace 'root\cimv2' -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        Write-KV 'Build actual' $uso.BuildNumber
    } catch { }

    try {
        $hist = Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop |
                Sort-Object InstalledOn -Descending | Select-Object -First 1
        if ($hist) { Write-KV 'Ultimo parche instalado' ("{0}  ({1})" -f $hist.HotFixID, $hist.InstalledOn) }
    } catch { }

    Write-Section 'Reinicio pendiente'
    $pending = Test-PendingRebootInternal
    if ($pending.Pending) {
        Write-Status 'Hay un reinicio pendiente. Reinicie cuando pueda para completar actualizaciones.' 'warn'
        foreach ($r in $pending.Razones) { Write-KV 'Motivo' $r $script:T.Warn }
    } else {
        Write-Status 'Sin reinicio pendiente detectado.' 'ok'
    }

    Write-Section 'Ultimos parches instalados'
    try {
        Get-CimInstance -ClassName Win32_QuickFixEngineering -ErrorAction Stop |
            Sort-Object InstalledOn -Descending | Select-Object -First 10 HotFixID, Description, InstalledOn |
            Format-Table -AutoSize | Out-Host
    } catch { Write-Status 'No se pudo leer el historial de parches.' 'warn' }

    Write-Host ''
    Write-Host '  [1] Buscar actualizaciones ahora (puede tardar varios minutos)' -ForegroundColor $script:T.Val
    Write-Host '  [2] Abrir Configuracion > Windows Update' -ForegroundColor $script:T.Val
    Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim

    switch (Read-Choice) {
        '1' {
            Write-Host ''
            Write-Status 'Consultando el servicio de Windows Update...' 'work'
            try {
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $result = $searcher.Search("IsInstalled=0 and IsHidden=0")
                if ($result.Updates.Count -eq 0) {
                    Write-Status 'No hay actualizaciones pendientes.' 'ok'
                } else {
                    Write-Status ("Actualizaciones disponibles: {0}" -f $result.Updates.Count) 'warn'
                    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
                        Write-Host ("  - {0}" -f $result.Updates.Item($i).Title) -ForegroundColor $script:T.Val
                    }
                    Write-Status 'Instale desde Configuracion > Windows Update.' 'info'
                }
            } catch {
                Write-Status "No se pudo consultar (requiere el servicio de Windows Update activo): $_" 'err'
            }
            Wait-Key
        }
        '2' { Start-Process 'ms-settings:windowsupdate' }
        default { }
    }
}

# ==============================================================================
# [25] ESTADO DE LICENCIAS (INFORMATIVO)
# ==============================================================================
# Solo lectura: consulta el estado real de activacion via las herramientas
# oficiales de Microsoft (slmgr para Windows, ospp.vbs para Office). No activa,
# no descarga, no ejecuta nada de terceros.

function Get-LicenseStatusScreen {
    Show-Header 'Estado de licencias'
    Write-Status 'Solo lectura: usa las herramientas oficiales de Microsoft.' 'info'

    Write-Section 'Windows'
    try {
        $out = cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli 2>&1
        $out | Out-Host
    } catch { Write-Status 'No se pudo consultar slmgr.vbs.' 'err' }

    Write-Section 'Microsoft Office'
    $osppCandidates = @(
        "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs",
        "$env:ProgramFiles\Microsoft Office\Office15\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office15\ospp.vbs"
    )
    $ospp = $osppCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($ospp) {
        try {
            $outOffice = cscript //nologo "$ospp" /dstatus 2>&1
            $outOffice | Out-Host
        } catch { Write-Status 'No se pudo consultar ospp.vbs.' 'err' }
    } else {
        Write-Status 'No se encontro ospp.vbs (Office no instalado o via Microsoft Store/Click-to-Run distinto).' 'warn'
    }

    Write-Host ''
    Write-Status 'Para reactivar o resolver licencias invalidas use los canales oficiales de Microsoft o contacte a soporte.' 'info'
    Wait-Key
}

# ==============================================================================
# [26] CONTROLADORES (DRIVERS)
# ==============================================================================

function Get-DriversScreen {
    Show-Header 'Controladores instalados'
    Write-Status 'Consultando drivers firmados...' 'work'

    $drivers = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
               Where-Object { $_.DeviceName } | Sort-Object DeviceName

    Write-KV 'Total' $drivers.Count

    Write-Section 'Listado (primeros 30)'
    $drivers | Select-Object -First 30 DeviceName, DriverVersion, Manufacturer,
        @{n='Fecha';e={ try { [datetime]$_.DriverDate } catch { $_.DriverDate } }} |
        Format-Table -AutoSize | Out-Host

    Write-Host ''
    Write-Host '  [1] Buscar driver' -ForegroundColor $script:T.Val
    Write-Host '  [2] Exportar lista completa a CSV' -ForegroundColor $script:T.Val
    Write-Host '  [3] Respaldar todos los drivers a una carpeta (pnputil)' -ForegroundColor $script:T.Val
    Write-Host '  [0] Volver' -ForegroundColor $script:T.Dim

    switch (Read-Choice) {
        '1' {
            $q = Read-Choice 'Texto a buscar'
            $drivers | Where-Object DeviceName -like "*$q*" |
                Select-Object DeviceName, DriverVersion, Manufacturer | Format-Table -AutoSize | Out-Host
            Wait-Key
        }
        '2' {
            $csv = Join-Path $script:Paths.Dir ("drivers_{0}_{1}.csv" -f $script:Ctx.Computer, $script:Ctx.Fecha)
            try {
                $drivers | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
                Write-Status ("Exportado: {0}" -f $csv) 'ok'
            } catch { Write-Status "Error: $_" 'err' }
            Wait-Key
        }
        '3' {
            if (-not (Assert-Admin)) { Wait-Key; return }
            $dest = Join-Path $script:Paths.Dir ("drivers_backup_{0}" -f $script:Ctx.Fecha)
            if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
            Write-Status 'Exportando drivers de terceros, puede tardar...' 'work'
            try {
                pnputil /export-driver * "$dest" | Out-Host
                Write-Status ("Respaldo en: {0}" -f $dest) 'ok'
            } catch { Write-Status "Error al ejecutar pnputil: $_" 'err' }
            Wait-Key
        }
        default { }
    }
}

# ==============================================================================
# [27] VARIABLES DE ENTORNO
# ==============================================================================

function Get-EnvironmentInfoScreen {
    Show-Header 'Variables de entorno'

    Write-Section 'PATH del sistema: revision de problemas'
    $pathSys = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $pathUser= [Environment]::GetEnvironmentVariable('Path', 'User')
    $allEntries = @()
    if ($pathSys)  { $allEntries += ($pathSys  -split ';' | Where-Object { $_ }) }
    if ($pathUser) { $allEntries += ($pathUser -split ';' | Where-Object { $_ }) }

    $dupes   = $allEntries | Group-Object | Where-Object Count -gt 1
    $missing = $allEntries | Select-Object -Unique | Where-Object { -not (Test-Path $_) }

    Write-KV 'Entradas totales'    $allEntries.Count
    Write-KV 'Entradas duplicadas' $dupes.Count $(if ($dupes.Count -gt 0) { $script:T.Warn } else { $script:T.Ok })
    Write-KV 'Rutas inexistentes'  $missing.Count $(if ($missing.Count -gt 0) { $script:T.Warn } else { $script:T.Ok })

    if ($dupes.Count -gt 0) {
        Write-Section 'Duplicadas'
        foreach ($d in $dupes) { Write-Host ("  {0}" -f $d.Name) -ForegroundColor $script:T.Warn }
    }
    if ($missing.Count -gt 0) {
        Write-Section 'Rutas que ya no existen (limpiar el PATH puede acelerar el arranque)'
        foreach ($m in $missing) { Write-Host ("  {0}" -f $m) -ForegroundColor $script:T.Dim }
    }

    Write-Section 'Otras variables comunes'
    foreach ($v in @('TEMP','TMP','USERPROFILE','APPDATA','LOCALAPPDATA','ProgramFiles','ProgramData','ComputerName','NUMBER_OF_PROCESSORS')) {
        Write-KV $v ([Environment]::GetEnvironmentVariable($v))
    }

    Write-Host ''
    if (Confirm-Action 'Ver el PATH completo?') {
        Write-Host ''
        $allEntries | Select-Object -Unique | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor $script:T.Val }
    }
    Wait-Key
}

# ==============================================================================
# [28] REINICIO PENDIENTE
# ==============================================================================

function Test-PendingRebootInternal {
    $razones = New-Object System.Collections.Generic.List[string]

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $razones.Add('Component Based Servicing (CBS)')
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $razones.Add('Windows Update')
    }
    try {
        $pfro = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction Stop
        if ($pfro) { $razones.Add('Operaciones de renombrado de archivos pendientes') }
    } catch { }
    try {
        $cbsRebootInProgress = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing' -Name 'RebootInProgress' -ErrorAction Stop
        if ($cbsRebootInProgress) { $razones.Add('Reinicio de CBS en progreso') }
    } catch { }

    return [pscustomobject]@{ Pending = ($razones.Count -gt 0); Razones = $razones }
}

function Get-PendingRebootScreen {
    Show-Header 'Reinicio pendiente'
    $r = Test-PendingRebootInternal

    if ($r.Pending) {
        Write-Status 'Este equipo tiene un reinicio pendiente.' 'warn'
        Write-Section 'Motivos detectados'
        foreach ($m in $r.Razones) { Write-Host ("  - {0}" -f $m) -ForegroundColor $script:T.Warn }
        Write-Host ''
        if (Confirm-Action 'Reiniciar el equipo ahora?') { Restart-Computer -Force }
    } else {
        Write-Status 'No se detecto ningun reinicio pendiente.' 'ok'
    }
    Wait-Key
}

# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================

function Write-MenuGroup {
    param([string]$Text)
    Write-Host ''
    Write-Host ("  {0} {1}" -f $script:B.Arrow, $Text.ToUpper()) -ForegroundColor $script:T.Accent
}

function Write-MenuPair {
    param([string]$N1, [string]$T1, [string]$N2, [string]$T2)
    Write-Host '   [' -ForegroundColor $script:T.Dim -NoNewline
    Write-Host $N1 -ForegroundColor $script:T.Num -NoNewline
    Write-Host '] ' -ForegroundColor $script:T.Dim -NoNewline
    Write-Host $T1.PadRight(32) -ForegroundColor $script:T.Val -NoNewline
    if ($N2) {
        Write-Host '[' -ForegroundColor $script:T.Dim -NoNewline
        Write-Host $N2 -ForegroundColor $script:T.Num -NoNewline
        Write-Host '] ' -ForegroundColor $script:T.Dim -NoNewline
        Write-Host $T2 -ForegroundColor $script:T.Val
    } else { Write-Host '' }
}

function Show-MainMenu {
    Show-Header
    Write-MenuGroup 'Diagnostico'
    Write-MenuPair '01' 'Informe completo a TXT'  '02' 'Informacion del sistema'
    Write-MenuPair '03' 'Red y conectividad'      '04' 'Almacenamiento y SMART'
    Write-MenuPair '05' 'Memoria RAM'             '06' 'Programas instalados'
    Write-MenuPair '07' 'Hardware'                '08' 'BIOS / UEFI / TPM'

    Write-MenuGroup 'Procesos, servicios e inicio'
    Write-MenuPair '09' 'Procesos en ejecucion'   '10' 'Servicios de Windows'
    Write-MenuPair '11' 'Programas de inicio'     '12' 'Tareas programadas'

    Write-MenuGroup 'Mantenimiento'
    Write-MenuPair '13' 'Analisis de canales WiFi' '14' 'Limpieza de red y DNS'
    Write-MenuPair '15' 'Reparar sistema SFC/DISM' '16' 'Visor de eventos'

    Write-MenuGroup 'Monitoreo'
    Write-MenuPair '17' 'Tarjeta grafica'          '18' 'Temperaturas'
    Write-MenuPair '19' 'Bateria (portatiles)'     '20' 'Exportar informe HTML'

    Write-MenuGroup 'Limpieza y seguridad'
    Write-MenuPair '21' 'Limpieza de temporales'   '22' 'Firewall y puertos'
    Write-MenuPair '23' 'Puntos de restauracion'   '24' 'Windows Update'

    Write-MenuGroup 'Utilidades adicionales'
    Write-MenuPair '25' 'Estado de licencias (solo lectura)' '26' 'Controladores (drivers)'
    Write-MenuPair '27' 'Variables de entorno'     '28' 'Reinicio pendiente'
    Write-MenuPair '29' '(reservado)'              '' ''

    Write-MenuGroup 'Herramienta'
    Write-MenuPair '30' 'Buscar actualizaciones'   '31' 'Config. de actualizaciones'
    Write-MenuPair '00' 'Salir'                    '' ''

    if ($script:Ctx.Update) {
        Write-Host ''
        Write-Status ("Hay una version nueva disponible ({0}). Use la opcion 30." -f $script:Ctx.Update.version) 'warn'
    }
    Write-Host ''
    Write-Rule
}

function Invoke-Main {
    $script:Ctx.IsAdmin = Test-Admin
    Import-AppConfig

    try { $Host.UI.RawUI.WindowTitle = "Multi Herramienta Tecnica v$script:Version" } catch { }

    if ($UpdatedRestart) {
        Show-Header
        Write-Status ("Actualizado correctamente a la version {0}" -f $script:Version) 'ok'
        Write-Log "Reinicio tras actualizacion a $script:Version"
        Start-Sleep -Seconds 2
    }

    if (-not $SkipUpdateCheck -and $script:Config.AutoCheck -and $script:Config.UpdateManifestUrl) {
        $m = Invoke-UpdateCheck -Quiet
        if ($m -and $m.mandatory) {
            Show-Header 'Actualizacion obligatoria'
            Write-Status ("El autor publico la version {0} como obligatoria." -f $m.version) 'warn'
            if ($m.notes) { Write-KV 'Cambios' $m.notes }
            Write-Host ''
            if (Confirm-Action 'Instalar ahora?') { Install-Update $m | Out-Null }
        }
    }

    while ($true) {
        Show-MainMenu
        $op = Read-Choice 'Seleccione una opcion'
        $norm = if ($op -match '^\d+$') { ([int]$op).ToString('00') } else { $op.Trim().ToUpper() }

        switch ($norm) {
            '01' { Get-FullDiagnostic }
            '02' { Get-SystemInfoScreen }
            '03' { Get-NetworkInfoScreen }
            '04' { Get-DiskInfoScreen }
            '05' { Get-RAMInfoScreen }
            '06' { Get-InstalledProgramsScreen }
            '07' { Get-HardwareInfoScreen }
            '08' { Get-BiosInfoScreen }
            '09' { Get-RunningProcessesScreen }
            '10' { Get-ServicesInfoScreen }
            '11' { Get-StartupProgramsScreen }
            '12' { Get-ScheduledTasksScreen }
            '13' { Get-WifiInfoScreen }
            '14' { Clear-NetworkScreen }
            '15' { Repair-SystemScreen }
            '16' { Get-SystemEventsScreen }
            '17' { Get-GPUInfoScreen }
            '18' { Get-TemperaturesScreen }
            '19' { Get-BatteryReportScreen }
            '20' { Export-ToHTMLScreen }
            '21' { Clear-TempFilesScreen }
            '22' { Get-FirewallScreen }
            '23' { Get-RestorePointsScreen }
            '24' { Get-WindowsUpdateScreen }
            '25' { Get-LicenseStatusScreen }
            '26' { Get-DriversScreen }
            '27' { Get-EnvironmentInfoScreen }
            '28' { Get-PendingRebootScreen }
            '29' {
                Write-Status 'Esta opcion esta reservada para una futura funcion.' 'info'
                Start-Sleep -Milliseconds 900
            }
            '30' { Show-UpdateScreen }
            '31' { Show-UpdateConfigScreen }
            '00' {
                Show-Header
                Write-Status 'Cerrando la herramienta.' 'info'
                return
            }
            'Q'  { return }
            default {
                Write-Status 'Opcion no valida.' 'err'
                Start-Sleep -Milliseconds 900
            }
        }
    }
}

# ==============================================================================
# ARRANQUE
# ==============================================================================

try {
    Invoke-Main
} catch {
    Write-Host ''
    Write-Host ("  ERROR NO CONTROLADO: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("  En: {0}" -f $_.InvocationInfo.PositionMessage) -ForegroundColor DarkGray
    Write-Log ("EXCEPCION: {0}" -f $_.Exception.Message) 'ERROR'
    Read-Host 'Presione Enter para salir'
} finally {
    try {
        $Host.UI.RawUI.ForegroundColor = $script:Ctx.OrigColors.FG
        $Host.UI.RawUI.BackgroundColor = $script:Ctx.OrigColors.BG
    } catch { }
}