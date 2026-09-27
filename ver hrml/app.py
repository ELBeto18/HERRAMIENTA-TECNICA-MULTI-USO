#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Aplicación Web Python para Multi Herramienta Técnica
Interfaz HTML + PowerShell como backend
"""

import os
import sys
import json
import subprocess
import threading
import time
from datetime import datetime
from flask import Flask, render_template, request, jsonify, send_from_directory
from flask_socketio import SocketIO
import psutil

app = Flask(__name__, static_folder='static', template_folder='templates')
app.config['SECRET_KEY'] = 'herramienta-tecnica-secret-key-2024'
socketio = SocketIO(app, cors_allowed_origins="*")

# Variables globales
SYSTEM_INFO = {
    'computer_name': os.environ.get('COMPUTERNAME', 'Desconocido'),
    'user_name': os.environ.get('USERNAME', 'Desconocido'),
    'os': sys.platform,
    'python_version': sys.version
}

class PowerShellRunner:
    """Clase para ejecutar comandos PowerShell de manera segura"""
    
    @staticmethod
    def run_command(command, timeout=30):
        """
        Ejecuta un comando PowerShell y retorna el resultado
        
        Args:
            command (str): Comando PowerShell a ejecutar
            timeout (int): Tiempo máximo en segundos
            
        Returns:
            dict: Resultado con éxito, salida y errores
        """
        try:
            # Preparar el comando PowerShell
            ps_command = f'powershell -Command "{command}"'
            
            # Ejecutar el comando
            result = subprocess.run(
                ps_command,
                capture_output=True,
                text=True,
                shell=True,
                timeout=timeout,
                encoding='utf-8',
                errors='ignore'
            )
            
            return {
                'success': result.returncode == 0,
                'output': result.stdout,
                'error': result.stderr,
                'returncode': result.returncode
            }
            
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'output': '',
                'error': f'El comando excedió el tiempo límite de {timeout} segundos',
                'returncode': -1
            }
        except Exception as e:
            return {
                'success': False,
                'output': '',
                'error': str(e),
                'returncode': -1
            }
    
    @staticmethod
    def run_script(script_path, args=None, timeout=60):
        """
        Ejecuta un script PowerShell completo
        
        Args:
            script_path (str): Ruta al script .ps1
            args (list): Argumentos para el script
            timeout (int): Tiempo máximo en segundos
            
        Returns:
            dict: Resultado de la ejecución
        """
        try:
            if not os.path.exists(script_path):
                return {
                    'success': False,
                    'output': '',
                    'error': f'Script no encontrado: {script_path}',
                    'returncode': -1
                }
            
            # Construir comando
            cmd = ['powershell', '-ExecutionPolicy', 'Bypass', '-File', script_path]
            if args:
                cmd.extend(args)
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                encoding='utf-8',
                errors='ignore',
                timeout=timeout
            )
            
            return {
                'success': result.returncode == 0,
                'output': result.stdout,
                'error': result.stderr,
                'returncode': result.returncode
            }
            
        except Exception as e:
            return {
                'success': False,
                'output': '',
                'error': str(e),
                'returncode': -1
            }

class SystemMonitor:
    """Clase para monitoreo del sistema usando Python"""
    
    @staticmethod
    def get_system_info():
        """Obtiene información básica del sistema usando Python"""
        try:
            info = {
                'cpu': {
                    'percent': psutil.cpu_percent(interval=1),
                    'cores': psutil.cpu_count(logical=False),
                    'logical_cores': psutil.cpu_count(logical=True),
                    'frequency': psutil.cpu_freq().current if psutil.cpu_freq() else None
                },
                'memory': {
                    'total': round(psutil.virtual_memory().total / (1024**3), 2),
                    'available': round(psutil.virtual_memory().available / (1024**3), 2),
                    'percent': psutil.virtual_memory().percent,
                    'used': round(psutil.virtual_memory().used / (1024**3), 2)
                },
                'disk': [],
                'network': [],
                'boot_time': datetime.fromtimestamp(psutil.boot_time()).strftime('%Y-%m-%d %H:%M:%S')
            }
            
            # Información de discos
            for partition in psutil.disk_partitions():
                try:
                    usage = psutil.disk_usage(partition.mountpoint)
                    info['disk'].append({
                        'device': partition.device,
                        'mountpoint': partition.mountpoint,
                        'fstype': partition.fstype,
                        'total': round(usage.total / (1024**3), 2),
                        'used': round(usage.used / (1024**3), 2),
                        'free': round(usage.free / (1024**3), 2),
                        'percent': usage.percent
                    })
                except:
                    continue
            
            # Información de red
            for interface, addrs in psutil.net_if_addrs().items():
                for addr in addrs:
                    if addr.family == 2:  # AF_INET
                        info['network'].append({
                            'interface': interface,
                            'ip': addr.address,
                            'netmask': addr.netmask
                        })
            
            return info
            
        except Exception as e:
            return {'error': str(e)}

# ============================================
# RUTAS DE LA APLICACIÓN WEB
# ============================================

@app.route('/')
def index():
    """Página principal"""
    return render_template('index.html', system_info=SYSTEM_INFO)

@app.route('/api/system/info', methods=['GET'])
def api_system_info():
    """API para obtener información del sistema"""
    monitor = SystemMonitor()
    info = monitor.get_system_info()
    return jsonify(info)

@app.route('/api/powershell/run', methods=['POST'])
def api_powershell_run():
    """API para ejecutar comandos PowerShell"""
    data = request.json
    command = data.get('command', '')
    
    if not command:
        return jsonify({'error': 'No se proporcionó comando'}), 400
    
    runner = PowerShellRunner()
    result = runner.run_command(command)
    
    return jsonify(result)

@app.route('/api/diagnostic/full', methods=['GET'])
def api_diagnostic_full():
    """API para diagnóstico completo del sistema"""
    
    diagnostic_data = {
        'timestamp': datetime.now().isoformat(),
        'system': {},
        'hardware': {},
        'network': {},
        'storage': {},
        'processes': []
    }
    
    # Usar Python para información básica
    monitor = SystemMonitor()
    py_info = monitor.get_system_info()
    
    diagnostic_data['system'] = {
        'computer_name': SYSTEM_INFO['computer_name'],
        'user_name': SYSTEM_INFO['user_name'],
        'os': SYSTEM_INFO['os'],
        'boot_time': py_info.get('boot_time', 'Desconocido'),
        'python_version': SYSTEM_INFO['python_version']
    }
    
    diagnostic_data['hardware'] = {
        'cpu': py_info.get('cpu', {}),
        'memory': py_info.get('memory', {}),
        'disk': py_info.get('disk', [])
    }
    
    # Comandos PowerShell para información específica
    ps_runner = PowerShellRunner()
    
    # Obtener información del sistema via PowerShell
    system_info_cmd = "systeminfo | Select-Object -First 50"
    result = ps_runner.run_command(system_info_cmd)
    if result['success']:
        diagnostic_data['system']['details'] = result['output']
    
    # Obtener programas instalados
    programs_cmd = """
    Get-ItemProperty "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*",
                    "HKLM:\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*" |
    Where-Object { $_.DisplayName } |
    Select-Object DisplayName, DisplayVersion, Publisher |
    ConvertTo-Json
    """
    
    result = ps_runner.run_command(programs_cmd)
    if result['success'] and result['output']:
        try:
            diagnostic_data['software'] = json.loads(result['output'])
        except:
            diagnostic_data['software'] = result['output']
    
    # Obtener servicios
    services_cmd = """
    Get-Service | 
    Select-Object DisplayName, Status, StartType, ServiceName |
    ConvertTo-Json
    """
    
    result = ps_runner.run_command(services_cmd)
    if result['success'] and result['output']:
        try:
            diagnostic_data['services'] = json.loads(result['output'])
        except:
            diagnostic_data['services'] = result['output']
    
    return jsonify(diagnostic_data)

@app.route('/api/export/html', methods=['GET'])
def api_export_html():
    """API para exportar información a HTML"""
    try:
        # Obtener datos del sistema
        monitor = SystemMonitor()
        system_info = monitor.get_system_info()
        
        # Generar HTML simple
        html_content = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Informe del Sistema - {SYSTEM_INFO['computer_name']}</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; }}
                h1 {{ color: #333; }}
                .section {{ margin-bottom: 30px; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }}
                .stat {{ display: inline-block; margin: 10px; padding: 15px; background: #f5f5f5; border-radius: 5px; }}
                .stat-value {{ font-size: 24px; font-weight: bold; color: #007bff; }}
            </style>
        </head>
        <body>
            <h1>Informe del Sistema</h1>
            <p><strong>Generado:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            
            <div class="section">
                <h2>Información General</h2>
                <p><strong>Equipo:</strong> {SYSTEM_INFO['computer_name']}</p>
                <p><strong>Usuario:</strong> {SYSTEM_INFO['user_name']}</p>
                <p><strong>Sistema Operativo:</strong> {SYSTEM_INFO['os']}</p>
            </div>
            
            <div class="section">
                <h2>CPU</h2>
                <div class="stat">
                    <div class="stat-value">{system_info.get('cpu', {}).get('percent', 0)}%</div>
                    <div>Uso de CPU</div>
                </div>
                <div class="stat">
                    <div class="stat-value">{system_info.get('cpu', {}).get('cores', 0)}</div>
                    <div>Núcleos Físicos</div>
                </div>
            </div>
            
            <div class="section">
                <h2>Memoria RAM</h2>
                <div class="stat">
                    <div class="stat-value">{system_info.get('memory', {}).get('used', 0)} GB</div>
                    <div>En uso</div>
                </div>
                <div class="stat">
                    <div class="stat-value">{system_info.get('memory', {}).get('total', 0)} GB</div>
                    <div>Total</div>
                </div>
                <div class="stat">
                    <div class="stat-value">{system_info.get('memory', {}).get('percent', 0)}%</div>
                    <div>Porcentaje usado</div>
                </div>
            </div>
            
            <div class="section">
                <h2>Almacenamiento</h2>
        """
        
        for disk in system_info.get('disk', []):
            html_content += f"""
                <div style="margin: 10px 0;">
                    <strong>{disk.get('mountpoint', '')}</strong><br>
                    Usado: {disk.get('used', 0)} GB de {disk.get('total', 0)} GB ({disk.get('percent', 0)}%)
                </div>
            """
        
        html_content += """
            </div>
        </body>
        </html>
        """
        
        # Guardar archivo
        filename = f"informe_sistema_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
        filepath = os.path.join('static', 'exports', filename)
        
        # Asegurar que existe el directorio
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(html_content)
        
        return jsonify({
            'success': True,
            'filename': filename,
            'filepath': filepath,
            'url': f'/static/exports/{filename}'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/network/info', methods=['GET'])
def api_network_info():
    """API para información de red"""
    ps_runner = PowerShellRunner()
    
    network_cmd = """
    $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
    $result = @()
    
    foreach ($adap in $adapters) {
        $config = Get-NetIPConfiguration -InterfaceAlias $adap.Name -ErrorAction SilentlyContinue
        $obj = [PSCustomObject]@{
            Name = $adap.Name
            Status = $adap.Status
            LinkSpeed = $adap.LinkSpeed
            MacAddress = $adap.MacAddress
            IP = if ($config) { $config.IPv4Address.IPAddress } else { "N/A" }
            Gateway = if ($config) { $config.IPv4DefaultGateway.NextHop } else { "N/A" }
            DNS = if ($config) { ($config.DNSServer.ServerAddresses -join ', ') } else { "N/A" }
        }
        $result += $obj
    }
    
    $result | ConvertTo-Json
    """
    
    result = ps_runner.run_command(network_cmd)
    
    if result['success'] and result['output']:
        try:
            network_info = json.loads(result['output'])
            return jsonify({
                'success': True,
                'data': network_info
            })
        except:
            return jsonify({
                'success': True,
                'data': result['output']
            })
    else:
        return jsonify({
            'success': False,
            'error': result['error']
        })

# ============================================
# WEBSOCKETS PARA TIEMPO REAL
# ============================================

@socketio.on('connect')
def handle_connect():
    """Manejar conexión de cliente"""
    print('Cliente conectado')
    socketio.emit('system_status', {'status': 'connected', 'system': SYSTEM_INFO})

@socketio.on('request_system_monitor')
def handle_system_monitor():
    """Enviar monitoreo del sistema en tiempo real"""
    def send_monitor_data():
        while True:
            try:
                monitor = SystemMonitor()
                data = monitor.get_system_info()
                socketio.emit('system_monitor', data)
                time.sleep(2)  # Actualizar cada 2 segundos
            except:
                break
    
    # Iniciar thread para monitoreo continuo
    thread = threading.Thread(target=send_monitor_data)
    thread.daemon = True
    thread.start()

# ============================================
# ARCHIVOS ESTÁTICOS
# ============================================

@app.route('/static/<path:path>')
def send_static(path):
    """Servir archivos estáticos"""
    return send_from_directory('static', path)

# ============================================
# INICIALIZACIÓN
# ============================================

def create_directories():
    """Crear directorios necesarios"""
    directories = [
        'static/css',
        'static/js',
        'static/img',
        'static/exports',
        'templates',
        'modules'
    ]
    
    for directory in directories:
        os.makedirs(directory, exist_ok=True)

def check_dependencies():
    """Verificar dependencias necesarias"""
    try:
        import flask
        import flask_socketio
        import psutil
        return True
    except ImportError as e:
        print(f"Error: {e}")
        print("Instale las dependencias con: pip install -r requirements.txt")
        return False

if __name__ == '__main__':
    print("=" * 60)
    print("Multi Herramienta Técnica - Versión Web")
    print("=" * 60)
    
    # Verificar dependencias
    if not check_dependencies():
        sys.exit(1)
    
    # Crear directorios
    create_directories()
    
    # Información del sistema
    print(f"Equipo: {SYSTEM_INFO['computer_name']}")
    print(f"Usuario: {SYSTEM_INFO['user_name']}")
    print(f"Sistema: {SYSTEM_INFO['os']}")
    print(f"Python: {SYSTEM_INFO['python_version']}")
    print("\nIniciando servidor web...")
    print("URL: http://localhost:5000")
    print("=" * 60)
    
    # Iniciar servidor
    socketio.run(app, debug=True, host='0.0.0.0', port=5000)