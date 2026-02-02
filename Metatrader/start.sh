#!/bin/bash

# Configuration variables
# NEU: Instanz-Nummer (1,2,3,...) -> installiert nach "C:\Program Files\MetaTrader 5_<n>"
MT5_INSTANCE="${MT5_INSTANCE:-1}"

MT5_DEFAULT_DIR="/config/.wine/drive_c/Program Files/MetaTrader 5"
MT5_DEFAULT_EXE="${MT5_DEFAULT_DIR}/terminal64.exe"

# NEU: Instanz-spezifischer Installationspfad
MT5_INSTALL_DIR="/config/.wine/drive_c/Program Files/MetaTrader 5_${MT5_INSTANCE}"
mt5file="${MT5_INSTALL_DIR}/terminal64.exe"

WINEPREFIX='/config/.wine'
WINEDEBUG='-all'
wine_executable="wine"
metatrader_version="5.0.45"
mt5server_port="8001"
MT5_CMD_OPTIONS="${MT5_CMD_OPTIONS:-}"
mono_url="https://dl.winehq.org/wine/wine-mono/10.3.0/wine-mono-10.3.0-x86.msi"
python_url="https://www.python.org/ftp/python/3.13.8/python-3.13.8-amd64.exe"
mt5setup_url="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"

# NEU: Projekt-Volume Konfiguration
PROJECT_DIR="/app"
REQUIREMENTS_FILE="$PROJECT_DIR/requirements.txt"
REQUIREMENTS_INSTALLED_MARKER="$WINEPREFIX/.custom_requirements_installed"

# NEU: Installer Cache-Pfad (nur 1x Download)
MT5_SETUP_LOCAL="/config/.wine/drive_c/mt5setup.exe"

# Function to display a graphical message
show_message() {
    echo $1
}

# Function to check if a dependency is installed
check_dependency() {
    if ! command -v $1 &> /dev/null; then
        echo "$1 is not installed. Please install it to continue."
        exit 1
    fi
}

# Function to check if a Python package is installed
is_python_package_installed() {
    python3 -c "import pkg_resources; exit(not pkg_resources.require('$1'))" 2>/dev/null
    return $?
}

# Function to check if a Python package is installed in Wine
is_wine_python_package_installed() {
    $wine_executable python -c "import pkg_resources; exit(not pkg_resources.require('$1'))" 2>/dev/null
    return $?
}

# Check for necessary dependencies
check_dependency "curl"
check_dependency "$wine_executable"

# Funktion für Custom Requirements Installation
install_custom_requirements() {
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        show_message "[7/8] No requirements.txt found in $PROJECT_DIR - skipping custom packages"
        return 0
    fi

    if [ -f "$REQUIREMENTS_INSTALLED_MARKER" ]; then
        show_message "[7/8] Custom requirements already installed (use ENV SKIP_REQUIREMENTS=no to force reinstall)"
        return 0
    fi

    show_message "[7/8] Installing custom requirements from $REQUIREMENTS_FILE..."
    
    # Upgrade pip first
    $wine_executable python -m pip install --upgrade --no-cache-dir pip
    
    # Install requirements from mounted volume
    $wine_executable python -m pip install --no-cache-dir -r "$REQUIREMENTS_FILE"
    
    if [ $? -eq 0 ]; then
        touch "$REQUIREMENTS_INSTALLED_MARKER"
        show_message "[7/8] Custom requirements installed successfully!"
        # List installed packages for verification
        $wine_executable python -m pip list | head -10
    else
        show_message "[7/8] ERROR: Custom requirements installation failed!"
        exit 1
    fi
}

# Install Mono if not present
if [ ! -e "/config/.wine/drive_c/windows/mono" ]; then
    show_message "[1/7] Downloading and installing Mono..."
    curl -o /config/.wine/drive_c/mono.msi $mono_url
    WINEDLLOVERRIDES=mscoree=d $wine_executable msiexec /i /config/.wine/drive_c/mono.msi /qn
    rm /config/.wine/drive_c/mono.msi
    show_message "[1/7] Mono installed."
else
    show_message "[1/7] Mono is already installed."
fi

# Check if MetaTrader 5 is already installed (Default install)
if [ -e "$MT5_DEFAULT_EXE" ]; then
    show_message "[2/7] File $MT5_DEFAULT_EXE already exists."
else
    show_message "[2/7] File $MT5_DEFAULT_EXE is not installed. Installing..."

    # Set Windows 10 mode in Wine and download and install MT5
    $wine_executable reg add "HKEY_CURRENT_USER\\Software\\Wine" /v Version /t REG_SZ /d "win10" /f
    show_message "[3/7] Downloading MT5 installer..."
    curl -o /config/.wine/drive_c/mt5setup.exe $mt5setup_url
    show_message "[3/7] Installing MetaTrader 5..."
    $wine_executable "/config/.wine/drive_c/mt5setup.exe" "/auto" &
    wait
    rm -f /config/.wine/drive_c/mt5setup.exe
fi

# NEU: Copy default install to instance folders (MetaTrader 5_1, _2, ...)
if [ "${AUTOSTART_ALL_MT5_INSTANCES:-0}" = "1" ]; then
    MT5_INSTANCES="${MT5_INSTANCES:-1}"

    for i in $(seq 1 "$MT5_INSTANCES"); do
        TARGET_DIR="/config/.wine/drive_c/Program Files/MetaTrader 5_${i}"
        TARGET_EXE="${TARGET_DIR}/terminal64.exe"

        if [ -e "$TARGET_EXE" ]; then
            show_message "[2/7] File $TARGET_EXE already exists."
        else
            show_message "[2/7] Creating MT5 instance $i by copying default installation..."

            # Zielordner neu erstellen
            rm -rf "$TARGET_DIR"
            cp -a "$MT5_DEFAULT_DIR" "$TARGET_DIR"

            # Optional: Icon-Datei pro Instanz ablegen (falls gemountet vorhanden)
            # Lege z.B. unter /app/icons/mt5_1.ico, mt5_2.ico, ... ab
            ICON_SRC="/app/icons/mt5_${i}.ico"
            if [ -f "$ICON_SRC" ]; then
                cp -a "$ICON_SRC" "${TARGET_DIR}/instance.ico"
                show_message "[2/7] Copied icon for instance $i to ${TARGET_DIR}/instance.ico"
            fi
        fi
    done
else
    # Single instance mode: map mt5file to instance folder by copying once if missing
    if [ -e "$mt5file" ]; then
        show_message "[2/7] File $mt5file already exists."
    else
        show_message "[2/7] Creating MT5 instance $MT5_INSTANCE by copying default installation..."
        rm -rf "$MT5_INSTALL_DIR"
        cp -a "$MT5_DEFAULT_DIR" "$MT5_INSTALL_DIR"
    fi
fi


# Install Python in Wine if not present
if ! $wine_executable python --version 2>/dev/null; then
    show_message "[5/7] Installing Python in Wine..."
    curl -L $python_url -o /tmp/python-installer.exe
    $wine_executable /tmp/python-installer.exe /quiet InstallAllUsers=1 PrependPath=1
    rm /tmp/python-installer.exe
    show_message "[5/7] Python installed in Wine."
else
    show_message "[5/7] Python is already installed in Wine."
fi

# Upgrade pip and install required packages
show_message "[6/7] Installing Python libraries"
$wine_executable python -m pip install --upgrade --no-cache-dir pip

# ─────────────────────────────────────────────────────────────
# 7. NEU: Install custom requirements from /app volume
# ─────────────────────────────────────────────────────────────
# Skip if SKIP_REQUIREMENTS=1 environment variable is set
if [ "${SKIP_REQUIREMENTS:-0}" != "1" ]; then
    install_custom_requirements
else
    show_message "[7/8] Custom requirements skipped (SKIP_REQUIREMENTS=1)"
fi
