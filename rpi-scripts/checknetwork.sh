sudo iptables -t nat -D POSTROUTING -o OBwlan0 -j MASQUERADE 2>/dev/null
sudo iptables -t nat -D PREROUTING -p tcp -d 192.168.32.1 --dport 443 -j REDIRECT --to-port 5000 2>/dev/null
sudo iptables -t nat -A POSTROUTING -o OBwlan0 -j MASQUERADE
sudo iptables -t nat -A PREROUTING -p tcp -d 192.168.32.1 --dport 443 -j REDIRECT --to-port 5000
if ! nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device | grep -q "^wlan0:wifi:connected:usdx"; then
  nmcli connection up usdx
fi
sudo ip route del default 2>/dev/null
sudo ip route del default 2>/dev/null
sudo ip route add default via 192.168.0.1 dev OBwlan0
