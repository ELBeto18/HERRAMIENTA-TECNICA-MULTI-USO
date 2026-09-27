@echo off
title Configurar Herramienta Tecnica
echo Configurando permisos de PowerShell...
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"
echo.
echo Creando acceso directo...
powershell -Command "$WshShell = New-Object -comObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%USERPROFILE%\Desktop\Herramienta Tecnica.lnk'); $Shortcut.TargetPath = 'powershell.exe'; $Shortcut.Arguments = '-ExecutionPolicy Bypass -NoProfile -File \"%~dp0HERRAMIENTA TECNICA MULTI USO.ps1\"'; $Shortcut.Save()"
echo.
echo Configuracion completada!
echo Ahora puede usar el acceso directo en el escritorio.
pause