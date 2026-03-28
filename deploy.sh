#!/usr/bin/bash


# --- CONFIGURACIÓN DEL ENTORNO --- 
clear
echo "=============================="
echo "AUTO-PROVISIONING SERVER SCRIPT"
echo "=============================="
echo ""

read -p "Introduce el nombre del proyecto (sin espacios, ej: mi_proyecto): " PROJECT_NAME
read -p "Introduce el nombre de usuario de la Base de Datos: " DB_USER
read -p "Introduce el nombre de la instancia Flask (ej: app, main, run): " FLASK_APP_NAME
read -p "Introduce el nombre del archivo SQL de volcado (ej: script.sql) [Deja en blanco si no se usa]: " SQL_FILE

readonly PROJECT_DIR="/var/www/$PROJECT_NAME"

function desplegarCodigoFuente()
{
	echo "🔄 Descargando código de la aplicación..."
	read -p "Introduce la URL de clonado del repositorio (HTTPS): " repo_url
	cd $PROJECT_DIR > /dev/null 2>&1

	if git clone "$repo_url" . ; then
		echo "✅ Código desplegado correctamente en el servidor."
	else
		echo "❌ Error al descargar el repositorio. Verifica la URL."
	fi

	read -p "Pulsa ENTER para continuar..."
}

function eliminarMySQL()
{
	# Detiene el servicio MySQL
	echo "🔄 Deteniendo servicio MySQL..."
	sudo systemctl stop mysql.service > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ MySQL detenido."
	else
		echo "❌ No se pudo detener MySQL."
	fi
	# Elimina completamente MySQL y sus configuraciones
	echo "🗑️  Purge de paquetes MySQL..."
	sudo apt purge -y mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-* > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Paquetes MySQL purgados."
	else
		echo "❌ Error al purgar paquetes MySQL."
	fi

	# Elimina dependencias no necesarias
	echo "🧹 Eliminando dependencias y caché..."
	sudo apt autoremove -y > /dev/null 2>&1
	sudo apt autoclean -y > /dev/null 2>&1
	echo "✅ Dependencias innecesarias y caché eliminadas."
	# Elimina los datos, configuraciones y logs de MySQL para una limpieza completa
	echo "🚮 Eliminando datos y configuraciones..."
	sudo rm -rf /var/lib/mysql /etc/mysql /var/log/mysql > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Datos de MySQL eliminados."
	else
		echo "❌ Error al eliminar datos de MySQL."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function crearNuevaUbicacion()
{
	# Crea una nueva ubicación para el proyecto, borrando la existente si ya está
	echo "🔄 Reconfigurando $PROJECT_DIR..."
	if [ -d $PROJECT_DIR ]; then
		echo "🗑️  Borrando directorio existente..."
		sudo rm -rf $PROJECT_DIR > /dev/null 2>&1
		echo "✅ Directorio anterior eliminado."
	fi
	echo "📁 Creando directorio..."
	sudo mkdir -p $PROJECT_DIR > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Directorio creado."
	else
		echo "❌ Error al crear directorio."
	fi

	echo "🔧 Ajustando permisos..."
	sudo chown -R $USER:$USER $PROJECT_DIR > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Permisos asignados a $USER."
	else
		echo "❌ No se pudieron cambiar permisos."
	fi

	read -p "Pulsa ENTER para continuar..."
}


function instalarMySQL()
{
	# Verifica si MySQL está instalado y lo inicia si no está corriendo; si no está instalado, lo instala
	echo "🔄 Comprobando instalación de MySQL..."
	if dpkg -l | grep -q mysql-server; then
		echo "ℹ️  MySQL ya está instalado."
	else
		echo "⬇️  Instalando MySQL..."
		sudo apt update
		sudo apt install -y mysql-server
		if [ $? -eq 0 ]; then
			echo "✅ MySQL instalado."
			echo "▶️  Iniciando MySQL si no está activo..."
			sudo systemctl start mysql.service > /dev/null 2>&1
			if systemctl is-active --quiet mysql.service; then
				echo "✅ Servicio MySQL en marcha."
			else
				echo "❌ No se pudo iniciar MySQL."
			fi
		else
			echo "❌ Fallo al instalar MySQL."
		fi
	fi

	
	read -p "Pulsa ENTER para continuar..."
}

function crearusuariobasesdedatos()
{
	# Crea un script SQL para crear el usuario 'lsi' con permisos amplios y lo ejecuta en MySQL
	local sqlScript="$PROJECT_DIR/crear_usuario.sql"

	echo "🔄 Generando script SQL de usuario..."
	touch "$sqlScript" > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Archivo $sqlScript creado."
	else
		echo "❌ No se pudo crear $sqlScript."
		return
	fi

	echo "🔄 Escribiendo comandos en el script..."
	read -s -p "Introduce una contraseña para el usuario $DB_USER: " DB_PASS
	echo ""
	cat <<EOF > "$sqlScript"
		CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
		GRANT CREATE, ALTER, DROP, INSERT, UPDATE, INDEX, DELETE, SELECT,
		    REFERENCES, RELOAD ON *.* TO '$DB_USER'@'localhost' WITH GRANT OPTION;
		FLUSH PRIVILEGES;
EOF
	if [ $? -eq 0 ]; then
		echo "✅ Script SQL rellenado."
	else
		echo "❌ Error al escribir en $sqlScript."
		return
	fi

	echo "▶️  Ejecutando script en MySQL..."
	sudo mysql < "$sqlScript" > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Usuario 'lsi' creado y permisos asignados."
	else
		echo "❌ Fallo al ejecutar el script SQL."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function crearbasededatos()
{
	# Ejecuta un script SQL con la cuenta del usuario que se indique para crear y configurar la base de datos
	if [ -z "$SQL_FILE" ]; then
		echo "ℹ️ No se especificó archivo SQL. Saltando configuración de tablas..."
		return 0
	fi

	local script="$PROJECT_DIR/$SQL_FILE"
	
	echo "🔄 Ejecutando script de creación de base de datos..."
	mysql -u "$DB_USER" -p < "$script" > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Base de datos configurada correctamente."
	else
		echo "❌ Error al ejecutar $script."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function ejecutarEntornoVirtual()
{
	# Instala dependencias necesarias y crea un entorno virtual Python en el proyecto
	echo "🔄 Preparando entorno virtual..."
	sudo apt update > /dev/null 2>&1
	sudo apt -y upgrade > /dev/null 2>&1
	sudo apt install -y python3-venv python3-dev build-essential libssl-dev libffi-dev python3-setuptools python3-pip > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Dependencias instaladas."
	else
		echo "❌ Error al instalar dependencias."
		return
	fi

	cd $PROJECT_DIR > /dev/null 2>&1
	echo "🔄 Creando entorno virtual venv..."
	python3 -m venv venv > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Entorno virtual creado."
	else
		echo "❌ Error al crear entorno virtual."
		return
	fi

	echo "▶️  Activando entorno virtual..."
	source venv/bin/activate
	if [ $? -eq 0 ]; then
		echo "✅ Entorno virtual activado."
	else
		echo "❌ Error al activar entorno virtual."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function instalarLibreriasEntornoVirtual()
{
	# Activa el entorno virtual e instala las librerías requeridas del proyecto
	echo "🔄 Instalando librerías en el entorno virtual..."
	cd $PROJECT_DIR > /dev/null 2>&1
	source venv/bin/activate > /dev/null 2>&1
	python -m pip install --upgrade pip > /dev/null 2>&1
	pip install -r requirements.txt > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Librerías instaladas correctamente."
	else
		echo "❌ Error al instalar librerías."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function probandotodoconservidordedesarrollodeflask()
{
	# Función de depuración. No recomendada para entornos de producción.
    echo "⚠️ MODO DEBUG: Iniciando servidor de desarrollo integrado de Flask..."
    echo "❌ Advertencia: No usar como servicio final."
    

    python3 "$PROJECT_DIR/${FLASK_APP_NAME}.py" > /dev/null 2>&1 &
    PID=$!
    sleep 2
    
    if ps -p $PID > /dev/null 2>&1; then
        echo "✅ Servidor Flask de prueba corriendo (PID $PID) en el puerto 5000."
        echo "   Para comprobarlo desde otra terminal, ejecuta: curl http://127.0.0.1:5000"
        echo "   Pulsa CTRL+C para detener el servidor de prueba."
        
        wait $PID
    else
        echo "❌ No se pudo iniciar el servidor Flask de prueba."
        echo "   Comprueba que $FLASK_APP_NAME.py existe en $PROJECT_DIR."
    fi
    read -p "Pulsa ENTER para continuar..."
}

function instalarNGINX()
{
	# Verifica si NGINX está instalado, y si no lo está, lo instala
	echo "🔄 Instalando NGINX..."
	if dpkg -s nginx > /dev/null 2>&1; then
		echo "ℹ️  NGINX ya estaba instalado."
	else
		sudo apt update > /dev/null 2>&1
		sudo apt install -y nginx > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo "✅ NGINX instalado correctamente."
		else
			echo "❌ Error al instalar NGINX."
			return
		fi
	fi
	read -p "Pulsa ENTER para continuar..."
}

function arrancarNGINX()
{
	# Verifica si el servicio NGINX está en ejecución, y si no, lo inicia
	echo "🔄 Arrancando NGINX..."
	if sudo lsof -i :80 -t > /dev/null; then
		echo "⚠️  Puerto 80 ocupado, liberando..."
		sudo kill -9 $(sudo lsof -i :80 -t) > /dev/null 2>&1
		echo "✅ Puerto 80 liberado."
	fi
	sudo systemctl start nginx.service
	if systemctl is-active --quiet nginx.service; then
		echo "✅ Servicio NGINX en marcha."
	else
		echo "❌ No se pudo iniciar NGINX."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function testearPuertosNGINX()
{ 
	# Verifica si 'net-tools' está instalado y lo instala si no está presente
	# Luego, muestra el estado de los puertos abiertos por NGINX
	echo "🔄 Comprobando net-tools..."
	if ! dpkg -s net-tools > /dev/null 2>&1; then
		sudo apt install -y net-tools > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo "✅ net-tools instalado."
		else
			echo "❌ Error al instalar net-tools."
			return
		fi
	else
		echo "ℹ️  net-tools ya instalado."
	fi

	echo "🔄 Listando puertos abiertos por NGINX..."
	sudo netstat -anp 2>/dev/null | grep nginx && echo "✅ Puertos mostrados." || echo "❌ No se encontraron puertos nginx."
	read -p "Pulsa ENTER para continuar..."
}

function visualizarIndex()
{ 
	# Abre el navegador Firefox en la URL local del servidor NGINX (localhost)
	echo "🔄 Abriendo index en Firefox... (Se recomienda Chromium)"
	firefox http://127.0.0.1 > /dev/null 2>&1 &
	if [ $? -eq 0 ]; then
		echo "✅ Firefox abierto en http://localhost"
	else
		echo "❌ No se pudo abrir Firefox."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function personalizarIndex()
{ 
	# Personaliza el archivo index.html de NGINX con contenido HTML básico
	sudo rm /var/www/html/index.html
	local file="/var/www/html/index.html"
	echo "🔄 Personalizando index.html..."
	sudo tee "$file" > /dev/null << EOF
	<!DOCTYPE html>
	<html lang="en">
	<head>
		<meta charset="UTF-8" />
		<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
		<title>Grupo E.D.U. - Portfolio</title>
		<style>
			:root {
				--bg: #2c2c2c;
				--fg: #e0e0e0;
				--card-bg: #383838;
				--transition: 0.3s ease;
				--github-color: #181717;
				--github-hover: #333;
			}

			* {
				margin: 0;
				padding: 0;
				box-sizing: border-box;
			}

			html, body {
				height: 100%;
			}

			body {
				background: var(--bg);
				color: var(--fg);
				font-family: 'Segoe UI', sans-serif;
				overflow-x: hidden;
				display: flex;
				flex-direction: column;
			}

			header {
				text-align: center;
				padding: 2rem 1rem;
			}

			header h1 {
				font-size: 2.5rem;
				letter-spacing: 2px;
			}

			header p {
				margin-top: 0.5rem;
				color: #aaa;
			}

			.container {
				flex: 1;
				display: grid;
				grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
				gap: 2rem;
				padding: 2rem;
			}

			.card {
				background: var(--card-bg);
				border-radius: 8px;
				padding: 1.5rem;
				transition: transform var(--transition), box-shadow var(--transition);
				display: flex;
				flex-direction: column;
				align-items: center;
				justify-content: center;
				height: 220px;
			}

			.card:hover {
				transform: translateY(-8px);
				box-shadow: 0 8px 16px rgba(0, 0, 0, 0.5);
			}

			.card h3 {
				text-align: center;
				font-size: 1.5rem;
				margin-bottom: 0.5rem;
			}

			.card p {
				text-align: center;
				font-size: 0.9rem;
				color: #aaa;
			}

			footer {
				text-align: center;
				padding: 1rem;
				background-color: var(--bg);
			}

			.btn {
				display: inline-flex;
				align-items: center;
				justify-content: center;
				padding: 0.6rem;
				background: var(--github-color);
				color: #fff;
				border-radius: 50%;
				transition: background var(--transition), box-shadow var(--transition), transform var(--transition);
				box-shadow: 0 4px 10px rgba(0, 0, 0, 0.4);
				text-decoration: none;
			}

			.btn:hover {
				background: var(--github-hover);
				box-shadow: 0 6px 14px rgba(0, 0, 0, 0.6);
				transform: scale(1.05);
			}

			svg {
				fill: currentColor;
			}
		</style>
	</head>
	<body>
		<header>
			<h1>Grupo E.D.U.</h1>
			<p>Bash Project - Directed by Prof. KEPA XABIER BENGOETXEA KORTAZAR</p>
		</header>

		<section class="container">
			<div class="card">
				<h3>Eneko Rodriguez</h3>
				<p>Developer</p>
			</div>
			<div class="card">
				<h3>Urko Horas</h3>
				<p>Developer</p>
			</div>
			<div class="card">
				<h3>Diego Pomares</h3>
				<p>Developer</p>
			</div>
			<div class="card">
				<h3>Eder Torres</h3>
				<p>Developer</p>
			</div>
		</section>

		<footer>
			<a href="https://github.com/apolo176/BashProject" class="btn" target="_blank">
			  <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="currentColor" viewBox="0 0 24 24">
			    <path d="M12 .3a12 12 0 0 0-3.79 23.4c.6.11.82-.26.82-.58v-2.17c-3.34.73-4.04-1.61-4.04-1.61-.55-1.4-1.34-1.77-1.34-1.77-1.1-.76.08-.75.08-.75 1.22.09 1.86 1.25 1.86 1.25 1.08 1.85 2.83 1.31 3.52 1 .11-.78.42-1.31.76-1.61-2.67-.3-5.47-1.34-5.47-5.95 0-1.31.47-2.38 1.25-3.22-.13-.3-.54-1.52.12-3.17 0 0 1.01-.32 3.3 1.23a11.5 11.5 0 0 1 6 0c2.3-1.55 3.3-1.23 3.3-1.23.66 1.65.25 2.87.12 3.17.78.84 1.25 1.91 1.25 3.22 0 4.62-2.8 5.64-5.48 5.94.43.38.81 1.11.81 2.24v3.33c0 .32.21.7.82.58A12 12 0 0 0 12 .3"/>
			  </svg>
			</a>
		</footer>
	</body>
	</html>
EOF
	if [ $? -eq 0 ]; then
		echo "✅ index.html personalizado."
	else
		echo "❌ Error al personalizar index.html."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function instalarGunicorn()
{ 
	# Activa el entorno virtual y instala Gunicorn para servir la aplicación Flask
	echo "🔄 Instalando Gunicorn..."
	cd $PROJECT_DIR > /dev/null 2>&1
	source venv/bin/activate > /dev/null 2>&1
	pip install --upgrade pip gunicorn > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Gunicorn instalado en el entorno virtual."
	else
		echo "❌ Error al instalar Gunicorn."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function configurarGunicorn()
{ 
	# Configura Gunicorn creando el archivo wsgi.py para lanzar la aplicación Flask
	# Luego, ejecuta Gunicorn en el puerto 5000 y abre Firefox en localhost
	echo "🔄 Configurando Gunicorn service..."
	cd $PROJECT_DIR > /dev/null 2>&1
	source venv/bin/activate > /dev/null 2>&1

	local wsgi="wsgi.py"
	sudo tee "$wsgi" > /dev/null <<EOF
from $FLASK_APP_NAME import app
if __name__ == '__main__':
    app.run()
EOF
	if [ $? -eq 0 ]; then
		echo "✅ Archivo wsgi.py creado."
	else
		echo "❌ Error al crear wsgi.py."
		read -p "Pulsa ENTER para continuar..."
	fi
	echo "▶️  Iniciando Gunicorn..."
	echo "🔄 Comprobando puerto 5000..."
	if sudo lsof -i :5000 -t > /dev/null; then
		echo "⚠️  Puerto 5000 ocupado, liberando..."
		sudo kill -9 $(sudo lsof -i :5000 -t) > /dev/null 2>&1
		echo "✅ Puerto 5000 liberado."
	fi
	echo "Pulsa CTRL+C para terminar gunicorn"
	gunicorn --bind 127.0.0.1:5000 wsgi:app & > /dev/null 2>&1
	echo "Abriendo Firefox."
	firefox 127.0.0.1:5000 
	echo "💀 Gunicorn fue terminado"
	read -p "Pulsa ENTER para continuar..."
}

function pasarPropiedadyPermisos()
{ 
	# Cambia la propiedad y los permisos de los archivos del proyecto a 'www-data'
	# Esto es necesario para que el servidor web NGINX pueda acceder a los archivos
	echo "🔄 Ajustando propiedad y permisos a www-data..."
	sudo chown -R www-data:www-data $PROJECT_DIR > /dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo "✅ Propiedad transferida a www-data:www-data."
	else
		echo "❌ Error al cambiar propiedad/permiso."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function crearServicioSystemd()
{ 
	# Crea un servicio systemd para gestionar la aplicación Flask con Gunicorn
	# Configura el servicio para que se ejecute como 'www-data' y se reinicie automáticamente
	echo "Creando servicio systemd para formulario de citas..."
	cat <<EOF | sudo tee /etc/systemd/system/$PROJECT_NAME.service > /dev/null
	[Unit]
	Description=Gunicorn instance to serve Flask
	After=network.target

	[Service]
	User=www-data
	Group=www-data
	WorkingDirectory=$PROJECT_DIR
	Environment="PATH=$PROJECT_DIR/venv/bin"
	ExecStart=$PROJECT_DIR/venv/bin/gunicorn --bind 127.0.0.1:5000 wsgi:app
	Restart=always

	[Install]
	WantedBy=multi-user.target
EOF
	# Recarga el daemon de systemd, habilita el servicio para que se inicie automáticamente y lo arranca
	sudo systemctl daemon-reload
	echo "Servicio creado en /etc/systemd/system/$PROJECT_NAME.service "
	sudo systemctl enable $PROJECT_NAME
	sudo systemctl start $PROJECT_NAME
	echo "Verificando estado del servicio..."
	sleep 1  # Pequeña pausa para dar tiempo al servicio a arrancar

	# Verifica si el servicio está activo y muestra el resultado
	if systemctl is-active --quiet $PROJECT_NAME; then
        	echo "✅ El servicio '$PROJECT_NAME' se ha creado y está activo."
	else
		echo "❌ El servicio '$PROJECT_NAME' no está activo. Revisa los logs con:"
		echo "   sudo journalctl -u $PROJECT_NAME -e"
	fi
	read -p "Pulsa ENTER para continuar..."
}

function configurarNginxProxyInverso()
{ 
	# Configura NGINX como proxy inverso para redirigir tráfico desde el puerto 3128 hacia el puerto 5000 (donde Gunicorn sirve Flask)
	local conf_path="/etc/nginx/conf.d/$PROJECT_NAME.conf"
	if [ -f "$conf_path" ]; then
		echo "⚠️  El archivo $conf_path ya existe. No se ha hecho ninguna modificación."
	else
		# Si no existe el archivo de configuración, lo crea con los parámetros adecuados
		echo "Creando configuración de Nginx para formulario de citas..."
		sudo tee "$conf_path" > /dev/null <<EOF
		server {
		    listen 3128;
		    server_name localhost;
		    location / {
			include proxy_params;
			proxy_pass  http://127.0.0.1:5000;
		    }
		}
EOF
		echo "✅ Configuración creada en $conf_path"
		echo "Recargando Nginx..."
		sudo nginx -t && sudo systemctl reload nginx
	fi
	# Verifica si la configuración de NGINX es válida y recarga el servicio si es necesario
	echo "🔎 Comprobando sintaxis de la configuración de Nginx..."
	if sudo nginx -t; then
		echo "✅ Sintaxis válida. Puede recargar Nginx con la opción 20"
	else
		echo "❌ Error en la configuración de Nginx. No se ha recargado el servicio."
		echo "   Revisa los mensajes anteriores para más detalles."
	fi
	read -p "Pulsa ENTER para continuar..."
}

function cargarFicherosConfiguracionNginx()
{
	# Recarga la configuración de NGINX para aplicar los cambios realizados en los archivos de configuración
	sudo systemctl reload nginx
	echo "⚙️ Nginx recargado correctamente con la nueva configuración."
	read -p "Pulsa ENTER para continuar..."
}

function rearrancarNginx()
{ 
	# Reinicia el servicio de NGINX para aplicar cambios en la configuración
	sudo systemctl restart nginx
	echo "🚀 Nginx reiniciado correctamente."
	read -p "Pulsa ENTER para continuar..."
}

function testearVirtualHost()
{ 
	# Realiza una prueba para verificar que el servicio esté funcionando correctamente
	# Redirige al navegador para comprobar que se pueda acceder a la aplicación
	echo "🔄 Comprobando puerto 80..."
	if sudo lsof -i :80 -t > /dev/null; then
		echo "⚠️  Puerto 80 ocupado, liberando..."
		sudo kill -9 $(sudo lsof -i :80 -t) > /dev/null 2>&1
		echo "✅ Puerto 80 liberado."
	fi

	echo "🔄 Iniciando prueba en http://127.0.0.1:80..."
	firefox http://127.0.0.1:80 > /dev/null 2>&1 &
	if [ $? -eq 0 ]; then
		echo "✅ Firefox abierto en http://127.0.0.1:80"
	else
		echo "❌ No se pudo abrir Firefox."
	fi
	read -p "Pulsa ENTER para continuar..."
}
function verNginxLogs()
{ 
	# Muestra las últimas 10 líneas del archivo de errores de NGINX
		echo "🔄 Mostrando últimos errores de Nginx..."
	if tail -10 /var/log/nginx/error.log; then
		echo "✅ Logs mostrados."
	else
		echo "❌ No se pudieron mostrar los logs."
	fi
	read -p "Pulsa ENTER para continuar..."
}


function controlarIntentosConexionSSH()
{
	# Analiza los logs de autenticación para detectar intentos de conexión SSH exitosos o fallidos
	echo "🔄 Analizando intentos de conexión SSH..."
	# Lista los archivos auth.log, incluyendo comprimidos
	LOGS=$(ls /var/log/auth.log* 2>/dev/null)

	for LOG in $LOGS; do
		if [[ $LOG == *.gz ]]; then
			zcat "$LOG"
		else
			cat "$LOG"
		fi
	done | grep "sshd" | grep -E "Failed password|Accepted password" | while read -r LINE; do
		# Extrae fecha, estado (fail/accept) y nombre de usuario del intento de conexión
		DATE=$(echo "$LINE" | awk '{print $1, $2, $3}')
		STATUS=$(echo "$LINE" | grep -q "Failed password" && echo "fail" || echo "accept")
		USER=$(echo "$LINE" | awk '{for(i=1;i<=NF;i++) if($i=="for") print $(i+1)}')
		echo "🔔 Estado: [$STATUS] Nombre: $USER Fecha: $DATE\""
	done
	read -p "Pulsa ENTER para continuar..."
}


function salirMenu()
{
	echo "Fin del Programa"
}
### Main ###
opcionmenuppal=0
while test $opcionmenuppal -ne 24
do
    	#Muestra el menu
	echo -e "0 Clona el repositorio necesario\n"
	echo -e "1 Eliminar la instalación de mysql\n"
	echo -e "2 Crea la nueva ubicación \n"
	echo -e "3 Instalar MySQL\n"
	echo -e "4 Crear usuario en la base de datos\n"
	echo -e "5 Crear base de datos\n"
	echo -e "6 Ejecutar entorno virtual\n"
	echo -e "7 Instalar librerías entorno virtual\n"
	echo -e "8 Ejecutar el servicio\n"
	echo -e "9 Instalar NGINX\n"
	echo -e "10 Arrancar servicio web\n"
	echo -e "11 Testear puertos NGINX\n"
	echo -e "12 Abrir en navegador\n"
	echo -e "13 Personalizar index\n"
	echo -e "14 Instalar Gunicorn\n"
	echo -e "15 Configurar Gunicorn\n"
	echo -e "16 Establecer propiedad y permisos\n"
	echo -e "17 Crear servicio systemd para $PROJECT_NAME\n"
	echo -e "18 Configurar NGINX\n"
	echo -e "19 Cargar nuevos cambios de la configuración de NGINX\n"
	echo -e "20 Arrancar NGINX\n"
	echo -e "21 Testear virtual host\n"
	echo -e "22 Ver errores de NGINX\n"
	echo -e "23 Controlar intentos de conexión de SSH\n"
	echo -e "24 salir del Menu \n"
    	read -p "Elige una opcion:" opcionmenuppal
    	case $opcionmenuppal in
		0) desplegarCodigoFuente;;
		1) eliminarMySQL;;
		2) crearNuevaUbicacion;;
		3) instalarMySQL;;
		4) crearusuariobasesdedatos;;
		5) crearbasededatos;;
		6) ejecutarEntornoVirtual;;
		7) instalarLibreriasEntornoVirtual;;
		8) probandotodoconservidordedesarrollodeflask;;
		9) instalarNGINX;;
		10) arrancarNGINX;;
		11) testearPuertosNGINX;;
		12) visualizarIndex;;
		13) personalizarIndex;;
		14) instalarGunicorn;;
		15) configurarGunicorn;;
		16) pasarPropiedadyPermisos;;
		17) crearServicioSystemd;;
		18) configurarNginxProxyInverso;;
		19) cargarFicherosConfiguracionNginx;;
		20) rearrancarNginx;;
		21) testearVirtualHost;;
		22) verNginxLogs;;
		23) controlarIntentosConexionSSH;;
		24) salirMenu;;
		*) ;;
    	esac
done
exit 0
