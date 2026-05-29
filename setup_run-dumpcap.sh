#!/bin/bash

# Завершать скрипт при любой ошибке
set -e

# =====================================================================
# НАСТРОЙКИ ЖЕЛЕЗА (Убедись, что имена eth0 и eth1 совпадают с твоими)
# =====================================================================
IFACE_1="eth0"
IFACE_2="eth1"
# =====================================================================

echo "=== ШАГ 1: Обновление системы и установка пакетов ==="
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y tshark conspy

echo "=== ШАГ 2: Настройка прав для dumpcap ==="
sudo chmod +x /usr/bin/dumpcap
sudo setcap cap_net_raw,cap_net_admin+eip /usr/bin/dumpcap || true

echo "=== ШАГ 3: Создание точек монтирования ==="
sudo mkdir -p /mnt/flash64
sudo chmod 777 /mnt/flash64

echo "=== ШАГ 4: Сборка прозрачного моста через NetworkManager ==="
# Удаляем старые профили для этих интерфейсов, чтобы не было конфликтов
sudo nmcli connection delete br0 2>/dev/null || true
sudo nmcli connection delete br0-slave1 2>/dev/null || true
sudo nmcli connection delete br0-slave2 2>/dev/null || true
sudo nmcli connection delete "$IFACE_1" 2>/dev/null || true
sudo nmcli connection delete "$IFACE_2" 2>/dev/null || true

# Создаем интерфейс моста, полностью отключая на нем IPv4 и IPv6 (полная скрытность)
sudo nmcli connection add type bridge con-name br0 ifname br0 ipv4.method disabled ipv6.method disabled

# Жестко привязываем физические карты к нашему мосту
sudo nmcli connection add type bridge-slave con-name br0-slave1 ifname "$IFACE_1" master br0
sudo nmcli connection add type bridge-slave con-name br0-slave2 ifname "$IFACE_2" master br0

# Принудительно включаем режим promiscuous (перехват всех чужих пакетов) на уровне NM
sudo nmcli connection modify br0 ethernet.accept-all-mac-addresses 1

# Активируем мост прямо сейчас
sudo nmcli connection up br0

echo "=== ШАГ 5: Копирование рабочего скрипта на Рабочий стол ==="
CURRENT_DIR=$(dirname "$(readlink -f "$0")")
cp "$CURRENT_DIR/run-dumpcap.sh" /home/pi/Desktop/run-dumpcap.sh
sudo sed -i 's/\r$//' /home/pi/Desktop/run-dumpcap.sh
chmod +x /home/pi/Desktop/run-dumpcap.sh
chown pi:pi /home/pi/Desktop/run-dumpcap.sh

echo "=== ШАГ 6: Создание ярлыка для флешки ==="
rm -f /home/pi/Desktop/traffic_flash
ln -s /mnt/flash64/traffic /home/pi/Desktop/traffic_flash

echo "=== ШАГ 7: Создание быстрой команды 'traffic' ==="
sudo sed -i '/alias traffic=/d' /etc/bash.bashrc || true
sudo tee -a /etc/bash.bashrc << 'EOF'
alias traffic="sudo conspy 3 2>/dev/null || sudo journalctl -u getty@tty3.service -f"
EOF

echo "=== ШАГ 8: Создание и настройка службы автозапуска Systemd ==="
sudo mkdir -p /etc/systemd/system/getty@tty3.service.d
sudo tee /etc/systemd/system/getty@tty3.service.d/override.conf << EOF
[Unit]
Description=Служба автозапуска сниффера трафика на TTY3
After=NetworkManager.target local-fs.target
Wants=NetworkManager.target local-fs.target

[Service]
ExecStart=
ExecStart=-/home/pi/Desktop/run-dumpcap.sh
StandardInput=tty
StandardOutput=tty
Type=idle
EOF

echo "=== ШАГ 9: Перезапуск демонов и включение службы ==="
sudo systemctl daemon-reload
sudo systemctl enable getty@tty3.service

echo "======================================================="
echo " СОВРЕМЕННАЯ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!"
echo " Мост br0 собран и активирован."
echo " Система уйдет в перезагрузку через 5 секунд..."
echo "======================================================="
sleep 5
sudo reboot