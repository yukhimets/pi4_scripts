#!/bin/bash

# =====================================================================
# НАСТРОЙКИ ЗАХВАТА
# =====================================================================
# Слушаем интерфейс моста br0 (исключает дублирование пакетов)
INTERFACES="br0" 
SAVE_DIR="/mnt/flash64/traffic"

# Размер одного файла в Кб (5000 = 5Мб)
FILE_SIZE="5000" 

# Фильтр пустой — пишем абсолютно всё (BPF формат)
FILTER=""
# =====================================================================

# На всякий случай принудительно отмонтируем точку, если что-то зависло
sudo umount /mnt/flash64 2>/dev/null

# Силовое циклическое монтирование физического USB-устройства (/dev/sda1)
COUNTER=0
while [ $COUNTER -lt 15 ]; do
    if [ -b /dev/sda1 ]; then
        echo "Флешка обнаружена в USB. Монтирую..."
        # Пробуем примонтировать как exfat. Если система старая — монтируем стандартно
        sudo mount -t exfat /dev/sda1 /mnt/flash64 -o iocharset=utf8,umask=000 2>/dev/null || sudo mount /dev/sda1 /mnt/flash64 -o iocharset=utf8,umask=000 2>/dev/null
        
        # Проверяем, привязался ли физический диск к папке
        if mountpoint -q /mnt/flash64; then
            echo "Успех! Флешка привязана к /mnt/flash64"
            break
        fi
    fi
    echo "Ожидание флешки в USB-порту... ($COUNTER сек)"
    sleep 1
    let COUNTER=COUNTER+1
done

# Если за 15 секунд флешка не смонтировалась — тушим скрипт, чтобы не забить внутреннюю SD-карту
if ! mountpoint -q /mnt/flash64; then
    echo "КРИТИЧЕСКАЯ ОШИБКА: Флешка не примонтирована. Захват отменен."
    exit 1
fi

# Включаем Promiscuous Mode на мосту, чтобы ловить абсолютно все чужие пакеты
sudo ip link set dev br0 promisc on

# Создаем папку для трафика непосредственно НА ФЛЕШКЕ
mkdir -p "$SAVE_DIR"

# Формируем аргументы интерфейсов для dumpcap
IFACE_ARGS=""
for iface in $INTERFACES; do
    IFACE_ARGS="$IFACE_ARGS -i $iface"
done

# Запуск процесса захвата трафика через exec
if [ -z "$FILTER" ]; then
    exec /usr/bin/dumpcap $IFACE_ARGS -b filesize:"$FILE_SIZE" -w "$SAVE_DIR/capture.pcap"
else
    exec /usr/bin/dumpcap $IFACE_ARGS -f "$FILTER" -b filesize:"$FILE_SIZE" -w "$SAVE_DIR/capture.pcap"
fi