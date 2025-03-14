#!/bin/bash

# 1. Linux-Distribution installieren (Ubuntu Server 24.04 LTS empfohlen)
# Lade Ubuntu Server 24.04 LTS von https://ubuntu.com/download/server herunter
# Installiere es auf deinem alten PC mit minimalen Einstellungen

# 2. Dieses Skript für frische Ubuntu 24.04 Installation mit minimalen Paketen

# Prüfen, ob das Skript als root oder mit sudo ausgeführt wird
if [ "$EUID" -ne 0 ]; then
  echo "Bitte führe dieses Skript als root oder mit sudo aus."
  exit 1
fi

echo "==== CasaOS Setup auf frischer Ubuntu 24.04 Installation ===="
echo "Dieses Skript installiert alle notwendigen Abhängigkeiten und richtet CasaOS ein."
echo ""

# Prüfe Ubuntu-Version
if grep -q "Ubuntu" /etc/os-release; then
  echo "✅ Ubuntu-System erkannt"
  UBUNTU_VERSION=$(lsb_release -rs)
  echo "   Version: $UBUNTU_VERSION"
else
  echo "⚠️ Dieses Skript ist für Ubuntu-Systeme konzipiert. Fortfahren könnte zu Problemen führen."
  read -p "Trotzdem fortfahren? (j/n): " CONTINUE
  if [[ "$CONTINUE" != "j" ]]; then
    exit 1
  fi
fi

echo ""
echo "1️⃣ Grundlegende Abhängigkeiten werden installiert..."
# Notwendige Basis-Pakete
apt update
apt install -y \
  curl \
  wget \
  git \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release \
  software-properties-common \
  cron \
  net-tools \
  ufw \
  sudo

echo ""
echo "2️⃣ System wird aktualisiert..."
apt upgrade -y

echo ""
echo "3️⃣ Docker wird installiert..."
# Bestehende Docker-Pakete entfernen (falls vorhanden)
apt remove -y docker docker-engine docker.io containerd runc || true

# Docker-Repository hinzufügen
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Docker installieren
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker-Dienst starten
systemctl enable --now docker

# Prüfen, ob Docker funktioniert
if docker --version && systemctl is-active --quiet docker; then
  echo "✅ Docker erfolgreich installiert und aktiv: $(docker --version)"
else
  echo "❌ Problem bei der Docker-Installation"
  exit 1
fi

# 4. CasaOS installieren
curl -fsSL https://get.casaos.io | sudo bash

# 5. Netzwerktools und Avahi für mDNS (casaos.local) einrichten
echo ""
echo "5️⃣ Netzwerk-Tools und mDNS werden eingerichtet..."
sudo apt install -y \
  avahi-daemon \
  libnss-mdns \
  network-manager \
  dnsmasq-base

# 6. Konfiguration von Avahi
sudo tee /etc/avahi/services/casaos.service > /dev/null << EOF
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

# 7. Avahi neu starten
sudo systemctl restart avahi-daemon

# 8. Überwachungs-Skript erstellen, um CasaOS am Laufen zu halten
sudo tee /usr/local/bin/check-casaos.sh > /dev/null << 'EOF'
#!/bin/bash

# Überprüfen, ob CasaOS läuft
if ! systemctl is-active --quiet casaos.service; then
  # Wenn nicht, starte es neu
  systemctl restart casaos.service
  echo "$(date): CasaOS wurde neu gestartet" >> /var/log/casaos-watchdog.log
fi
EOF

# 9. Skript ausführbar machen
sudo chmod +x /usr/local/bin/check-casaos.sh

# 10. Cron-Job einrichten, der das Skript regelmäßig ausführt
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/check-casaos.sh") | crontab -

# 11. Einrichten, dass CasaOS beim Systemstart automatisch startet
sudo systemctl enable casaos.service

# 12. Firewall einrichten
echo ""
echo "12️⃣ Firewall wird konfiguriert..."
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw allow 5000/tcp  # CasaOS API Port
sudo ufw allow 5001/tcp  # CasaOS UI Port
sudo ufw allow mdns      # mDNS/Avahi

# Firewall aktivieren, falls noch nicht aktiv
sudo ufw --force enable

# 13. Abschließende Prüfungen
echo ""
echo "13️⃣ Abschließende Prüfungen werden durchgeführt..."

# Prüfen, ob CasaOS läuft
if systemctl is-active --quiet casaos.service; then
  echo "✅ CasaOS läuft"
else
  echo "⚠️ CasaOS scheint nicht zu laufen. Versuche es zu starten..."
  sudo systemctl start casaos.service
  sleep 5
  if systemctl is-active --quiet casaos.service; then
    echo "✅ CasaOS wurde erfolgreich gestartet"
  else
    echo "❌ Es gibt Probleme beim Starten von CasaOS"
  fi
fi

# Prüfen, ob Avahi läuft
if systemctl is-active --quiet avahi-daemon.service; then
  echo "✅ Avahi-Dienst läuft (für mDNS/casaos.local)"
else
  echo "❌ Avahi-Dienst läuft nicht"
  sudo systemctl start avahi-daemon.service
fi

echo ""
echo "==== Installation abgeschlossen ===="
echo "CasaOS ist jetzt installiert und sollte unter http://casaos.local im Netzwerk erreichbar sein"
echo "Ein Überwachungs-Skript überprüft alle 5 Minuten, ob CasaOS läuft und startet es bei Bedarf neu"
echo ""
echo "Netzwerk-Informationen:"
ip -4 addr show | grep inet
echo ""
echo "Wenn casaos.local nicht funktioniert, versuche die IP-Adresse oben zu verwenden"