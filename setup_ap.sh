#!/bin/bash
set -e

SSID="RPI4_AP"
PASS="11111111"
IP="192.168.1.1/24"
GW="192.168.1.1"
DHCP_START="192.168.1.10"
DHCP_END="192.168.1.50"

echo "[1] Установка пакетов"
apt update
apt install -y hostapd dnsmasq iw

systemctl unmask hostapd
systemctl enable hostapd

echo "[2] Отключаем wlan0 от NetworkManager (если есть)"
nmcli dev set wlan0 managed no 2>/dev/null || true
nmcli dev disconnect wlan0 2>/dev/null || true

echo "[3] Ставим статический IP через dhcpcd (защита от сброса)"
sed -i '/interface wlan0/,$d' /etc/dhcpcd.conf || true
cat >> /etc/dhcpcd.conf <<EOF
interface wlan0
    static ip_address=$IP
    nohook wpa_supplicant
EOF
systemctl restart dhcpcd
sleep 2

echo "[4] Настраиваем hostapd"
cat > /etc/hostapd/hostapd.conf <<EOF
country_code=UA
interface=wlan0
ssid=$SSID
hw_mode=g
channel=6

wmm_enabled=1
auth_algs=1

wpa=2
wpa_passphrase=$PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd

echo "[5] Настраиваем dnsmasq (DHCP-сервер)"
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig 2>/dev/null || true
cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,24h
EOF

echo "[6] Перезапуск сервисов"
systemctl restart hostapd
systemctl restart dnsmasq

echo "========================================="
echo "Готово! Точка доступа $SSID успешно поднята."
echo "========================================="