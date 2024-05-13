# autoOVPN

This scritp automates the installation & automatization o open VPN in linux. Rigth now it has only been proved in ubuntu server.

You should run it with sudo before.

You shoud be careful with the following command in it: 
# Paso 7: Configurar NAT para la subred VPN
# interface=$(ifconfig | awk 'NR==1 {print $1}' | tr -d :)
# sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$interface" -j MASQUERADE 

This part of the script takes the interface as the first argument of the first line suposing that is the one you need but that can change in your own device (in the future i may implant an update that ask the user the ip and selects the intfz through that)