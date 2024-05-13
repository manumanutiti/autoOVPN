#!/bin/bash

#Ejecutar con sudo ./autoOVPN 
#El codigo es estable 13/05/2024. El comando iptable que requiere de escribir la interfaz es dinámico y lo 
#obtiene de forma automática al igual que la ip (Si no funciona puedes ajustarlos manualmente). 
#La interfaz y la ip se obtienen en base al output del cli de ifconfig suponiendo que la itfaz y la ip están en la primera linea (Esto podría cambiar en diferentes pcs))
#directorios debería funcionar corrrectamente Mientras easyrsa y openvpn no cambien la estructura de sus
#la ruta de las iptables no existe, aun asi no parece afectar

# Paso 1: Actualizar e instalar openvpn y easy-rsa e iptables
sudo apt update
sudo apt install -y openvpn easy-rsa
sudo apt-get install net-tools


if ! command -v iptables &> /dev/null
then
    
    sudo apt-get install -y iptables
    
fi

# Paso 2: Generar claves y certificados
cd /usr/share/easy-rsa || exit
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa gen-req server nopass
./easyrsa sign-req server server
./easyrsa gen-dh
openvpn --genkey --secret pki/private/ta.key

# Paso 3: Configurar el servidor openvpn
sudo cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem pki/private/ta.key /etc/openvpn/server/
sudo tee /etc/openvpn/server/server.conf > /dev/null <<EOF
port 1194
proto udp
dev tun
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/server.crt
key /etc/openvpn/server/server.key
dh /etc/openvpn/server/dh.pem
auth SHA256
tls-auth /etc/openvpn/server/ta.key 0
key-direction 0
cipher AES-256-CBC
user nobody
group nogroup
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 208.67.222.222"
push "dhcp-option DNS 208.67.220.220"
keepalive 10 120
comp-lzo
persist-key
persist-tun
status openvpn-status.log
verb 3
explicit-exit-notify 1
client-to-client
EOF

# Paso 4: Habilitar el reenvío de paquetes IP
sudo sed -i '/#net.ipv4.ip_forward=1/s/^#//g' /etc/sysctl.conf
sudo sysctl -p

# Paso 5: Iniciar y habilitar el servicio openvpn
sudo systemctl start openvpn-server@server
sudo systemctl enable openvpn-server@server

# Paso 6: Configurar el cliente
echo ""
echo ""
read -p "[!] Insert the client name: " client_name
./easyrsa gen-req "$client_name" nopass
./easyrsa sign-req client "$client_name"


# Paso 7: Configurar NAT para la subred VPN
interface=$(ifconfig | awk 'NR==1 {print $1}' | tr -d :)
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$interface" -j MASQUERADE

# Paso 8: Configuración del firewall
# Asegúrate de personalizar las reglas según tus necesidades
sudo tee /etc/iptables/rules.v4 > /dev/null <<RULES
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -p tcp -m conntrack --ctstate NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p udp -m conntrack --ctstate NEW -m udp --dport 1194 -j ACCEPT
-A INPUT -p tcp -m conntrack --ctstate NEW -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m conntrack --ctstate NEW -m tcp --dport 443 -j ACCEPT
-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -s 10.8.0.0/24 -j ACCEPT
COMMIT
RULES

# Habilita el mantenimiento de las reglas de iptables después de reiniciar
sudo iptables-save | sudo tee /etc/iptables/rules.v4

# Aplica las reglas de iptables
sudo iptables-restore < /etc/iptables/rules.v4

# Habilita el servicio de iptables-persistent
sudo apt-get install -y iptables-persistent

# Habilita la persistencia del reenvío de paquetes IP
#adrisudo sed -i '/^#net.ipv4.ip_forward=1/s/^#//g' /etc/sysctl.conf
sudo sysctl -p


##############################################################
# Archivos de cliente a mano

# Carpeta de destino en el directorio de inicio del usuario
folder="$HOME/openvpn_client_files/"${client_name}""

# Crear la carpeta de destino si no existe
sudo mkdir -p "$folder"

# Copiar los archivos con sudo
sudo cp /etc/openvpn/server/ca.crt "$folder/ca.crt"
sudo cp /usr/share/easy-rsa/pki/issued/"${client_name}".crt "$folder/"${client_name}".crt"
sudo cp /usr/share/easy-rsa/pki/private/"${client_name}".key "$folder/"${client_name}".key"
sudo cp /usr/share/easy-rsa/pki/private/ta.key "$folder/ta.key"

#################################




# Obtener la dirección IP del servidor
server_ip=$(ifconfig | grep "inet" | awk 'NR==1 {print $2}')

# Solicitar nombre del cliente




# Contenido de los archivos
ca_content=$(cat /etc/openvpn/server/ca.crt)
cert_content=$(cat /usr/share/easy-rsa/pki/issued/${client_name}.crt)
key_content=$(cat /usr/share/easy-rsa/pki/private/${client_name}.key)
tls_auth_content=$(cat /usr/share/easy-rsa/pki/private/ta.key)

# Texto del archivo .ovpn
ovpn_text="
client
dev tun
proto udp
remote $server_ip 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
auth-nocache
cipher AES-256-CBC
tls-client
tls-auth ta.key 1
key-direction 1
comp-lzo
verb 3
<ca>
$ca_content
</ca>
<cert>
$cert_content
</cert>
<key>
$key_content
</key>
<tls-auth>
$tls_auth_content
</tls-auth>
"

# Guardar el texto en un archivo .ovpn

sudo mkdir /root/openvpn_client_files/"${client_name}"

echo "$ovpn_text" > /root/openvpn_client_files/"${client_name}"/"${client_name}"_config.ovpn



echo "Client conf files created successfully"

################################




green_color="\e[32m"
reset_color="\e[0m"

echo  "${green_color}[+] Installed and confd successfully${reset_color}"
echo ""
echo "/root/openvpn_client_files look here for files, .opvn file automatically created here"
