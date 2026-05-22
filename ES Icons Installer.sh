#!/bin/bash

#--------------------------------#
#      ES Installer - R36S       #
#          By Jason              #
#--------------------------------#

# --- Vérification des privilèges root ---
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E "$0" "$@"
fi

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CURR_TTY="/dev/tty1"
BACKTITLE="ES Installer R36S - By Jason -"

RAW_BASE="https://raw.githubusercontent.com/Jason3x/ES-Installer/main"
API_BASE="https://api.github.com/repos/Jason3x/ES-Installer/contents"

# Noms des fichiers sur le dépôt 
ES_DARKS_URL="$RAW_BASE/ES%20dArkOS%20RE"
ES_DARKS4_URL="$RAW_BASE/ES%20darkos4clone"
SVG_API_URL="$API_BASE/SVG%20Icons"

ES_INSTALL_PATH="/usr/bin/emulationstation/emulationstation"
ES_RESOURCES_PATH="/usr/bin/emulationstation/resources"
ES_BACKUP="/root/es_original_backup"
BACKUP_FLAG="/root/.es_installer_backup_done"

# --- Préparation affichage ---
printf "\033c" > "$CURR_TTY"
printf "\e[?25l" > "$CURR_TTY"
dialog --clear

# --- Sélection de la police ---
if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
    setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz
else
    setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz
fi

pkill -9 -f gptokeyb || true
pkill -9 -f osk.py    || true

# --- Animation splash ---
printf "\033c" > "$CURR_TTY"

for i in {1..2}; do
    printf "Starting ES Installer...\nPlease wait." > "$CURR_TTY"
    sleep 0.6
    printf "\033c" > "$CURR_TTY"
    sleep 0.4
done

# --- Message de bienvenue ---
printf "\033c" > "$CURR_TTY"
printf "\n\n" > "$CURR_TTY"
printf "      ========================================\n" > "$CURR_TTY"
printf "             Welcome to ES Installer          \n" > "$CURR_TTY"
printf "                    By Jason                  \n" > "$CURR_TTY"
printf "      ========================================\n" > "$CURR_TTY"
sleep 2

printf "\033c" > "$CURR_TTY"

# --- Progression fluide ---
smooth_progress() {
    local msg=$1
    local delay=$2
    local start_val=$3
    local end_val=$4
    for ((i=start_val; i<=end_val; i++)); do
        echo "$i"
        echo "XXX"; echo -e "$msg"; echo "XXX"
        sleep "$delay"
    done
}

# --- Vérification connexion Internet ---
check_internet() {
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        dialog --backtitle "$BACKTITLE" --title "Network Error" \
            --msgbox "\nInternet connection required.\nPlease check your WiFi." 8 55 > "$CURR_TTY"
        return 1
    fi
    return 0
}

# --- Sauvegarde de l'ES ---
backup_es_if_needed() {
    if [ ! -f "$BACKUP_FLAG" ]; then
        if [ -f "$ES_INSTALL_PATH" ]; then
            cp "$ES_INSTALL_PATH" "$ES_BACKUP"
            touch "$BACKUP_FLAG"
        fi
    fi
}

# --- Téléchargement des SVG ---
download_svgs() {
    mkdir -p "$ES_RESOURCES_PATH"

    local svg_list
    svg_list=$(wget -qO- "$SVG_API_URL" 2>/dev/null)

    if [ -z "$svg_list" ]; then
        return 1
    fi

    local urls
    urls=$(echo "$svg_list" \
        | grep -o '"download_url": *"[^"]*"' \
        | sed 's/"download_url": *"//;s/"$//')

    while IFS= read -r url; do
        [ -z "$url" ] && continue
        local filename
        filename=$(basename "$url" | cut -d'?' -f1)
        wget -q -O "$ES_RESOURCES_PATH/$filename" "$url" 2>/dev/null
    done <<< "$urls"

    return 0
}

# --- Suppression des SVG installés ---
remove_svgs() {
    local svg_list
    svg_list=$(wget -qO- "$SVG_API_URL" 2>/dev/null)

    if [ -n "$svg_list" ]; then
        local names
        names=$(echo "$svg_list" \
            | grep -o '"name": *"[^"]*\.svg"' \
            | sed 's/"name": *"//;s/"$//')

        while IFS= read -r name; do
            [ -z "$name" ] && continue
            rm -f "$ES_RESOURCES_PATH/$name"
        done <<< "$names"
    fi
}

# --- Optimisations du lancement ---
apply_optimizations() {
    ES_LAUNCH="/usr/bin/emulationstation/emulationstation.sh"

    if [ ! -f "${ES_LAUNCH}.bak" ]; then
        cp "$ES_LAUNCH" "${ES_LAUNCH}.bak"
    fi

    sed -i '/ff400000.gpu.*governor/d' "$ES_LAUNCH"
    sed -i '/policy0.*scaling_governor/d' "$ES_LAUNCH"
    sed -i '/dmc.*governor/d' "$ES_LAUNCH"

    sed -i '/export SDL_VIDEO_DOUBLE_BUFFER/d' "$ES_LAUNCH"
    
    if ! grep -q "schedutil" "$ES_LAUNCH"; then
        sed -i 's|rm -f /tmp/es-restart /tmp/es-sysrestart /tmp/es-shutdown|echo schedutil | tee /sys/devices/system/cpu/cpufreq/policy0/scaling_governor > /dev/null\n        echo 1200000 | tee /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq > /dev/null\n        iw dev wlan0 set power_save on 2>/dev/null || true\n        rm -f /tmp/es-restart /tmp/es-sysrestart /tmp/es-shutdown|' "$ES_LAUNCH"
    fi
    
    if ! grep -q "SDL_RENDER_VSYNC" "$ES_LAUNCH"; then
        sed -i 's|export SDL_ASSERT="always_ignore"|export SDL_ASSERT="always_ignore"\nexport SDL_RENDER_VSYNC=0\nexport SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1|' "$ES_LAUNCH"
    else
        if ! grep -q "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS" "$ES_LAUNCH"; then
            sed -i 's|export SDL_RENDER_VSYNC=0|export SDL_RENDER_VSYNC=0\nexport SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1|' "$ES_LAUNCH"
        fi
    fi

    # Background daemon -- detection WiFi/BT en tache de fond
    DAEMON_SCRIPT="/usr/local/bin/es-status-daemon.sh"
    DAEMON_SERVICE="/etc/systemd/system/es-status-daemon.service"

    cat > "$DAEMON_SCRIPT" << 'DAEMONEOF'
#!/bin/bash
# ES Status Daemon -- detects WiFi and Bluetooth state
# Writes state to /tmp/es-wifi-state and /tmp/es-bt-state
# WiFi states: 0=off 1=no-ip 2=connected 3=sharing-active 4=service-up
# BT states:   0=off 1=active-no-device 2=device-connected

detect_wifi() {
    rfkill list wifi 2>/dev/null | grep -iq "soft blocked: yes" && echo 0 && return
    ip link show wlan0 2>/dev/null | grep -q "wlan0" || { echo 0; return; }
    nmcli -t -f DEVICE,STATE dev 2>/dev/null | grep -qE "^wlan.*:connected$" || { echo 1; return; }
    # Connected -- check active sharing client
    ss -tn state established 2>/dev/null | grep -qE ":22 |:445 |:53 " && echo 3 && return
    # Check services running (SSH/Samba/filebrowser)
    { systemctl is-active smbd nmbd ssh.service 2>/dev/null | grep -xqm1 active || \
      pgrep -x filebrowser > /dev/null 2>&1; } && echo 4 && return
    echo 2
}

detect_bt() {
    rfkill list bluetooth 2>/dev/null | grep -iq "soft blocked: yes" && echo 0 && return
    systemctl is-active bluetooth 2>/dev/null | grep -qx active || { echo 0; return; }
    hciconfig 2>/dev/null | grep -qE "^hci" || { echo 0; return; }
    conn=$(bluetoothctl devices Connected 2>/dev/null | grep -c Device)
    [ "$conn" -gt 0 ] 2>/dev/null && echo 2 && return
    echo 1
}

while true; do
    # Atomic write: file is never empty/partial when ES reads it
    wifi_val=$(detect_wifi)
    bt_val=$(detect_bt)
    echo "$wifi_val" > /tmp/es-wifi-state.tmp && mv /tmp/es-wifi-state.tmp /tmp/es-wifi-state
    echo "$bt_val"   > /tmp/es-bt-state.tmp   && mv /tmp/es-bt-state.tmp   /tmp/es-bt-state
    sleep 5
done
DAEMONEOF

    chmod +x "$DAEMON_SCRIPT"

    cat > "$DAEMON_SERVICE" << 'SVCEOF'
[Unit]
Description=EmulationStation WiFi/BT Status Daemon
After=network.target bluetooth.target

[Service]
Type=simple
ExecStart=/usr/local/bin/es-status-daemon.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable es-status-daemon.service
    systemctl restart es-status-daemon.service

    NM_DISPATCH="/etc/NetworkManager/dispatcher.d/99-es-wifi-icon"
    if [ ! -f "$NM_DISPATCH" ]; then
        cat > "$NM_DISPATCH" << 'NMEOF'
#!/bin/bash
# Triggered by NetworkManager on any WiFi state change
touch /tmp/es-wifi-changed
NMEOF
        chmod +x "$NM_DISPATCH"
    fi

    for SERVICE in ssh smbd nmbd filebrowser; do
        DROP_DIR="/etc/systemd/system/${SERVICE}.service.d"
        DROP_FILE="$DROP_DIR/es-icon.conf"
        if systemctl list-unit-files "${SERVICE}.service" > /dev/null 2>&1; then
            if [ ! -f "$DROP_FILE" ]; then
                mkdir -p "$DROP_DIR"
                cat > "$DROP_FILE" << DROPIN
[Service]
ExecStartPost=/bin/sh -c 'touch /tmp/es-wifi-changed'
ExecStopPost=/bin/sh -c 'touch /tmp/es-wifi-changed'
DROPIN
            fi
        fi
    done
    systemctl daemon-reload 2>/dev/null

    UDEV_RULE="/etc/udev/rules.d/99-es-icons.rules"
    if [ ! -f "$UDEV_RULE" ]; then
        cat > "$UDEV_RULE" << 'UDEVEOF'
# WiFi: only on add/remove, not on "change" (wpa_supplicant scans fire too often)
SUBSYSTEM=="net", KERNEL=="wlan0", ACTION=="add",    RUN+="/bin/sh -c 'touch /tmp/es-wifi-changed'"
SUBSYSTEM=="net", KERNEL=="wlan0", ACTION=="remove", RUN+="/bin/sh -c 'touch /tmp/es-wifi-changed'"
# Bluetooth: device add/remove only
SUBSYSTEM=="bluetooth", ACTION=="add",    RUN+="/bin/sh -c 'touch /tmp/es-bt-changed'"
SUBSYSTEM=="bluetooth", ACTION=="remove", RUN+="/bin/sh -c 'touch /tmp/es-bt-changed'"
UDEVEOF
        udevadm control --reload-rules
    fi
}

# --- Suppression des optimisations  ---
remove_optimizations() {
    ES_LAUNCH="/usr/bin/emulationstation/emulationstation.sh"
    if [ -f "${ES_LAUNCH}.bak" ]; then
        cp "${ES_LAUNCH}.bak" "$ES_LAUNCH"
        rm -f "${ES_LAUNCH}.bak"
    fi

    # Arrêter et désactiver le daemon
    if systemctl list-unit-files | grep -q es-status-daemon.service; then
        systemctl stop es-status-daemon.service 2>/dev/null
        systemctl disable es-status-daemon.service 2>/dev/null
        rm -f /etc/systemd/system/es-status-daemon.service
        rm -f /usr/local/bin/es-status-daemon.sh
        systemctl daemon-reload
    fi

    # Supprimer le dispatcher NetworkManager
    NM_DISPATCH="/etc/NetworkManager/dispatcher.d/99-es-wifi-icon"
    if [ -f "$NM_DISPATCH" ]; then
        rm -f "$NM_DISPATCH"
    fi

    # Supprimer les drop-ins systemd
    for SERVICE in ssh smbd nmbd filebrowser; do
        DROP_FILE="/etc/systemd/system/${SERVICE}.service.d/es-icon.conf"
        if [ -f "$DROP_FILE" ]; then
            rm -f "$DROP_FILE"
            rmdir "/etc/systemd/system/${SERVICE}.service.d" 2>/dev/null
        fi
    done
    systemctl daemon-reload 2>/dev/null

    # Supprimer la règle udev
    UDEV_RULE="/etc/udev/rules.d/99-es-icons.rules"
    if [ -f "$UDEV_RULE" ]; then
        rm -f "$UDEV_RULE"
        udevadm control --reload-rules
    fi

    # Nettoyer les fichiers temporaires
    rm -f /tmp/es-wifi-state /tmp/es-bt-state /tmp/es-wifi-changed /tmp/es-bt-changed 2>/dev/null

    # Restaurer les réglages CPU/WiFi par défaut
    if grep -q "schedutil" "$ES_LAUNCH" 2>/dev/null; then
        sed -i '/echo schedutil/d' "$ES_LAUNCH"
        sed -i '/scaling_max_freq/d' "$ES_LAUNCH"
        sed -i '/power_save on/d' "$ES_LAUNCH"
    fi
    sed -i '/SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS/d' "$ES_LAUNCH" 2>/dev/null || true

    # Restaurer la fréquence CPU maximale disponible
    MAX_FREQ=$(cat /sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq 2>/dev/null)
    [ -n "$MAX_FREQ" ] && echo "$MAX_FREQ" | tee /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq > /dev/null 2>&1 || true

    sleep 1
}

# --- Installation ES-dArkOS ---
Install_dArkOS() {
    check_internet || return

    dialog --backtitle "$BACKTITLE" --title "Install ES-dArkOS" \
        --yesno "\nInstall ES-dArkOS on your R36S?\n\nThe device will reboot when done." 9 55 > "$CURR_TTY"
    [ $? -ne 0 ] && return

    (
        smooth_progress "Backing up original ES..." 0.04 0 10
        backup_es_if_needed

        smooth_progress "Downloading ES-dArkOS..." 0.06 11 45
        wget -q -O /tmp/es_tmp "$ES_DARKS_URL" 2>/dev/null

        smooth_progress "Applying permissions..." 0.03 46 55
        install -m 755 -o root -g root /tmp/es_tmp "$ES_INSTALL_PATH"
        rm -f /tmp/es_tmp

        smooth_progress "Downloading SVG icons..." 0.05 56 80
        download_svgs

        smooth_progress "Applying optimizations..." 0.05 81 100
        apply_optimizations
    ) | dialog --backtitle "$BACKTITLE" --title "Install ES-dArkOS" \
        --gauge "\nInstalling, please wait..." 8 60 0 > "$CURR_TTY"

    dialog --backtitle "$BACKTITLE" --title "Install ES-dArkOS" \
        --msgbox "\nES-dArkOS installed successfully!\n\nRebooting R36S..." 8 55 > "$CURR_TTY"

    reboot
}

# --- Installation ES-dArkOS4clone ---
Install_dArkOS4clone() {
    check_internet || return

    dialog --backtitle "$BACKTITLE" --title "Install ES-dArkOS4clone" \
        --yesno "\nInstall ES-dArkOS4clone on your R36S?\n\nThe device will reboot when done." 9 60 > "$CURR_TTY"
    [ $? -ne 0 ] && return

    (
        smooth_progress "Backing up original ES..." 0.04 0 10
        backup_es_if_needed

        smooth_progress "Downloading ES-dArkOS4clone ..." 0.06 11 45
        wget -q -O /tmp/es_tmp "$ES_DARKS4_URL" 2>/dev/null

        smooth_progress "Applying permissions..." 0.03 46 55
        install -m 755 -o root -g root /tmp/es_tmp "$ES_INSTALL_PATH"
        rm -f /tmp/es_tmp

        smooth_progress "Downloading SVG icons..." 0.05 56 80
        download_svgs

        smooth_progress "Applying optimizations..." 0.05 81 100
        apply_optimizations
    ) | dialog --backtitle "$BACKTITLE" --title "Install ES-dArkOS4clone" \
        --gauge "\nInstalling, please wait..." 8 60 0 > "$CURR_TTY"

    dialog --backtitle "$BACKTITLE" --title "Install ES-dArkOS4clone" \
        --msgbox "\nES-dArkOS4clone installed successfully!\n\nRebooting R36S..." 8 55 > "$CURR_TTY"

    reboot
}

# --- Restauration de l'ES original ---
Restore_ES() {
    if [ ! -f "$ES_BACKUP" ]; then
        dialog --backtitle "$BACKTITLE" --title "Restore" \
            --msgbox "\nNo backup found.\n\nPlease run an installation first\nto create an automatic backup." 10 55 > "$CURR_TTY"
        return
    fi

    dialog --backtitle "$BACKTITLE" --title "Restore" \
        --yesno "\nRestore the original EmulationStation?\n\nInstalled SVG icons will be removed.\nOptimizations will be undone.\nThe device will reboot when done." 10 55 > "$CURR_TTY"
    [ $? -ne 0 ] && return

    (
        smooth_progress "Removing optimizations..." 0.05 0 30
        remove_optimizations

        smooth_progress "Restoring original ES..." 0.05 31 60
        install -m 755 -o root -g root "$ES_BACKUP" "$ES_INSTALL_PATH"

        smooth_progress "Removing SVG icons..." 0.05 61 90
        remove_svgs

        smooth_progress "Finalizing..." 0.03 91 100
    ) | dialog --backtitle "$BACKTITLE" --title "Restore" \
        --gauge "\nRestoring, please wait..." 8 60 0 > "$CURR_TTY"

    dialog --backtitle "$BACKTITLE" --title "Restore" \
        --msgbox "\nOriginal ES restored successfully!\n\nRebooting R36S..." 8 55 > "$CURR_TTY"

    reboot
}

# --- Quitter ---
Exit_Script() {
    printf "\033c" > "$CURR_TTY"
    printf "\e[?25h" > "$CURR_TTY"
    pkill -f "gptokeyb" || true
    exit 0
}

# --- Menu Principal ---
Main_Menu() {
    while true; do
        if [ -f "$BACKUP_FLAG" ]; then
            BACKUP_STATUS="\Z2Backup found\Zn"
        else
            BACKUP_STATUS="\Z1No backup\Zn"
        fi

        selection=$(dialog --colors --backtitle "$BACKTITLE" --title " MAIN MENU " \
            --cancel-label "Exit" \
            --menu "\nBackup status: $BACKUP_STATUS\n\nSelect an option:" 16 60 4 \
            1 "Install ES-dArkOS" \
            2 "Install ES-dArkOS4clone" \
            3 "Restore original ES" \
            4 "Exit" 2>&1 > "$CURR_TTY")

        [ $? -ne 0 ] && Exit_Script

        case $selection in
            1) Install_dArkOS ;;
            2) Install_dArkOS4clone ;;
            3) Restore_ES ;;
            4) Exit_Script ;;
        esac
    done
}

# --- Mapping des touches ---
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
/opt/inttools/gptokeyb -1 "$(basename "$0")" -c "/opt/inttools/keys.gptk" > /dev/null 2>&1 &

trap Exit_Script EXIT

# --- Lancement ---
Main_Menu