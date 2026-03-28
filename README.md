# Linux Server Auto-Provisioning & Deployment Tool (IaC)

Este proyecto es una **adaptación y evolución profesional** de un trabajo grupal realizado originalmente para la asignatura *Introducción a los Sistemas Operativos*. La versión presente en este repositorio ha sido refactorizada íntegramente para transformar un script académico en una herramienta de infraestructura agnóstica, segura y alineada con estándares modernos de despliegue.

## 🚀 Descripción
Herramienta de automatización basada en Bash (Infraestructura como Código) diseñada para el aprovisionamiento de servidores Linux (Ubuntu/Debian) y el despliegue de aplicaciones web Python (Flask/WSGI) bajo un stack **LEMP/LNMP**.

A diferencia de un script de configuración rígida, esta herramienta permite desplegar dinámicamente cualquier repositorio de aplicaciones web, gestionando todo el ciclo de vida del servidor desde una interfaz CLI interactiva.

## 🛠️ Capacidades Técnicas (Refactorizadas)

* **Despliegue Dinámico (Git-Driven):** Integración con Git para clonar repositorios en tiempo de ejecución directamente en el directorio de producción (`/var/www/`), permitiendo un flujo de despliegue versátil y profesional.
* **Aprovisionamiento de Red:** Instalación y configuración automática de **NGINX** como proxy inverso, gestionando archivos de configuración dinámicos basados en el nombre del proyecto definido por el usuario.
* **Gestión de Procesos y Alta Disponibilidad:** Configuración de **Gunicorn** y generación automática de unidades de servicio **systemd**, asegurando que la aplicación se inicie con el sistema y se recupere ante fallos de forma autónoma.
* **Seguridad y Aislamiento:**
    * Creación de entornos virtuales Python (`venv`) independientes por proyecto.
    * Gestión de permisos granulares mediante el usuario de sistema `www-data`.
    * **Eliminación de Hardcoded Credentials:** Todas las contraseñas de BD y nombres de usuario se solicitan de forma segura durante la ejecución.
* **Manejo de Bases de Datos:** Automatización de la instalación de **MySQL Server**, creación de usuarios con privilegios específicos y volcado dinámico de esquemas SQL.

## 🏗️ Stack Gestionado
* **OS:** Linux (Debian/Ubuntu)
* **Web Server:** NGINX
* **App Server:** Gunicorn (WSGI)
* **Backend:** Python 3 (venv)
* **Database:** MySQL Server
* **VCS:** Git

## ⚙️ Instalación y Uso

1. **Clonar la herramienta:**
    ```bash
    git clone [https://github.com/enekorodriguezg/linux-server-automation.git](https://github.com/enekorodriguezg/linux-server-automation.git)
    cd linux-server-automation
    chmod +x deploy.sh
    ```

2. **Ejecutar con privilegios de root:**
    El script requiere permisos de superusuario para gestionar paquetes, servicios de sistema (systemd) y directorios protegidos.

    ```bash
    sudo ./deploy.sh
    ```

3. **Inicialización e Input de Variables:**
    Al arrancar, el sistema solicitará de forma interactiva los datos necesarios para parametrizar el entorno:
    * **Nombre del proyecto:** Definirá las rutas en `/var/www/` y los nombres de los servicios de sistema.
    * **Nombre de usuario de BD:** Para la creación del esquema y asignación de privilegios.
    * **Entry point de Flask:** Nombre del archivo principal (ej: `app` o `run`) para configurar correctamente el servidor WSGI.
    * **URL del Repositorio:** Dirección HTTPS para el clonado dinámico del código fuente de la aplicación.

---

**Nota Final:** Este software se ha desarrollado con fines de automatización de entornos de staging y producción inicial. Tras su ejecución, se recomienda encarecidamente revisar las políticas de firewall (UFW/Iptables) y asegurar que solo los puertos necesarios (80/443/SSH) permanezcan expuestos al tráfico externo.

## ⚖️ Licencia
Este proyecto está bajo la Licencia MIT. Consulta el archivo [LICENSE](LICENSE) para más detalles.