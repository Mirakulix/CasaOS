#!/bin/bash

# 1. Homebrew und Docker Desktop für Mac installieren (falls nicht vorhanden)
echo "Prüfe, ob Homebrew installiert ist..."
if ! command -v brew &> /dev/null; then
    echo "Homebrew wird installiert..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Homebrew-Pfad zur Shell hinzufügen (falls nötig)
    if [[ $(uname -m) == 'arm64' ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "Homebrew ist bereits installiert."
fi

# Docker Desktop für Mac installieren
echo "Prüfe, ob Docker installiert ist..."
if ! command -v docker &> /dev/null; then
    echo "Docker Desktop wird installiert. Bitte lade es von https://www.docker.com/products/docker-desktop/ herunter und installiere es."
    echo "Nach der Installation drücke eine Taste, um fortzufahren..."
    read -n 1
else
    echo "Docker ist bereits installiert."
fi

# 2. Docker-Container mit CasaOS erstellen
docker run -d --name casaos \
  -e PUID=1000 \
  -e PGID=1000 \
  -p 80:80 \
  -p 443:443 \
  --restart=always \
  -v ~/casaos-data:/DATA \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --privileged \
  icasaos/casaos:latest

# 3. Überprüfen, ob der Container läuft
docker ps | grep casaos

# 4. Im Browser testen
echo "Öffne im Browser: http://localhost"

# 5. Optional: mDNS für lokalen Netzwerkzugriff einrichten
brew install avahi
sudo brew services start avahi

# Erstelle eine Konfigurationsdatei für den Service
cat > ~/casaos.service << EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">CasaOS auf %h</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
    <txt-record>path=/</txt-record>
  </service>
</service-group>
EOF

# Kopiere die Konfigurationsdatei an den richtigen Ort
sudo cp ~/casaos.service /usr/local/etc/avahi/services/

# Starte den Avahi-Daemon neu
sudo brew services restart avahi

echo "CasaOS sollte jetzt unter http://casaos.local im Netzwerk erreichbar sein"