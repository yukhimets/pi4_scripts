#!/bin/bash

# Завершать скрипт при любой ошибке
set -e

# =====================================================================
# НАСТРОЙКИ ЖЕЛЕЗА (Поменяйте eth0 и eth1 на ваши интерфейсы, если нужно)
# =====================================================================
IFACE_1="eth0"
IFACE_2="eth1"
# =====================================================================

echo "=== ШАГ 1: Обновление системы и установка пакетов ==="
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y tshark bridge-utils conspy

echo "=== ШАГ 2: Настройка прав для dumpcap ==="
sudo chmod +x /usr/bin/dumpcap
sudo setcap cap_net_raw,cap_net_admin+eip /usr/bin/dumpcap || true

echo "=== ШАГ 3: Создание точек монтирования ==="
sudo mkdir -p /mnt/flash64
sudo chmod 777 /mnt/flash64

echo "=== ШАГ 4: Настройка сетевого моста (/etc/network/interfaces) ==="
sudo tee /etc/network/interfaces << EOF
source-directory /etc/network/interfaces.d

auto br0
iface br0 inet manual
    bridge_ports $IFACE_1 $IFACE_2
    up ip link set dev br0 promisc on
EOF

echo "=== ШАГ 5: Изоляция интерфейсов моста ==="
# Удаляем старые запреты из конфига, если они там были
sudo sed -i '/denyinterfaces/d' /etc/dhcpcd.conf || true
# Вставляем запрет строго в начало файла, чтобы не сломать настройки AP
sudo sed -i "1s/^/denyinterfaces $IFACE_1 $IFACE_2 br0\n/" /etc/dhcpcd.conf

echo "=== ШАГ 6: Копирование рабочего скрипта на Рабочий стол ==="
CURRENT_DIR=$(dirname "$(readlink -f "$0")")
cp "$CURRENT_DIR/run-dumpcap.sh" /home/pi/Desktop/run-dumpcap.sh
sudo sed -i 's/\r$//' /home/pi/Desktop/run-dumpcap.sh
chmod +x /home/pi/Desktop/run-dumpcap.sh
chown pi:pi /home/pi/Desktop/run-dumpcap.sh

echo "=== ШАГ 7: Создание ярлыка для флешки ==="
rm -f /home/pi/Desktop/traffic_flash
ln -s /mnt/flash64/traffic /home/pi/Desktop/traffic_flash

echo "=== ШАГ 8: Создание быстрой команды 'traffic' ==="
sudo sed -i '/alias traffic=/d' /etc/bash.bashrc || true
sudo tee -a /etc/bash.bashrc << 'EOF'
alias traffic="sudo conspy 3 2>/dev/null || sudo journalctl -u getty@tty3.service -f"
EOF

echo "=== ШАГ 9: Отключение конфликтующих PPPoE служб ==="
sudo systemctl disable dsl-provider 2>/dev/null || true

echo "=== ШАГ 10: Создание и настройка службы автозапуска Systemd ==="
sudo mkdir -p /etc/systemd/system/getty@tty3.service.d
sudo tee /etc/systemd/system/getty@tty3.service.d/override.conf << EOF
[Unit]
Description=Служба автозапуска сниффера трафика на TTY3
After=network-online.target local-fs.target
Wants=network-online.target local-fs.target

[Service]
ExecStart=
ExecStart=-/home/pi/Desktop/run-dumpcap.sh
StandardInput=tty
StandardOutput=tty
Type=idle
EOF

echo "=== ШАГ 11: Перезапуск демонов и включение службы ==="
sudo systemctl daemon-reload
sudo systemctl enable getty@tty3.service

echo "======================================================="
echo " УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!"
echo " Малина уйдет в перезагрузку через 5 секунд..."
echo "======================================================="
sleep 5
sudo reboot