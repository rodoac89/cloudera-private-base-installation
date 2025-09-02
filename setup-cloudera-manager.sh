#!/bin/bash

# Autor: Rodolfo Aravena Collipal
# Version: 0.1.20250903

# Paso 0
## Verificar si el script se ejecuta en el SCM
echo "Configuración de Cloudera Manager en distribuciones RHEL."
read -p "¿Desea continuar? [Y/n]: " CONTINUE
PACKAGES=""
CONTINUE=${CONTINUE:-Y}
if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
  echo "Ejecución detenida."
  exit 1
fi
OPTION=0
echo "Seleccione las que desea configurar:"
echo "1. Cloudera Manager en nodo SCM"
echo "2. Cloudera Manager en los nodos agentes"
read -p "Ingrese su opción [1-2]: " OPTION
case $OPTION in
  1) PACKAGES+="cloudera-manager-daemons cloudera-manager-agent cloudera-manager-server";;
  2) PACKAGES+="cloudera-manager-daemons cloudera-manager-agent";;
  *) echo "Opción no válida."; exit 1;;
esac

read -p "Ahora copie y pegue el repositorio correspondiente con el nombre de usuario y contraseña correspondientes: " REPO_URL

## Actualizar el sistema e instalar paquetes
echo "Actualizando el sistema e instalando dependencias generales..."
#sudo dnf config-manager --set-enabled crb
sudo dnf update -y
sudo dnf -y install wget curl vim nano tar zip unzip nscd perl bind-utils rpcbind iproute #perl-IPC-Run
if [ $? -eq 0 ]; then
  echo "Paquetes instalados exitosamente."
else
  echo "Error: No se pudieron instalar algunos paquetes."
  exit 1
fi



## Instalar python 3.8
echo "Instalando Python 3.8..."
sudo dnf -y install python38 python38-devel platform-python
if [ $? -eq 0 ]; then
  echo "Python 3.8 instalado exitosamente."
  sudo python3.8 -m ensurepip
  sudo python3.8 -m pip install --upgrade pip
  sudo python3.8 -m pip install --upgrade pip
else
  echo "Error: No se pudieron instalar algunos paquetes."
  exit 1
fi


## Sincronización horaria con Chrony
echo "Configurando sincronización horaria con Chrony..."
sudo dnf -y install chrony

if [ $? -eq 0 ]; then
  sudo cp /etc/chrony.conf /etc/chrony.conf.bak
  sudo sed -i '/^server /s/^/#/' /etc/chrony.conf
  sudo bash -c 'echo "server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4" >> /etc/chrony.conf'

  echo "Iniciando y habilitando el servicio Chrony..."
  sudo systemctl enable --now chronyd
  echo "Verificando fuentes NTP:"
  sudo chronyc sources -v
  echo "Chrony instalado exitosamente."
  
else
  echo "Error: No se pudieron instalar algunos paquetes."
  exit 1
fi

#Configuración de red y AD
echo "Iniciando el proceso de configuración de red y Active Directory..."

## Hacer copia de seguridad de /etc/hosts
sudo cp /etc/hosts /etc/hosts.bak
echo "Copia de seguridad de /etc/hosts creada en /etc/hosts.bak"

DOMAIN="cdp.local"
## Verificar si existe el archivo host-dist en el directorio actual
if [ -f "./host-dist" ]; then
  echo "Se encontró el archivo host-dist en el directorio actual."
  echo "Se utilizará este archivo para la configuración de hosts."
  sudo cp ./host-dist /etc/hosts


else
  echo "No se encontró el archivo host-dist en el directorio actual."
  echo "Se procederá con la configuración manual de hosts."


  ## Solicitar el nombre del dominio con valor por defecto
  read -p "Nombre del dominio [$DOMAIN]: " INPUT_DOMAIN
  DOMAIN=${INPUT_DOMAIN:-$DOMAIN}
  ## Validar que el dominio no esté vacío
  if [ -z "$DOMAIN" ]; then
    echo "Error: El nombre del dominio no puede estar vacío."
    exit 1
  fi

  ## Solicitar la cantidad de nodos con valor por defecto
  NUM_NODES=1
  read -p "Cuántos nodos trabajará? [$NUM_NODES]: " INPUT_NODES
  NUM_NODES=${INPUT_NODES:-$NUM_NODES}

  ## Validar que sea un número entero positivo
  if ! [[ "$NUM_NODES" =~ ^[0-9]+$ ]] || [ "$NUM_NODES" -lt 1 ]; then
    echo "Error: Por favor, ingrese un número válido de nodos (entero positivo)."
    exit 1
  fi

  if [ $OPTION == 1 ]; then
    ## Configurar el hostname del nodo actual (nodo scm)
    sudo hostnamectl set-hostname cdp-scm.$DOMAIN
    echo "Hostname configurado como cdp-scm.$DOMAIN"
  else
    ## Configurar el hostname del nodo actual correspondiente
    read -p "Ingrese el numero del nodo agente que está configurando: " AGENT_NODE
    sudo hostnamectl set-hostname cdp-node$AGENT_NODE.$DOMAIN
    echo "Hostname configurado como cdp-node$AGENT_NODE.$DOMAIN"
  fi

  ## Inicializar las entradas de hosts
  HOSTS_ENTRIES="## IP Privada              Nombre FQDN                    Alias corto\n"

  ## Solicitar las IPs para cada nodo con valores por defecto
  for ((i=1; i<=NUM_NODES; i++)); do
    name_node="" 
    if [ $i == 1 ]; then
      ## Nodo SCM
      read -p "Ingrese la IP del nodo SCM: " IP
      name_node="cdp-scm"
    else
      ## Nodo Worker
      read -p "Ingrese la IP del nodo Worker $((i-1)): " IP
      name_node="cdp-node$((i-1))"
    fi
    if [ -z "$IP" ]; then
      echo "Error: La IP no puede estar vacía."
      exit 1
    fi
    ## Validar formato de IP (estricto)
    if ! [[ "$IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      echo "Error: La IP $IP no tiene un formato válido."
      exit 1
    fi
    HOSTS_ENTRIES+="$IP        $name_node.$DOMAIN           $name_node\n"
  done



  ## Agregar las entradas al archivo /etc/hosts
  echo -e "$HOSTS_ENTRIES" | sudo tee -a /etc/hosts > /dev/null

  ## Mostrar las entradas agregadas
  echo -e "\nSe ha agregado el siguiente bloque a su archivo hosts:"
  echo -e "$HOSTS_ENTRIES"
  sudo cp /etc/hosts ./hosts-dist
  echo "Se ha realizado una copia del archivo host en el directorio actual llamado 'hosts-dist'"
  echo "Copie/Descargue este archivo y coloquelo en cada nodo en /etc/hosts"
  echo "Presione cualquier ENTER para continuar..."
  read -r

fi



## En cada nodo, editar /etc/resolv.conf (o crear drop-in for NetworkManager):
echo "Configurando /etc/resolv.conf... para AD"
read -p "Ingrese la IP del Controlador de Dominio 1: " IP_DC1
read -p "Ingrese la IP del Controlador de Dominio 2: " IP_DC2

sudo sed -i "1inameserver $IP_DC1\nnameserver $IP_DC2\nsearch $DOMAIN" /etc/resolv.conf

dig +short _ldap._tcp.$DOMAIN SRV
echo "Archivo /etc/resolv.conf configurado."


## Verificar conectividad con otros nodos
echo -e "\nVerificando conectividad con otros nodos..."
ALL_PINGS_SUCCESSFUL=true
for ((i=1; i<=NUM_NODES; i++)); do
  NODE="cdp-node$i"
  if [ $i == 1 ]; then
    NODE="cdp-scm"
  fi
  echo -n "Haciendo ping a $((NODE-1))... "
  if ping -c 2 -W 2 "$NODE" > /dev/null 2>&1; then
    echo "Éxito"
  else
    echo "Fallo"
    ALL_PINGS_SUCCESSFUL=false
  fi
done
if ! $ALL_PINGS_SUCCESSFUL; then
  echo "Advertencia: No se pudo conectar con uno o más nodos. Verifique la configuración de red."
  read -p "¿Desea continuar de todos modos? [y/N]: " CONTINUE_ANYWAY
  CONTINUE_ANYWAY=${CONTINUE_ANYWAY:-N}
  if [[ "$CONTINUE_ANYWAY" != [yY] ]]; then
    echo "Operación cancelada por el usuario."
    exit 1
  fi
fi

## Instalación de Kerberos
echo "Instalando Kerberos..."
sudo dnf install -y krb5-workstation krb5-libs

if [ $? -eq 0 ]; then
  echo "Iniciando y habilitando el servicio Kerberos..."
  sudo systemctl enable --now krb5kdc
  echo "Verificando estado del servicio Kerberos:"
  sudo systemctl status krb5kdc
  echo "Kerberos instalado exitosamente."
  
else
  echo "Error: No se pudieron instalar algunos paquetes."
  exit 1
fi


## Instalación de Open LDAP
echo "Instalando Open LDAP..."
sudo dnf install -y openldap-clients
if [ $? -eq 0 ]; then
  echo "Open LDAP instalado exitosamente."
else
  echo "Error: No se pudieron instalar algunos paquetes."
  exit 1
fi


## Instalación de requisitos para AD
echo "Instalado paquetes para la configuración de Active Directory..."
sudo dnf -y install realmd sssd sssd-tools oddjob oddjob-mkhomedir samba-common-tools adcli
if [ $? -eq 0 ]; then
  echo "Paquetes instalados exitosamente."
else
  echo "Error: No se pudieron instalar algunos paquetes."
  exit 1
fi

## Uniendo dominios de AD
echo "Uniendo el nodo al dominio de Active Directory..."
sudo realm discover ${DOMAIN^^}
sudo realm join --verbose ${DOMAIN^^} -U "Admin@${DOMAIN^^}"
realm list
id "Admin@${DOMAIN^^}"
if [ $? -eq 0 ]; then
  echo "Nodo unido exitosamente al dominio $DOMAIN."
else
  echo "Error: No se pudo unir el nodo al dominio $DOMAIN."
  exit 1
fi


## Configurar SELinux a permissive en el nodo actual
if [ -f /etc/selinux/config ]; then
  sudo cp /etc/selinux/config /etc/selinux/config.bak
  echo "Copia de seguridad de /etc/selinux/config creada en /etc/selinux/config.bak"
  sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
  if grep -q '^SELINUX=permissive' /etc/selinux/config; then
    echo "SELinux configurado a permissive exitosamente en /etc/selinux/config."
    sudo setenforce 0
    echo "SELinux establecido a permissive para la sesión actual."
  else
    echo "Error: No se pudo configurar SELinux a permissive."
    exit 1
  fi
else
  echo "Advertencia: El archivo /etc/selinux/config no existe. SELinux puede no estar habilitado."
fi

## Desactivar firewalld en el nodo actual
if command -v firewall-cmd > /dev/null 2>&1; then
  if systemctl is-active firewalld > /dev/null 2>&1; then
    echo "Desactivando firewalld..."
    sudo systemctl disable --now firewalld
    if ! systemctl is-active firewalld > /dev/null 2>&1; then
      echo "firewalld ha sido desactivado exitosamente."
    else
      echo "Error: No se pudo desactivar firewalld."
      exit 1
    fi
  else
    echo "firewalld no está activo."
  fi
else
  echo "firewalld no está instalado."
fi

## Configurar límites en /etc/security/limits.conf en el nodo actual
sudo cp /etc/security/limits.conf /etc/security/limits.conf.bak
echo "Copia de seguridad de /etc/security/limits.conf creada en /etc/security/limits.conf.bak"
LIMITS_ENTRIES="*                soft    nofile          1048576
*                hard    nofile          1048576
*                soft    nproc           65536
*                hard    nproc           65536"
echo "$LIMITS_ENTRIES" | sudo tee -a /etc/security/limits.conf > /dev/null
if grep -q "nofile          1048576" /etc/security/limits.conf && grep -q "nproc           65536" /etc/security/limits.conf; then
  echo "Límites configurados exitosamente en /etc/security/limits.conf."
else
  echo "Error: No se pudieron configurar los límites en /etc/security/limits.conf."
  exit 1
fi

## Configurar sysctl
echo "Configurando vm.swappiness..."
echo "vm.swappiness=1" | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -w vm.swappiness=1
echo "vm.swappiness configurado a 1."

## Desactivar Transparent Huge Pages
echo "Desactivando Transparent Huge Pages..."
echo "never" | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null
echo "never" | sudo tee /sys/kernel/mm/transparent_hugepage/defrag > /dev/null
echo "Transparent Huge Pages desactivado."

## Activar FIPS
## echo "Activando FIPS..."
## status_fips=$(sudo fips-mode-setup --check)
## if [[ "$status_fips" == *"FIPS mode is disabled"* ]]; then
##   echo "FIPS está actualmente desactivado. Procediendo a activarlo..."
##   sudo fips-mode-setup --enable 
## else
##   echo "FIPS ya está activado. No se requieren cambios."
## fi 


# Paso 1
## Configuración del repositorio de Cloudera Manager
echo "Configurando el repositorio de Cloudera Manager desde $REPO_URL..."
wget "$REPO_URL"
sudo mv cloudera-manager.repo /etc/yum.repos.d/cloudera-manager.repo
sudo dnf update -y

# Paso 2
## Instalar java 17
echo "Instalando OpenJDK..."
sudo dnf -y install java-17-openjdk-devel
if [ $? -eq 0 ]; then
  echo "OpenJDK 17 instalado exitosamente."
else
  echo "Error: No se pudieron instalar algunos paquetes."
  exit 1
fi

# Paso 3
## Instalar postgresql desde el repositorio de Cloudera
echo "Instalando PostgreSQL..."
sudo dnf -y remove postgresql postgresql-server
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql
sudo dnf update -y
sudo dnf install -y postgresql17-server #postgresql17-devel

if [ $? -eq 0 ]; then
  echo "Configurando PostgreSQL..."
  sudo /usr/pgsql-17/bin/postgresql-17-setup initdb
  sudo systemctl enable postgresql-17
  sudo systemctl start postgresql-17
  echo "Instalando driver jdbc version 42.7.6..."
  wget https://jdbc.postgresql.org/download/postgresql-42.7.6.jar
  mv postgresql-42.7.6.jar postgresql-jdbc.jar
  sudo mv postgresql-jdbc.jar /usr/share/java/postgresql-connector-java.jar
  sudo chmod 644 /usr/share/java/postgresql-connector-java.jar
  ## Instalando paquete de python para postgresql
  sudo dnf install -y python3-psycopg2
  python3.8 -m pip install psycopg2-binary
  echo "Postgresql instalado exitosamente."
else
  echo "Error: No se pudieron instalar algunos paquetes."
  exit 1
fi


# Paso 4
## Configurar base de datos para Cloudera Manager
echo "Configurando base de datos para Cloudera Manager..."
read -p "Ingrese nombre de la base de datos: " DB_NAME
while true; do
  read -p "Ingrese nombre de usuario: " USER_DB
  if [[ "$USER_DB" == *"-"* ]]; then
    echo "Error: El nombre de usuario no puede contener el carácter '-'. Intente nuevamente."
  else
    break
  fi
done
read -p "Ingrese contraseña para el usuario: " PASSWORD_DB
sudo -u postgres psql -c "CREATE USER $USER_DB WITH PASSWORD '$PASSWORD_DB' CREATEDB;"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $USER_DB;"



# Paso 5
## Instalar Cloudera manager y desplegar
echo "Instalando Cloudera Manager..."
sudo dnf -y install $PACKAGES
if [ $? -eq 0 ]; then
  echo "Cloudera Manager instalado exitosamente."
  sudo /opt/cloudera/cm/schema/scm_prepare_database.sh postgresql $DB_NAME $USER_DB $PASSWORD_DB
  sudo systemctl enable cloudera-scm-server
  sudo systemctl enable cloudera-scm-agent
  echo "Servicios de Cloudera Manager habilitados para iniciar en el arranque."
  sudo systemctl start cloudera-scm-server
  sudo systemctl start cloudera-scm-agent
  echo "Servicios de Cloudera Manager iniciados."
else
  echo "Error: No se pudo instalar Cloudera Manager."
  exit 1
fi


# Preguntar si desea reiniciar
read -p "¿Desea reiniciar el sistema ahora? [y/N]: " REBOOT
REBOOT=${REBOOT:-N}
if [[ "$REBOOT" == "y" || "$REBOOT" == "Y" ]]; then
  echo "Reiniciando el sistema..."
  sudo reboot now
else
  echo "Reinicio omitido. Por favor, reinicie manualmente para aplicar todos los cambios."
fi

## Esperar a que el usuario presione una tecla
read -n 1 -s -r -p $'\nPresione una tecla para salir de la configuración...\n'