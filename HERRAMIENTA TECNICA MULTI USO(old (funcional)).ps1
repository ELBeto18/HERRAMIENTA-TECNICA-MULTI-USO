# Multi Herramienta Tecnica - PowerShell
# Guardar como: herramienta_tecnica.ps1
# Ejecutar como administrador para todas las funciones
 
# Configuracion inicial
$ErrorActionPreference = "SilentlyContinue"
$host.UI.RawUI.WindowTitle = "Multi Herramienta Tecnica - PowerShell"
$host.UI.RawUI.ForegroundColor = "Green"
Clear-Host
 
# Variables globales
$global:ComputerName = $env:COMPUTERNAME
$global:UserName = $env:USERNAME
$global:Fecha = Get-Date -Format "yyyy-MM-dd"
$global:Hora = Get-Date -Format "HH-mm-ss"
$global:LogFile = "diagnostico_${Fecha}_${Hora}.txt"
 
# Funcion para mostrar encabezado
function Show-Header {
    Clear-Host
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "          HERRAMIENTA TECNICA MULTI USO - PowerShell version 1.2" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host "Equipo: $ComputerName   Usuario: $UserName  Creado por: BMA" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------" -ForegroundColor Cyan
}
 
# Funcion para el menu principal
function Show-Menu {
    Show-Header
    Write-Host "[01] Recolectar diagnostico general y guardar en TXT"
    Write-Host "[02] Informacion del sistema"
    Write-Host "[03] Datos de red y IP"
    Write-Host "[04] Espacio en disco"
    Write-Host "[05] Uso de RAM"
    Write-Host "[06] Programas instalados"
    Write-Host "[07] Informacion del hardware"
    Write-Host "[08] Informacion de la BIOS/UEFI"
    Write-Host "[09] Procesos en ejecucion"
    Write-Host "[10] Servicios de Windows"
    Write-Host "[11] Comprobar canales de red WiFi"
    Write-Host "[12] Limpieza de red y DNS"
    Write-Host "[13] Reparar archivos del sistema (SFC/DISM)"
    Write-Host "[14] Ver eventos del sistema"
    Write-Host "[15] Informacion de la GPU"
    Write-Host "[16] Temperaturas del sistema"
    Write-Host "[17] Reporte de bateria (Solo para laptops)"
    Write-Host "[18] Activador MSGrave"
    Write-Host "[19] Exportar todo a HTML"
    Write-Host "[20] Salir"
    Write-Host "==============================================================" -ForegroundColor Cyan
}
 
# Funcion 1: Recolectar diagnostico completo
function Get-FullDiagnostic {
    Show-Header
    Write-Host "Generando informe completo..." -ForegroundColor Yellow
    
    $diagnostico = @"
===============================================================
DIAGNOSTICO COMPLETO DEL SISTEMA
Equipo: $ComputerName
Usuario: $UserName
Fecha: $(Get-Date)
===============================================================
 
"@
    
    # Informacion del sistema
    $diagnostico += "`n=== INFORMACION DEL SISTEMA ==="
    $diagnostico += "`n$(systeminfo)"
    
    # Informacion de hardware
    $diagnostico += "`n`n=== INFORMACION DE HARDWARE ==="
    
    # CPU
    $cpu = Get-WmiObject Win32_Processor
    $diagnostico += "`n`n[PROCESADOR]"
    $diagnostico += "`nNombre: $($cpu.Name)"
    $diagnostico += "`nNucleos: $($cpu.NumberOfCores)"
    $diagnostico += "`nHilos: $($cpu.NumberOfLogicalProcessors)"
    $diagnostico += "`nVelocidad: $($cpu.MaxClockSpeed) MHz"
    
    # RAM
    $ram = Get-WmiObject Win32_ComputerSystem
    $diagnostico += "`n`n[MEMORIA RAM]"
    $diagnostico += "`nTotal: $([math]::Round($ram.TotalPhysicalMemory/1GB, 2)) GB"
    
    $os = Get-WmiObject Win32_OperatingSystem
    $diagnostico += "`nDisponible: $([math]::Round($os.FreePhysicalMemory/1MB, 2)) GB"
    $usedRAM = [math]::Round(($ram.TotalPhysicalMemory - $os.FreePhysicalMemory*1024)/1GB, 2)
    $diagnostico += "`nEn uso: $usedRAM GB"
    
    # Discos
    $diagnostico += "`n`n[DISCOS DUROS]"
    $discos = Get-WmiObject Win32_LogicalDisk | Where-Object {$_.DriveType -eq 3}
    foreach ($disco in $discos) {
        $diagnostico += "`n$($disco.DeviceID) - $($disco.VolumeName)"
        $diagnostico += "`n  Tamano: $([math]::Round($disco.Size/1GB, 2)) GB"
        $diagnostico += "`n  Libre: $([math]::Round($disco.FreeSpace/1GB, 2)) GB"
        $usedDisk = [math]::Round(($disco.Size - $disco.FreeSpace)/1GB, 2)
        $diagnostico += "`n  Usado: $usedDisk GB"
        $porcentajeLibre = [math]::Round(($disco.FreeSpace/$disco.Size)*100, 2)
        $diagnostico += "`n  % Libre: ${porcentajeLibre}%"
    }
    
    # Red
    $diagnostico += "`n`n=== INFORMACION DE RED ==="
    $adaptadores = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
    foreach ($adap in $adaptadores) {
        $diagnostico += "`n`n[$($adap.Name)]"
        $diagnostico += "`nEstado: $($adap.Status)"
        $diagnostico += "`nVelocidad: $($adap.LinkSpeed)"
        
        $config = Get-NetIPConfiguration -InterfaceAlias $adap.Name -ErrorAction SilentlyContinue
        if ($config) {
            $diagnostico += "`nIP: $($config.IPv4Address.IPAddress)"
            $diagnostico += "`nGateway: $($config.IPv4DefaultGateway.NextHop)"
            $diagnostico += "`nDNS: $($config.DNSServer.ServerAddresses -join ', ')"
        }
    }
    
    # Programas instalados
    $diagnostico += "`n`n=== PROGRAMAS INSTALADOS ==="
    $programas = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                   "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                 Where-Object {$_.DisplayName} |
                 Select-Object DisplayName, DisplayVersion, Publisher |
                 Sort-Object DisplayName
    
    foreach ($prog in $programas | Select-Object -First 50) {
        $diagnostico += "`n- $($prog.DisplayName) v$($prog.DisplayVersion)"
    }
    
    $totalProgramas = $programas.Count
    $diagnostico += "`n`n... y $(($totalProgramas - 50)) mas."
    
    # Guardar a archivo
    $diagnostico | Out-File -FilePath $global:LogFile -Encoding UTF8
    Write-Host "`nDiagnostico guardado en: $global:LogFile" -ForegroundColor Green
    Write-Host "Ubicacion: $(Get-Location)\$global:LogFile" -ForegroundColor Green
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 2: Informacion del sistema
function Get-SystemInfo {
    Show-Header
    Write-Host "=== INFORMACION DEL SISTEMA ===" -ForegroundColor Yellow
    systeminfo
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 3: Datos de red
function Get-NetworkInfo {
    Show-Header
    Write-Host "=== INFORMACION DE RED ===" -ForegroundColor Yellow
    
    # Direccion IP publica
    try {
        Write-Host "`nIP Publica: " -NoNewline
        $publicIP = Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5
        Write-Host $publicIP -ForegroundColor Green
    } catch {
        Write-Host "No disponible" -ForegroundColor Red
    }
    
    # Informacion local
    Write-Host "`n=== CONFIGURACION DE RED LOCAL ===" -ForegroundColor Cyan
    Get-NetIPConfiguration | Format-List
    
    # Adaptadores de red
    Write-Host "`n=== ADAPTADORES DE RED ===" -ForegroundColor Cyan
    Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, LinkSpeed -AutoSize
    
    # Conexiones activas
    Write-Host "`n=== CONEXIONES ACTIVAS ===" -ForegroundColor Cyan
    Get-NetTCPConnection -State Established | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, @{Name="Process";Expression={(Get-Process -Id $_.OwningProcess).ProcessName}} | Format-Table -AutoSize
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 4: Espacio en disco
function Get-DiskInfo {
    Show-Header
    Write-Host "=== INFORMACION DE DISCOS ===" -ForegroundColor Yellow
    
    # Discos logicos
    Write-Host "`n=== DISCOS LOGICOS ===" -ForegroundColor Cyan
    Get-WmiObject Win32_LogicalDisk | Where-Object {$_.DriveType -eq 3} |
        Select-Object DeviceID, VolumeName,
            @{Name="Size(GB)";Expression={[math]::Round($_.Size/1GB,2)}},
            @{Name="Free(GB)";Expression={[math]::Round($_.FreeSpace/1GB,2)}},
            @{Name="Free(%)";Expression={[math]::Round(($_.FreeSpace/$_.Size)*100,2)}} |
        Format-Table -AutoSize
    
    # Discos fisicos
    Write-Host "`n=== DISCOS FISICOS ===" -ForegroundColor Cyan
    Get-PhysicalDisk | Select-Object FriendlyName, MediaType, Size, HealthStatus, OperationalStatus |
        Format-Table -AutoSize
    
    # Particiones
    Write-Host "`n=== PARTICIONES ===" -ForegroundColor Cyan
    Get-Partition | Select-Object DriveLetter, Size, Type |
        Format-Table -AutoSize
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 5: Uso de RAM
function Get-RAMInfo {
    Show-Header
    Write-Host "=== INFORMACION DE MEMORIA RAM ===" -ForegroundColor Yellow
    
    # Informacion basica
    $os = Get-WmiObject Win32_OperatingSystem
    $cs = Get-WmiObject Win32_ComputerSystem
    
    $totalRAM = [math]::Round($cs.TotalPhysicalMemory/1GB, 2)
    $freeRAM = [math]::Round($os.FreePhysicalMemory/1MB, 2)
    $usedRAM = [math]::Round(($cs.TotalPhysicalMemory - ($os.FreePhysicalMemory * 1024))/1GB, 2)
    $percentUsed = [math]::Round(($usedRAM/$totalRAM)*100, 2)
    
    Write-Host "`nResumen:" -ForegroundColor Cyan
    Write-Host "Total RAM: $totalRAM GB" -ForegroundColor Green
    
    if ($percentUsed -gt 80) {
        Write-Host "RAM en uso: $usedRAM GB (${percentUsed}%)" -ForegroundColor Red
    } else {
        Write-Host "RAM en uso: $usedRAM GB (${percentUsed}%)" -ForegroundColor Green
    }
    
    Write-Host "RAM disponible: $freeRAM GB" -ForegroundColor Green
    
    # Modulos de memoria
    Write-Host "`n=== MODULOS DE MEMORIA ===" -ForegroundColor Cyan
    Get-WmiObject Win32_PhysicalMemory | Select-Object BankLabel,
        @{Name="Capacity(GB)";Expression={[math]::Round($_.Capacity/1GB,2)}},
        Speed, Manufacturer, PartNumber |
        Format-Table -AutoSize
    
    # Uso de memoria por proceso
    Write-Host "`n=== TOP 10 PROCESOS POR USO DE MEMORIA ===" -ForegroundColor Cyan
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 |
        Select-Object ProcessName, @{Name="Memory(MB)";Expression={[math]::Round($_.WorkingSet64/1MB,2)}}, CPU |
        Format-Table -AutoSize
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 6: Programas instalados
function Get-InstalledPrograms {
    Show-Header
    Write-Host "=== PROGRAMAS INSTALADOS ===" -ForegroundColor Yellow
    
    $programas = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                   "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                 Where-Object {$_.DisplayName} |
                 Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
                 Sort-Object DisplayName
    
    Write-Host "`nTotal de programas: $($programas.Count)" -ForegroundColor Cyan
    
    # Mostrar primeros 20
    $programas | Select-Object -First 20 | Format-Table DisplayName, DisplayVersion -AutoSize
    
    Write-Host "`nOpciones:" -ForegroundColor Cyan
    Write-Host "1. Ver mas programas"
    Write-Host "2. Buscar un programa especifico"
    Write-Host "3. Exportar lista completa a CSV"
    Write-Host "4. Volver al menu"
    
    $opcion = Read-Host "`nSeleccione una opcion"
    
    switch ($opcion) {
        "1" {
            $programas | Select-Object -Skip 20 -First 20 | Format-Table DisplayName, DisplayVersion -AutoSize
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-InstalledPrograms
        }
        "2" {
            $busqueda = Read-Host "`nIngrese nombre a buscar"
            $programas | Where-Object {$_.DisplayName -like "*$busqueda*"} | Format-Table DisplayName, DisplayVersion, Publisher -AutoSize
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-InstalledPrograms
        }
        "3" {
            $csvFile = "programas_instalados_${global:Fecha}.csv"
            $programas | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
            Write-Host "`nLista exportada a: $csvFile" -ForegroundColor Green
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "4" { return }
        default {
            Write-Host "Opcion no valida" -ForegroundColor Red
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-InstalledPrograms
        }
    }
}
 
# Funcion 7: Informacion del hardware
function Get-HardwareInfo {
    Show-Header
    Write-Host "=== INFORMACION DETALLADA DEL HARDWARE ===" -ForegroundColor Yellow
    
    # CPU
    Write-Host "`n=== PROCESADOR ===" -ForegroundColor Cyan
    $cpu = Get-WmiObject Win32_Processor
    $cpu | Select-Object Name, Manufacturer, NumberOfCores, 
        NumberOfLogicalProcessors, MaxClockSpeed, L2CacheSize, L3CacheSize |
        Format-List
    
    # Motherboard
    Write-Host "`n=== PLACA BASE ===" -ForegroundColor Cyan
    $board = Get-WmiObject Win32_BaseBoard
    $board | Select-Object Manufacturer, Product, SerialNumber |
        Format-List
    
    # GPU
    Write-Host "`n=== TARJETA GRAFICA ===" -ForegroundColor Cyan
    $gpu = Get-WmiObject Win32_VideoController
    $gpu | Select-Object Name, AdapterRAM, DriverVersion |
        Format-List
    
    # BIOS
    Write-Host "`n=== BIOS/UEFI ===" -ForegroundColor Cyan
    $bios = Get-WmiObject Win32_BIOS
    $bios | Select-Object Manufacturer, Name, Version, SerialNumber |
        Format-List
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 8: Informacion de la BIOS/UEFI
function Get-BiosInfo {
    Show-Header
    Write-Host "=== INFORMACION DE LA BIOS/UEFI ===" -ForegroundColor Yellow
    
    $bios = Get-WmiObject Win32_BIOS
    $bios | Format-List *
    
    Write-Host "`n=== MODO DE ARRANQUE ===" -ForegroundColor Cyan
    $firmware = Get-WmiObject Win32_ComputerSystem
    if ($firmware.BootupState -like "*UEFI*") {
        Write-Host "Modo: UEFI" -ForegroundColor Green
    } else {
        Write-Host "Modo: BIOS Legacy" -ForegroundColor Yellow
    }
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 9: Procesos en ejecucion
function Get-RunningProcesses {
    Show-Header
    Write-Host "=== PROCESOS EN EJECUCION ===" -ForegroundColor Yellow
    
    $processes = Get-Process | Sort-Object CPU -Descending
    
    Write-Host "`nTotal de procesos: $($processes.Count)" -ForegroundColor Cyan
    
    # Mostrar top 15 por CPU
    Write-Host "`n=== TOP 15 POR USO DE CPU ===" -ForegroundColor Cyan
    $processes | Select-Object -First 15 |
        Select-Object ProcessName, CPU, @{Name="Memory(MB)";Expression={[math]::Round($_.WorkingSet64/1MB,2)}}, Id, StartTime |
        Format-Table -AutoSize
    
    Write-Host "`nOpciones:" -ForegroundColor Cyan
    Write-Host "1. Ver todos los procesos"
    Write-Host "2. Finalizar un proceso"
    Write-Host "3. Actualizar lista"
    Write-Host "4. Volver al menu"
    
    $opcion = Read-Host "`nSeleccione una opcion"
    
    switch ($opcion) {
        "1" {
            $processes | Format-Table ProcessName, CPU, Id -AutoSize
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-RunningProcesses
        }
        "2" {
            $pidToKill = Read-Host "`nIngrese el ID del proceso a finalizar"
            try {
                Stop-Process -Id $pidToKill -Force
                Write-Host "Proceso finalizado correctamente" -ForegroundColor Green
            } catch {
                Write-Host "Error al finalizar el proceso: $_" -ForegroundColor Red
            }
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-RunningProcesses
        }
        "3" { Get-RunningProcesses }
        "4" { return }
        default {
            Write-Host "Opcion no valida" -ForegroundColor Red
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-RunningProcesses
        }
    }
}
 
# Funcion 10: Servicios de Windows
function Get-ServicesInfo {
    Show-Header
    Write-Host "=== SERVICIOS DE WINDOWS ===" -ForegroundColor Yellow
    
    Write-Host "`n=== SERVICIOS EN EJECUCION ===" -ForegroundColor Cyan
    Get-Service | Where-Object {$_.Status -eq "Running"} |
        Select-Object -First 20 | Format-Table DisplayName, Status, StartType -AutoSize
    
    Write-Host "`n=== SERVICIOS DETENIDOS ===" -ForegroundColor Cyan
    Get-Service | Where-Object {$_.Status -eq "Stopped"} |
        Select-Object -First 20 | Format-Table DisplayName, Status, StartType -AutoSize
    
    Write-Host "`nOpciones:" -ForegroundColor Cyan
    Write-Host "1. Iniciar un servicio"
    Write-Host "2. Detener un servicio"
    Write-Host "3. Buscar servicio"
    Write-Host "4. Volver al menu"
    
    $opcion = Read-Host "`nSeleccione una opcion"
    
    switch ($opcion) {
        "1" {
            $serviceName = Read-Host "`nIngrese el nombre del servicio a iniciar"
            try {
                Start-Service -Name $serviceName
                Write-Host "Servicio iniciado correctamente" -ForegroundColor Green
            } catch {
                Write-Host "Error: $_" -ForegroundColor Red
            }
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-ServicesInfo
        }
        "2" {
            $serviceName = Read-Host "`nIngrese el nombre del servicio a detener"
            try {
                Stop-Service -Name $serviceName
                Write-Host "Servicio detenido correctamente" -ForegroundColor Green
            } catch {
                Write-Host "Error: $_" -ForegroundColor Red
            }
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-ServicesInfo
        }
        "3" {
            $search = Read-Host "`nIngrese nombre a buscar"
            Get-Service | Where-Object {$_.DisplayName -like "*$search*"} |
                Format-Table DisplayName, Status, StartType -AutoSize
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-ServicesInfo
        }
        "4" { return }
        default {
            Write-Host "Opcion no valida" -ForegroundColor Red
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-ServicesInfo
        }
    }
}
 
# Funcion 11: Redes WiFi
function Get-WifiInfo {
    Show-Header
    Write-Host "=== REDES WIFI DISPONIBLES ===" -ForegroundColor Yellow
    
    # Verificar si hay interfaz WiFi
    $wifiAdapter = Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "*Wi-Fi*" -or $_.Name -like "*Wi-Fi*"}
    
    if (-not $wifiAdapter) {
        Write-Host "No se encontro adaptador WiFi" -ForegroundColor Red
        Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }
    
    Write-Host "`nAdaptador WiFi: $($wifiAdapter.Name)" -ForegroundColor Cyan
    
    try {
        # Usar netsh para compatibilidad
        $wifiNetworks = netsh wlan show networks mode=bssid
        Write-Host "`n$wifiNetworks"
    } catch {
        Write-Host "Error al obtener redes WiFi. Ejecute como administrador." -ForegroundColor Red
    }
    
    Write-Host "`nOpciones:" -ForegroundColor Cyan
    Write-Host "1. Guardar informacion en archivo"
    Write-Host "2. Ver contrasenas WiFi guardadas (necesita admin)"
    Write-Host "3. Volver al menu"
    
    $opcion = Read-Host "`nSeleccione una opcion"
    
    switch ($opcion) {
        "1" {
            $wifiNetworks | Out-File -FilePath "wifi_redes_${global:Fecha}.txt" -Encoding UTF8
            Write-Host "Informacion guardada en: wifi_redes_${global:Fecha}.txt" -ForegroundColor Green
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "2" {
            try {
                $profiles = netsh wlan show profiles
                Write-Host "`nPerfiles WiFi guardados:"
                Write-Host $profiles
                
                $profileName = Read-Host "`nIngrese el nombre del perfil para ver la clave"
                if ($profileName) {
                    $key = netsh wlan show profile name="$profileName" key=clear | Select-String "Contenido de la clave"
                    Write-Host "Clave: $key" -ForegroundColor Green
                }
            } catch {
                Write-Host "Ejecute como administrador para esta funcion" -ForegroundColor Red
            }
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "3" { return }
        default {
            Write-Host "Opcion no valida" -ForegroundColor Red
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-WifiInfo
        }
    }
}
 
# Funcion 12: Limpieza de red
function Clear-Network {
    Show-Header
    Write-Host "=== LIMPIEZA DE RED Y DNS ===" -ForegroundColor Yellow
    Write-Host "`nADVERTENCIA: Requiere ejecucion como Administrador" -ForegroundColor Red
    
    Write-Host "`nOpciones:" -ForegroundColor Cyan
    Write-Host "1. Limpieza basica de DNS"
    Write-Host "2. Limpieza completa de red"
    Write-Host "3. Reiniciar adaptadores de red"
    Write-Host "4. Volver al menu"
    
    $opcion = Read-Host "`nSeleccione una opcion"
    
    switch ($opcion) {
        "1" {
            Write-Host "`nLimpiando DNS..." -ForegroundColor Yellow
            ipconfig /flushdns
            Write-Host "DNS limpiado correctamente" -ForegroundColor Green
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "2" {
            Write-Host "`nIniciando limpieza completa de red..." -ForegroundColor Yellow
            ipconfig /release
            ipconfig /renew
            ipconfig /flushdns
            netsh winsock reset
            netsh int ip reset
            Write-Host "`nLimpieza completada. Reinicie el equipo para aplicar todos los cambios." -ForegroundColor Green
            
            $reiniciar = Read-Host "`nDesea reiniciar ahora? (S/N)"
            if ($reiniciar -eq "S" -or $reiniciar -eq "s") {
                Restart-Computer -Force
            }
            
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "3" {
            Write-Host "`nReiniciando adaptadores de red..." -ForegroundColor Yellow
            Get-NetAdapter | Restart-NetAdapter -Confirm:$false
            Write-Host "Adaptadores reiniciados" -ForegroundColor Green
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "4" { return }
        default {
            Write-Host "Opcion no valida" -ForegroundColor Red
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Clear-Network
        }
    }
}
 
# Funcion 13: Reparar sistema
function Repair-System {
    Show-Header
    Write-Host "=== REPARACION DEL SISTEMA ===" -ForegroundColor Yellow
    Write-Host "`nADVERTENCIA: Requiere ejecucion como Administrador" -ForegroundColor Red
    
    Write-Host "`nOpciones:" -ForegroundColor Cyan
    Write-Host "1. Comprobar archivos del sistema (SFC /verifyonly)"
    Write-Host "2. Reparar archivos del sistema (SFC /scannow)"
    Write-Host "3. Reparar con DISM"
    Write-Host "4. Verificar integridad del almacen de componentes"
    Write-Host "5. Volver al menu"
    
    $opcion = Read-Host "`nSeleccione una opcion"
    
    switch ($opcion) {
        "1" {
            Write-Host "`nComprobando archivos del sistema..." -ForegroundColor Yellow
            sfc /verifyonly
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Repair-System
        }
        "2" {
            Write-Host "`nReparando archivos del sistema..." -ForegroundColor Yellow
            sfc /scannow
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Repair-System
        }
        "3" {
            Write-Host "`nReparando con DISM..." -ForegroundColor Yellow
            DISM.exe /Online /Cleanup-Image /RestoreHealth
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Repair-System
        }
        "4" {
            Write-Host "`nVerificando integridad del almacen de componentes..." -ForegroundColor Yellow
            DISM.exe /Online /Cleanup-Image /CheckHealth
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Repair-System
        }
        "5" { return }
        default {
            Write-Host "Opcion no valida" -ForegroundColor Red
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Repair-System
        }
    }
}
 
# Funcion 14: Eventos del sistema
function Get-SystemEvents {
    Show-Header
    Write-Host "=== EVENTOS DEL SISTEMA ===" -ForegroundColor Yellow
    
    Write-Host "`nOpciones:" -ForegroundColor Cyan
    Write-Host "1. Ver errores criticos (ultimas 24 horas)"
    Write-Host "2. Ver advertencias (ultimas 24 horas)"
    Write-Host "3. Ver eventos de inicio/apagado"
    Write-Host "4. Volver al menu"
    
    $opcion = Read-Host "`nSeleccione una opcion"
    
    $fechaInicio = (Get-Date).AddHours(-24)
    
    switch ($opcion) {
        "1" {
            Write-Host "`n=== ERRORES CRITICOS (Ultimas 24 horas) ===" -ForegroundColor Red
            Get-WinEvent -FilterHashtable @{LogName='System'; Level=1; StartTime=$fechaInicio} -MaxEvents 20 |
                Select-Object TimeCreated, ProviderName, Id, Message |
                Format-Table -AutoSize -Wrap
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-SystemEvents
        }
        "2" {
            Write-Host "`n=== ADVERTENCIAS (Ultimas 24 horas) ===" -ForegroundColor Yellow
            Get-WinEvent -FilterHashtable @{LogName='System'; Level=3; StartTime=$fechaInicio} -MaxEvents 20 |
                Select-Object TimeCreated, ProviderName, Id, Message |
                Format-Table -AutoSize -Wrap
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-SystemEvents
        }
        "3" {
            Write-Host "`n=== EVENTOS DE INICIO/APAGADO ===" -ForegroundColor Cyan
            Get-WinEvent -FilterHashtable @{LogName='System'; Id=6005,6006,6008} -MaxEvents 10 |
                Select-Object TimeCreated, Id, @{Name="Evento";Expression={
                    switch ($_.Id) {
                        6005 { "Inicio del sistema" }
                        6006 { "Apagado del sistema" }
                        6008 { "Apagado inesperado" }
                    }
                }} | Format-Table -AutoSize
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-SystemEvents
        }
        "4" { return }
        default {
            Write-Host "Opcion no valida" -ForegroundColor Red
            Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            Get-SystemEvents
        }
    }
}
 
# Funcion 15: Informacion de la GPU mejorada
function Get-GPUInfo {
    Show-Header
    Write-Host "=== INFORMACION DE LA GPU ===" -ForegroundColor Yellow
    
    Write-Host "`nObteniendo informacion de tarjetas graficas..." -ForegroundColor Cyan
    
    try {
        # Metodo 1: Usar WMI (mas compatible)
        $gpu = Get-WmiObject Win32_VideoController -ErrorAction SilentlyContinue
        
        if ($gpu) {
            Write-Host "`n=== TARJETAS GRAFICAS DETECTADAS ===" -ForegroundColor Green
            
            $counter = 1
            foreach ($g in $gpu) {
                Write-Host "`n[GPU $counter]" -ForegroundColor Cyan
                Write-Host "Nombre: $($g.Name)" -ForegroundColor White
                
                if ($g.AdapterCompatibility) {
                    Write-Host "Fabricante: $($g.AdapterCompatibility)" -ForegroundColor Gray
                }
                
                # Calcular memoria en GB
                if ($g.AdapterRAM -ne $null -and $g.AdapterRAM -gt 0) {
                    $ramGB = [math]::Round($g.AdapterRAM/1GB, 2)
                    Write-Host "Memoria dedicada: $ramGB GB" -ForegroundColor Green
                } else {
                    Write-Host "Memoria: Compartida con sistema" -ForegroundColor Yellow
                }
                
                if ($g.VideoProcessor) {
                    Write-Host "Procesador: $($g.VideoProcessor)" -ForegroundColor Gray
                }
                
                if ($g.DriverVersion) {
                    Write-Host "Driver: $($g.DriverVersion)" -ForegroundColor Gray
                }
                
                if ($g.VideoModeDescription) {
                    Write-Host "Resolucion actual: $($g.VideoModeDescription)" -ForegroundColor Gray
                }
                
                $counter++
            }
        } else {
            Write-Host "No se pudo obtener informacion de GPU via WMI" -ForegroundColor Yellow
        }
        
        # Metodo 2: Intentar con Get-CimInstance (mas moderno)
        try {
            Write-Host "`n=== INFORMACION ADICIONAL ===" -ForegroundColor Cyan
            $cimGPU = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
            
            if ($cimGPU) {
                foreach ($cg in $cimGPU) {
                    if ($cg.CurrentHorizontalResolution -and $cg.CurrentVerticalResolution) {
                        Write-Host "Resolucion: $($cg.CurrentHorizontalResolution)x$($cg.CurrentVerticalResolution)" -ForegroundColor Gray
                    }
                    
                    if ($cg.CurrentRefreshRate -gt 0) {
                        Write-Host "Refresh Rate: $($cg.CurrentRefreshRate) Hz" -ForegroundColor Gray
                    }
                    
                    if ($cg.CurrentBitsPerPixel) {
                        Write-Host "Bits por pixel: $($cg.CurrentBitsPerPixel)" -ForegroundColor Gray
                    }
                }
            }
        } catch {
            # Silenciar error
        }
        
    } catch {
        Write-Host "Error al obtener informacion de GPU: $_" -ForegroundColor Red
    }
    
    # Informacion adicional con DirectX
    Write-Host "`n=== INFORMACION DIRECTX ===" -ForegroundColor Cyan
    try {
        # Verificar DirectX
        $dxPath = "HKLM:\SOFTWARE\Microsoft\DirectX"
        if (Test-Path $dxPath) {
            $dxVersion = Get-ItemProperty -Path $dxPath -Name "Version" -ErrorAction SilentlyContinue
            if ($dxVersion.Version) {
                Write-Host "DirectX instalado: Version $($dxVersion.Version)" -ForegroundColor Green
            }
        }
        
        # Verificar DirectX mediante archivos del sistema
        $dxdll = "$env:SystemRoot\System32\d3dx9_43.dll"
        if (Test-Path $dxdll) {
            $dxFile = Get-Item $dxdll
            Write-Host "DirectX 9: Instalado" -ForegroundColor Green
        }
        
        # Verificar si hay problemas conocidos
        $dxdiagInfo = Get-ChildItem "$env:SystemRoot\System32\dxdiag.exe" -ErrorAction SilentlyContinue
        if ($dxdiagInfo) {
            Write-Host "Herramienta DXDiag: Disponible" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "Informacion DirectX no disponible" -ForegroundColor Yellow
    }
    
    # Comprobar drivers de NVIDIA
    Write-Host "`n=== DRIVERS DE GPU ===" -ForegroundColor Cyan
    try {
        # Verificar NVIDIA
        $nvidiaPath = "HKLM:\SOFTWARE\NVIDIA Corporation\Global\NVTweak"
        if (Test-Path $nvidiaPath) {
            Write-Host "Controlador NVIDIA detectado" -ForegroundColor Green
        }
        
        # Verificar AMD
        $amdPath = "HKLM:\SOFTWARE\AMD"
        if (Test-Path $amdPath) {
            Write-Host "Controlador AMD detectado" -ForegroundColor Green
        }
        
        # Verificar Intel Graphics
        $intelPath = "HKLM:\SOFTWARE\Intel\GMM"
        if (Test-Path $intelPath) {
            Write-Host "Graficos Intel detectados" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "No se pudieron verificar drivers especificos" -ForegroundColor Yellow
    }
    
    # Recomendaciones
    Write-Host "`n=== RECOMENDACIONES ===" -ForegroundColor Cyan
    Write-Host "1. Mantenga los drivers de graficos actualizados" -ForegroundColor Yellow
    Write-Host "2. Use DirectX Diagnostic Tool (dxdiag) para mas informacion" -ForegroundColor Yellow
    Write-Host "3. Verifique temperaturas si experimenta problemas de rendimiento" -ForegroundColor Yellow
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 16: Temperaturas del sistema mejorada
function Get-Temperatures {
    Show-Header
    Write-Host "=== MONITOR DE TEMPERATURAS ===" -ForegroundColor Yellow
    Write-Host "`nNOTA: Esta funcion puede no estar disponible en todos los sistemas" -ForegroundColor Cyan
    
    $temperatureData = @()
    $fanData = @()
    
    Write-Host "`n[1/4] Buscando sensores de temperatura..." -ForegroundColor Gray
    
    # Metodo 1: WMI Standard
    try {
        $temperatures = Get-WmiObject -Namespace "root\wmi" -Class "MSAcpi_ThermalZoneTemperature" -ErrorAction SilentlyContinue
        
        if ($temperatures) {
            Write-Host "`nSensores WMI encontrados" -ForegroundColor Green
            
            foreach ($temp in $temperatures) {
                if ($temp.CurrentTemperature -ne $null) {
                    # Convertir de decimas de Kelvin a Celsius
                    $celsius = ($temp.CurrentTemperature - 2732) / 10
                    $temperatureData += @{
                        Source = "WMI Thermal Zone"
                        Temperature = $celsius
                        Unit = "C"
                    }
                    
                    Write-Host "`n  Temperatura: $celsius C" -ForegroundColor White
                    
                    # Evaluar temperatura
                    if ($celsius -gt 85) {
                        Write-Host "  Estado: CRITICO! Temperatura muy alta" -ForegroundColor Red -BackgroundColor Black
                    } elseif ($celsius -gt 75) {
                        Write-Host "  Estado: ALTA - Considere revisar refrigeracion" -ForegroundColor Yellow
                    } elseif ($celsius -gt 60) {
                        Write-Host "  Estado: Normal-Alta" -ForegroundColor Green
                    } else {
                        Write-Host "  Estado: Normal" -ForegroundColor Green
                    }
                }
            }
        } else {
            Write-Host "No se encontraron sensores WMI estandar" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Error en sensores WMI: $_" -ForegroundColor Red
    }
    
    # Metodo 2: Open Hardware Monitor WMI (si esta instalado)
    Write-Host "`n[2/4] Buscando Open Hardware Monitor..." -ForegroundColor Gray
    try {
        $ohmTemps = Get-WmiObject -Namespace "root\OpenHardwareMonitor" -Class "Sensor" -Filter "SensorType='Temperature'" -ErrorAction SilentlyContinue
        
        if ($ohmTemps) {
            Write-Host "Open Hardware Monitor detectado" -ForegroundColor Green
            
            foreach ($ohm in $ohmTemps | Select-Object -First 5) {
                $temperatureData += @{
                    Source = "OHM: $($ohm.Name)"
                    Temperature = $ohm.Value
                    Unit = "C"
                }
                
                Write-Host "`n  $($ohm.Name): $($ohm.Value) C" -ForegroundColor White
            }
        } else {
            Write-Host "Open Hardware Monitor no detectado" -ForegroundColor Yellow
        }
    } catch {
        # Silenciar error si no esta instalado
    }
    
    # Metodo 3: Lectura de BIOS/UEFI
    Write-Host "`n[3/4] Consultando informacion de BIOS..." -ForegroundColor Gray
    try {
        $biosInfo = Get-WmiObject Win32_BIOS -ErrorAction SilentlyContinue
        if ($biosInfo) {
            Write-Host "Informacion de BIOS disponible" -ForegroundColor Green
            
            $cpuInfo = Get-WmiObject Win32_PerfFormattedData_Counters_ProcessorInformation | 
                       Where-Object {$_.Name -like "*_Total"} | 
                       Select-Object -First 1
            
            if ($cpuInfo) {
                Write-Host "  Informacion de procesador disponible" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "Error al consultar BIOS" -ForegroundColor Yellow
    }
    
    # Metodo 4: Informacion de ventiladores
    Write-Host "`n[4/4] Buscando informacion de ventiladores..." -ForegroundColor Gray
    try {
        $fans = Get-WmiObject -Namespace "root\wmi" -Class "MSAcpi_Fan" -ErrorAction SilentlyContinue
        
        if ($fans) {
            Write-Host "Ventiladores detectados" -ForegroundColor Green
            foreach ($fan in $fans) {
                $status = if ($fan.Active) { "ACTIVO" } else { "INACTIVO" }
                $color = if ($fan.Active) { "Green" } else { "Red" }
                
                Write-Host "  Ventilador: $status" -ForegroundColor $color
                
                $fanData += @{
                    Status = $status
                    Active = $fan.Active
                }
            }
        } else {
            Write-Host "No se encontro informacion de ventiladores" -ForegroundColor Yellow
            
            try {
                $fanAlt = Get-WmiObject -Class Win32_Fan -ErrorAction SilentlyContinue
                if ($fanAlt) {
                    Write-Host "  Ventiladores encontrados via metodo alternativo" -ForegroundColor Green
                }
            } catch {
                # Silenciar error
            }
        }
    } catch {
        Write-Host "Error al leer ventiladores" -ForegroundColor Red
    }
    
    # Resumen
    Write-Host "`n" + ("="*60) -ForegroundColor Cyan
    Write-Host "RESUMEN DE TEMPERATURAS" -ForegroundColor Yellow
    
    if ($temperatureData.Count -gt 0) {
        Write-Host "`nTotal de sensores encontrados: $($temperatureData.Count)" -ForegroundColor Green
        
        $totalTemp = 0
        foreach ($temp in $temperatureData) {
            $totalTemp += $temp.Temperature
        }
        $averageTemp = [math]::Round($totalTemp / $temperatureData.Count, 1)
        
        Write-Host "Temperatura promedio: $averageTemp C" -ForegroundColor White
        
        if ($averageTemp -gt 80) {
            Write-Host "ADVERTENCIA! Temperatura general muy alta" -ForegroundColor Red -BackgroundColor Black
        } elseif ($averageTemp -gt 70) {
            Write-Host "Temperatura general elevada" -ForegroundColor Yellow
        } else {
            Write-Host "Temperatura general normal" -ForegroundColor Green
        }
    } else {
        Write-Host "No se obtuvieron lecturas de temperatura" -ForegroundColor Yellow
    }
    
    if ($fanData.Count -gt 0) {
        $activeFans = $fanData | Where-Object { $_.Active -eq $true } | Measure-Object | Select-Object -ExpandProperty Count
        Write-Host "`nVentiladores activos: $activeFans de $($fanData.Count)" -ForegroundColor White
    }
    
    if ($temperatureData.Count -eq 0) {
        Write-Host "`n=== SOLUCIONES ALTERNATIVAS ===" -ForegroundColor Cyan
        Write-Host "1. Ejecutar como Administrador puede dar mas acceso" -ForegroundColor Yellow
        Write-Host "2. Instalar Open Hardware Monitor (gratuito)" -ForegroundColor Yellow
        Write-Host "3. Usar software del fabricante (SpeedFan, HWMonitor)" -ForegroundColor Yellow
        Write-Host "4. Consultar temperaturas en BIOS/UEFI al arrancar" -ForegroundColor Yellow
        Write-Host "5. Verificar fisicamente los ventiladores" -ForegroundColor Yellow
    }
    
    Write-Host "`n=== RECOMENDACIONES GENERALES ===" -ForegroundColor Cyan
    Write-Host "Temperaturas seguras para CPU:" -ForegroundColor Green
    Write-Host "   - Ideal: 30-60C" -ForegroundColor White
    Write-Host "   - Aceptable: 60-75C" -ForegroundColor Yellow
    Write-Host "   - Peligroso: >85C" -ForegroundColor Red
    
    Write-Host "`nMantenimiento preventivo:" -ForegroundColor Green
    Write-Host "   1. Limpiar el polvo cada 3-6 meses" -ForegroundColor White
    Write-Host "   2. Verificar que todos los ventiladores giren" -ForegroundColor White
    Write-Host "   3. Cambiar pasta termica cada 2-3 anos" -ForegroundColor White
    Write-Host "   4. Mantener buena ventilacion del equipo" -ForegroundColor White
    
    Write-Host "`nSintomas de sobrecalentamiento:" -ForegroundColor Green
    Write-Host "   - Apagados repentinos" -ForegroundColor White
    Write-Host "   - Rendimiento reducido" -ForegroundColor White
    Write-Host "   - Ventiladores a maxima velocidad constantemente" -ForegroundColor White
    Write-Host "   - Artefactos graficos (en pantalla)" -ForegroundColor White
    
    Write-Host "`n=== DIAGNOSTICO AVANZADO ===" -ForegroundColor Cyan
    Write-Host "Para mas informacion, puede ejecutar:" -ForegroundColor Yellow
    Write-Host "1. En BIOS/UEFI: Ver opciones de Hardware Monitor" -ForegroundColor White
    Write-Host "2. En Windows: Descargar HWMonitor de CPUID" -ForegroundColor White
    Write-Host "3. Para laptops: Usar software del fabricante" -ForegroundColor White
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 17: Reporte de bateria (Solo para laptops)
function Get-BatteryReport {
    Show-Header
    Write-Host "=== REPORTE DE BATERIA ===" -ForegroundColor Yellow
    Write-Host "`nNOTA: Esta funcion esta disenada especificamente para laptops" -ForegroundColor Cyan
    
    $computerSystem = Get-WmiObject Win32_ComputerSystem
    if ($computerSystem.PCSystemType -eq 2) {
        Write-Host "Equipo portatil detectado" -ForegroundColor Green
        Write-Host "Generando reporte de bateria en el escritorio..." -ForegroundColor Yellow
        
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $batteryReportFile = "$desktopPath\battery_report_${global:Fecha}_${global:Hora}.html"
        
        try {
            powercfg /batteryreport /output "$batteryReportFile"
            
            if (Test-Path $batteryReportFile) {
                Write-Host "`nReporte de bateria generado exitosamente!" -ForegroundColor Green
                Write-Host "Ubicacion: $batteryReportFile" -ForegroundColor Cyan
                
                Write-Host "`n=== INFORMACION BASICA DE LA BATERIA ===" -ForegroundColor Cyan
                $battery = Get-WmiObject Win32_Battery -ErrorAction SilentlyContinue
                if ($battery) {
                    Write-Host "Estado: $($battery.BatteryStatus)" -ForegroundColor White
                    Write-Host "Capacidad restante: $($battery.EstimatedChargeRemaining)%" -ForegroundColor White
                    Write-Host "Tiempo restante: $([math]::Round($battery.EstimatedRunTime/60, 1)) horas" -ForegroundColor White
                    
                    if ($battery.EstimatedChargeRemaining -lt 20) {
                        Write-Host "ADVERTENCIA: Bateria baja!" -ForegroundColor Red
                    }
                } else {
                    Write-Host "No se pudo obtener informacion detallada de la bateria" -ForegroundColor Yellow
                }
                
                $abrir = Read-Host "`nDesea abrir el reporte de bateria en el navegador? (S/N)"
                if ($abrir -eq "S" -or $abrir -eq "s") {
                    Start-Process $batteryReportFile
                }
            } else {
                Write-Host "Error: No se pudo generar el reporte de bateria" -ForegroundColor Red
            }
        } catch {
            Write-Host "Error al generar el reporte: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Este no parece ser un equipo portatil/laptop." -ForegroundColor Red
        Write-Host "PCSystemType: $($computerSystem.PCSystemType)" -ForegroundColor Yellow
        Write-Host "Esta funcion esta disenada solo para laptops." -ForegroundColor Red
    }
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 18: Activador MSGrave
function Invoke-MSGrave {
    Show-Header
    Write-Host "=== ACTIVADOR MSGRAVE ===" -ForegroundColor Yellow
    Write-Host "`nADVERTENCIA: Requiere ejecucion como Administrador" -ForegroundColor Red
    Write-Host "`nEste proceso descargara y ejecutara el activador MSGrave." -ForegroundColor Cyan
    Write-Host "Asegurese de tener conexion a Internet antes de continuar." -ForegroundColor Cyan
    
    $confirmar = Read-Host "`nDesea continuar con la activacion? (S/N)"
    
    if ($confirmar -eq "S" -or $confirmar -eq "s") {
        Write-Host "`nIniciando activador MSGrave..." -ForegroundColor Yellow
        try {
            irm https://get.activated.win | iex
            Write-Host "`nProceso de activacion finalizado." -ForegroundColor Green
        } catch {
            Write-Host "`nError al ejecutar el activador: $_" -ForegroundColor Red
            Write-Host "Verifique su conexion a Internet y que este ejecutando como Administrador." -ForegroundColor Yellow
        }
    } else {
        Write-Host "`nActivacion cancelada." -ForegroundColor Yellow
    }
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion 19: Exportar a HTML mejorado
function Export-ToHTML {
    Show-Header
    Write-Host "=== EXPORTAR INFORMACION A HTML ===" -ForegroundColor Yellow
    
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $htmlFile = "$desktopPath\informe_sistema_${global:Fecha}_${global:Hora}.html"
    
    Write-Host "`nGenerando informe HTML profesional..." -ForegroundColor Yellow
    Write-Host "Por favor espere, esto puede tomar un momento..." -ForegroundColor Gray
    
    $htmlContent = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Informe Tecnico del Sistema - $global:ComputerName</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .header {
            background: linear-gradient(to right, #2c3e50, #4a6491);
            color: white;
            padding: 30px;
            border-radius: 15px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            position: relative;
            overflow: hidden;
        }
        
        .header::before {
            content: '';
            position: absolute;
            top: -50%;
            right: -50%;
            width: 200%;
            height: 200%;
            background: radial-gradient(circle, rgba(255,255,255,0.1) 1px, transparent 1px);
            background-size: 30px 30px;
            opacity: 0.1;
            animation: float 20s linear infinite;
        }
        
        @keyframes float {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            color: #fff;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .header-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin-top: 20px;
            padding: 20px;
            background: rgba(255,255,255,0.1);
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
        
        .info-item {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .info-item i {
            font-size: 1.2em;
            color: #4ecdc4;
        }
        
        .card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 25px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.1);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 25px rgba(0,0,0,0.15);
        }
        
        .card-title {
            color: #2c3e50;
            font-size: 1.5em;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 3px solid #3498db;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .card-title i {
            color: #3498db;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        
        .stat-box {
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            border-left: 5px solid #3498db;
        }
        
        .stat-value {
            font-size: 2.2em;
            font-weight: bold;
            color: #2c3e50;
            margin: 10px 0;
        }
        
        .stat-label {
            color: #666;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .progress-bar {
            height: 8px;
            background: #ecf0f1;
            border-radius: 4px;
            margin: 10px 0;
            overflow: hidden;
        }
        
        .progress {
            height: 100%;
            background: linear-gradient(to right, #2ecc71, #3498db);
            border-radius: 4px;
            transition: width 1s ease;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        
        th {
            background: linear-gradient(to right, #2c3e50, #3498db);
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 600;
        }
        
        td {
            padding: 15px;
            border-bottom: 1px solid #eee;
        }
        
        tr:nth-child(even) {
            background-color: #f8f9fa;
        }
        
        tr:hover {
            background-color: #e3f2fd;
        }
        
        .badge {
            display: inline-block;
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
            text-transform: uppercase;
        }
        
        .badge-success {
            background: linear-gradient(to right, #2ecc71, #27ae60);
            color: white;
        }
        
        .badge-warning {
            background: linear-gradient(to right, #f39c12, #e67e22);
            color: white;
        }
        
        .badge-danger {
            background: linear-gradient(to right, #e74c3c, #c0392b);
            color: white;
        }
        
        .badge-info {
            background: linear-gradient(to right, #3498db, #2980b9);
            color: white;
        }
        
        .alert {
            padding: 15px;
            border-radius: 10px;
            margin: 15px 0;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .alert-info {
            background: #e3f2fd;
            border-left: 5px solid #2196f3;
        }
        
        .alert-warning {
            background: #fff3e0;
            border-left: 5px solid #ff9800;
        }
        
        .alert-success {
            background: #e8f5e9;
            border-left: 5px solid #4caf50;
        }
        
        .footer {
            text-align: center;
            padding: 30px;
            margin-top: 50px;
            color: #fff;
            font-size: 0.9em;
            opacity: 0.8;
        }
        
        @media print {
            body { background: white !important; }
            .card { box-shadow: none !important; border: 1px solid #ddd !important; }
            .header { background: white !important; color: black !important; }
        }
        
        @media (max-width: 768px) {
            .header h1 { font-size: 1.8em; }
            .stats-grid { grid-template-columns: 1fr; }
            table { display: block; overflow-x: auto; }
        }
    </style>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1><i class="fas fa-server"></i> Informe Tecnico del Sistema</h1>
            <p>Analisis completo del equipo generado automaticamente</p>
            
            <div class="header-info">
                <div class="info-item">
                    <i class="fas fa-desktop"></i>
                    <div><strong>Equipo:</strong> $global:ComputerName</div>
                </div>
                <div class="info-item">
                    <i class="fas fa-user"></i>
                    <div><strong>Usuario:</strong> $global:UserName</div>
                </div>
                <div class="info-item">
                    <i class="fas fa-calendar-alt"></i>
                    <div><strong>Fecha:</strong> $(Get-Date -Format "dd/MM/yyyy HH:mm")</div>
                </div>
                <div class="info-item">
                    <i class="fas fa-cogs"></i>
                    <div><strong>Herramienta:</strong> Multi Herramienta Tecnica v1.0</div>
                </div>
            </div>
        </div>
"@
 
    Write-Host "Generando resumen del sistema..." -ForegroundColor Gray
    $os = Get-WmiObject Win32_OperatingSystem
    $cpu = Get-WmiObject Win32_Processor
    $ram = Get-WmiObject Win32_ComputerSystem
    $totalRAM = [math]::Round($ram.TotalPhysicalMemory/1GB, 2)
    $freeRAM = [math]::Round($os.FreePhysicalMemory/1MB, 2)
    $usedRAM = [math]::Round(($ram.TotalPhysicalMemory - $os.FreePhysicalMemory*1024)/1GB, 2)
    $ramPercent = [math]::Round(($usedRAM/$totalRAM)*100, 2)
    
    $htmlContent += @"
        <div class="card">
            <h2 class="card-title"><i class="fas fa-chart-line"></i> Resumen del Sistema</h2>
            <div class="stats-grid">
                <div class="stat-box">
                    <div class="stat-label">Sistema Operativo</div>
                    <div class="stat-value">$($os.Caption)</div>
                    <div class="stat-label">Version $($os.Version)</div>
                </div>
                <div class="stat-box">
                    <div class="stat-label">Procesador</div>
                    <div class="stat-value">$($cpu.Name.Split('@')[0])</div>
                    <div class="stat-label">$($cpu.NumberOfCores) nucleos</div>
                </div>
                <div class="stat-box">
                    <div class="stat-label">Memoria RAM</div>
                    <div class="stat-value">$totalRAM GB</div>
                    <div class="progress-bar">
                        <div class="progress" style="width: ${ramPercent}%"></div>
                    </div>
                    <div class="stat-label">$usedRAM GB en uso ($ramPercent%)</div>
                </div>
            </div>
        </div>
"@
 
    Write-Host "Recopilando informacion de discos..." -ForegroundColor Gray
    $discos = Get-WmiObject Win32_LogicalDisk | Where-Object {$_.DriveType -eq 3}
    
    $htmlContent += @"
        <div class="card">
            <h2 class="card-title"><i class="fas fa-hdd"></i> Almacenamiento</h2>
            <div class="alert alert-info">
                <i class="fas fa-info-circle"></i>
                <span>Total de discos encontrados: $($discos.Count)</span>
            </div>
            <table>
                <thead>
                    <tr>
                        <th>Unidad</th>
                        <th>Etiqueta</th>
                        <th>Tamano Total</th>
                        <th>Espacio Libre</th>
                        <th>Espacio Usado</th>
                        <th>% Libre</th>
                        <th>Estado</th>
                    </tr>
                </thead>
                <tbody>
"@
 
    foreach ($disco in $discos) {
        $sizeGB = [math]::Round($disco.Size/1GB, 2)
        $freeGB = [math]::Round($disco.FreeSpace/1GB, 2)
        $usedGB = [math]::Round(($disco.Size - $disco.FreeSpace)/1GB, 2)
        $freePercent = [math]::Round(($disco.FreeSpace/$disco.Size)*100, 2)
        
        if ($freePercent -gt 20) { $estado = "Optimo"; $badgeClass = "badge-success" }
        elseif ($freePercent -gt 10) { $estado = "Advertencia"; $badgeClass = "badge-warning" }
        else { $estado = "Critico"; $badgeClass = "badge-danger" }
        
        $htmlContent += @"
                    <tr>
                        <td><strong>$($disco.DeviceID)</strong></td>
                        <td>$($disco.VolumeName)</td>
                        <td>$sizeGB GB</td>
                        <td>$freeGB GB</td>
                        <td>$usedGB GB</td>
                        <td>
                            <div class="progress-bar">
                                <div class="progress" style="width: ${freePercent}%"></div>
                            </div>
                            $freePercent%
                        </td>
                        <td><span class="badge $badgeClass">$estado</span></td>
                    </tr>
"@
    }
    
    $htmlContent += @"
                </tbody>
            </table>
        </div>
"@
 
    Write-Host "Analizando configuracion de red..." -ForegroundColor Gray
    $adaptadores = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
    
    $htmlContent += @"
        <div class="card">
            <h2 class="card-title"><i class="fas fa-network-wired"></i> Red y Conectividad</h2>
            <div class="alert alert-success">
                <i class="fas fa-wifi"></i>
                <span>Adaptadores activos: $($adaptadores.Count)</span>
            </div>
            <div class="stats-grid">
"@
 
    foreach ($adap in $adaptadores) {
        $config = Get-NetIPConfiguration -InterfaceAlias $adap.Name -ErrorAction SilentlyContinue
        $ipAddress = if ($config) { $config.IPv4Address.IPAddress } else { "No disponible" }
        
        $htmlContent += @"
                <div class="stat-box">
                    <div class="stat-label">$($adap.Name)</div>
                    <div class="stat-value">$($adap.InterfaceDescription.Split(',')[0])</div>
                    <div class="stat-label"><strong>IP:</strong> $ipAddress</div>
                    <div class="stat-label"><strong>Velocidad:</strong> $($adap.LinkSpeed)</div>
                    <span class="badge badge-success">Conectado</span>
                </div>
"@
    }
    
    $htmlContent += @"
            </div>
        </div>
"@
 
    Write-Host "Listando programas instalados..." -ForegroundColor Gray
    $programas = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                                   "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                 Where-Object {$_.DisplayName} |
                 Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
                 Sort-Object DisplayName |
                 Select-Object -First 30
    
    $htmlContent += @"
        <div class="card">
            <h2 class="card-title"><i class="fas fa-box"></i> Programas Instalados</h2>
            <div class="alert alert-warning">
                <i class="fas fa-exclamation-triangle"></i>
                <span>Mostrando 30 de $($programas.Count) programas instalados</span>
            </div>
            <table>
                <thead>
                    <tr>
                        <th>Nombre</th>
                        <th>Version</th>
                        <th>Editor</th>
                        <th>Fecha Instalacion</th>
                    </tr>
                </thead>
                <tbody>
"@
 
    foreach ($prog in $programas) {
        $fecha = if ($prog.InstallDate) { 
            try { [DateTime]::ParseExact($prog.InstallDate, "yyyyMMdd", $null).ToString("dd/MM/yyyy") } catch { "Desconocida" }
        } else { "Desconocida" }
        
        $htmlContent += @"
                    <tr>
                        <td>$($prog.DisplayName)</td>
                        <td><span class="badge badge-info">$($prog.DisplayVersion)</span></td>
                        <td>$($prog.Publisher)</td>
                        <td>$fecha</td>
                    </tr>
"@
    }
    
    $htmlContent += @"
                </tbody>
            </table>
        </div>
"@
 
    Write-Host "Recopilando detalles de hardware..." -ForegroundColor Gray
    $gpu = Get-WmiObject Win32_VideoController
    $bios = Get-WmiObject Win32_BIOS
    $board = Get-WmiObject Win32_BaseBoard
    
    $htmlContent += @"
        <div class="card">
            <h2 class="card-title"><i class="fas fa-microchip"></i> Hardware Detallado</h2>
            <div class="stats-grid">
                <div class="stat-box">
                    <div class="stat-label">Placa Base</div>
                    <div class="stat-value">$($board.Manufacturer)</div>
                    <div class="stat-label">$($board.Product)</div>
                    <div class="stat-label">Serie: $($board.SerialNumber)</div>
                </div>
                <div class="stat-box">
                    <div class="stat-label">BIOS/UEFI</div>
                    <div class="stat-value">$($bios.Manufacturer)</div>
                    <div class="stat-label">Version $($bios.SMBIOSBIOSVersion)</div>
                </div>
                <div class="stat-box">
                    <div class="stat-label">Tarjeta Grafica</div>
                    <div class="stat-value">$($gpu.Name)</div>
                    <div class="stat-label">Driver: $($gpu.DriverVersion)</div>
                </div>
            </div>
        </div>
        
        <div class="footer">
            <p>Informe generado automaticamente por Multi Herramienta Tecnica v1.0</p>
            <p>Generado el $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</p>
        </div>
    </div>
    
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            const progressBars = document.querySelectorAll('.progress');
            progressBars.forEach(bar => {
                const width = bar.style.width;
                bar.style.width = '0';
                setTimeout(() => { bar.style.width = width; }, 300);
            });
        });
    </script>
</body>
</html>
"@
 
    try {
        $htmlContent | Out-File -FilePath $htmlFile -Encoding UTF8 -Force
        Write-Host "`nInforme HTML generado exitosamente!" -ForegroundColor Green
        Write-Host "Ubicacion: $htmlFile" -ForegroundColor Cyan
        
        $fileSize = (Get-Item $htmlFile).Length / 1KB
        Write-Host "Tamano del archivo: $([math]::Round($fileSize, 2)) KB" -ForegroundColor Gray
        
        $abrir = Read-Host "`nDesea abrir el informe en el navegador? (S/N)"
        if ($abrir -eq "S" -or $abrir -eq "s") {
            Start-Process $htmlFile
            Write-Host "Abriendo informe..." -ForegroundColor Green
        }
        
        $abrirCarpeta = Read-Host "`nDesea abrir la carpeta del escritorio? (S/N)"
        if ($abrirCarpeta -eq "S" -or $abrirCarpeta -eq "s") {
            Start-Process "explorer.exe" -ArgumentList "/select,`"$htmlFile`""
        }
        
    } catch {
        Write-Host "Error al guardar el archivo: $_" -ForegroundColor Red
    }
    
    Write-Host "`nPresione cualquier tecla para continuar..." -ForegroundColor Gray
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
 
# Funcion principal
function Main {
    do {
        Show-Menu
        $opcion = Read-Host "`nSeleccione una opcion"
        
        switch ($opcion) {
            "01" { Get-FullDiagnostic }
            "02" { Get-SystemInfo }
            "03" { Get-NetworkInfo }
            "04" { Get-DiskInfo }
            "05" { Get-RAMInfo }
            "06" { Get-InstalledPrograms }
            "07" { Get-HardwareInfo }
            "08" { Get-BiosInfo }
            "09" { Get-RunningProcesses }
            "10" { Get-ServicesInfo }
            "11" { Get-WifiInfo }
            "12" { Clear-Network }
            "13" { Repair-System }
            "14" { Get-SystemEvents }
            "15" { Get-GPUInfo }
            "16" { Get-Temperatures }
            "17" { Get-BatteryReport }
            "18" { Invoke-MSGrave }
            "19" { Export-ToHTML }
            "20" { 
                Write-Host "`nSaliendo..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
                exit 
            }
            default { 
                Write-Host "Opcion no valida. Presione cualquier tecla para continuar..." -ForegroundColor Red
                $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
        }
    } while ($true)
}
 
# Iniciar programa
Main