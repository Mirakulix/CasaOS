#!/bin/bash

# Testskript für CentOS auf Ubuntu 24.04
# Dieses Skript installiert alle benötigten Abhängigkeiten und setzt einen CentOS-Container auf

echo "==== CentOS-Testumgebung auf Ubuntu 24.04 ====="
echo "Dieses Skript richtet eine CentOS-Testumgebung mit Podman ein"
echo ""

# Prüfen, ob das Skript als root oder mit sudo ausgeführt wird
if [ "$EUID" -ne 0 ]; then
  echo "Bitte führe dieses Skript als root oder mit sudo aus."
  exit 1
fi

# Prüfen, ob das System Ubuntu 24.04 ist
if grep -q "Ubuntu" /etc/os-release; then
    echo "✅ Ubuntu erkannt"
    UBUNTU_VERSION=$(lsb_release -rs)
    echo "   Version: $UBUNTU_VERSION"
    if [[ "$UBUNTU_VERSION" != "24.04" ]]; then
        echo "⚠️ Dieses Skript wurde für Ubuntu 24.04 entwickelt, aber Version $UBUNTU_VERSION erkannt."
        read -p "Trotzdem fortfahren? (j/n): " CONTINUE
        if [[ "$CONTINUE" != "j" ]]; then
            exit 1
        fi
    fi
else
    echo "❌ Kein Ubuntu-System erkannt"
    echo "Aktuelle Version:"
    cat /etc/os-release | grep "PRETTY_NAME"
    exit 1
fi

# Grundlegende Systempakete installieren
echo ""
echo "1️⃣ Grundlegende Systempakete werden installiert..."
apt update
apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    net-tools \
    netcat-openbsd \
    iptables \
    sudo \
    wget

# System aktualisieren
echo ""
echo "2️⃣ System wird aktualisiert..."
apt upgrade -y

# Podman installieren (statt Docker)
echo ""
echo "3️⃣ Podman wird installiert..."
apt install -y podman containernetworking-plugins uidmap slirp4netns fuse-overlayfs

# Prüfen, ob Podman erfolgreich installiert wurde
if podman --version; then
    echo "✅ Podman installiert: $(podman --version)"
else
    echo "❌ Podman-Installation fehlgeschlagen"
    exit 1
fi

# Konfiguration für rootless mode (falls Benutzer nicht root ist)
if [ "$SUDO_USER" ]; then
    echo "Konfiguriere Podman für Benutzer $SUDO_USER"
    su - $SUDO_USER -c "podman system migrate"
fi

# CentOS-Container starten
echo ""
echo "4️⃣ CentOS-Container wird erstellt..."
# CentOS Stream 9 verwenden (neueste stabile Version)
podman run -d --name centos-test -p 8080:80 quay.io/centos/centos:stream9
if [ $? -eq 0 ]; then
    echo "✅ CentOS-Container gestartet"
else
    echo "❌ Fehler beim Starten des CentOS-Containers"
    # Versuche es mit einem anderen Image
    echo "   Versuche alternatives Image..."
    podman run -d --name centos-test -p 8080:80 quay.io/centos-boot/centos:stream9
    if [ $? -eq 0 ]; then
        echo "✅ CentOS-Container mit alternativem Image gestartet"
    else
        echo "❌ Alle Versuche, einen CentOS-Container zu starten, sind fehlgeschlagen"
        exit 1
    fi
fi

# Überprüfen, ob der Container läuft
echo ""
echo "5️⃣ Container-Status wird überprüft..."
if podman ps | grep -q centos-test; then
    echo "✅ CentOS-Container läuft"
    CONTAINER_ID=$(podman ps | grep centos-test | awk '{print $1}')
    echo "   Container-ID: $CONTAINER_ID"
else
    echo "❌ CentOS-Container läuft nicht"
    podman ps -a
    exit 1
fi

# Grundlegende Tests im Container durchführen
echo ""
echo "6️⃣ Container wird getestet..."
echo "   CentOS-Version im Container:"
podman exec centos-test cat /etc/redhat-release || echo "❌ Konnte Version nicht auslesen"

# Grundlegende Tools im Container installieren
echo ""
echo "7️⃣ Grundlegende Tools werden im Container installiert..."
podman exec centos-test dnf -y install dnf-utils iputils hostname procps-ng less which
echo "   DNF Version im Container:"
podman exec centos-test dnf --version | head -n 1

# Webserver im Container installieren
echo ""
echo "8️⃣ Apache-Webserver wird im Container installiert..."
podman exec centos-test dnf install -y httpd
podman exec centos-test sh -c "echo '<html><body><h1>CentOS auf Ubuntu 24.04 Test erfolgreich!</h1><p>Container läuft und Apache ist installiert.</p></body></html>' > /var/www/html/index.html"

# Apache manuell starten (da systemctl im Container eingeschränkt ist)
echo "   Apache wird manuell gestartet..."
podman exec centos-test /usr/sbin/httpd -k start || echo "❌ Apache konnte nicht gestartet werden"

# Firewall für den Container konfigurieren
echo ""
echo "9️⃣ Firewall-Konfiguration im Container..."
podman exec centos-test dnf install -y firewalld || echo "❌ Firewalld konnte nicht installiert werden"
podman exec centos-test sh -c "firewall-cmd --permanent --add-service=http || true"
podman exec centos-test sh -c "firewall-cmd --reload || true"

# Port-Test für den Webserver
echo ""
echo "🔟 Port-Test für Webserver..."
if nc -z localhost 8080; then
    echo "✅ Webserver ist erreichbar auf Port 8080"
    echo "   Teste HTTP-Antwort..."
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080)
    if [ "$HTTP_RESPONSE" == "200" ]; then
        echo "✅ HTTP-Server antwortet mit Status 200 (OK)"
    else
        echo "⚠️ HTTP-Server antwortet mit Status $HTTP_RESPONSE"
    fi
else
    echo "❓ Webserver scheint nicht erreichbar zu sein auf Port 8080"
    echo "   (Eventuell wurde der Apache nicht korrekt gestartet)"
fi

# Informationen zur weiteren Nutzung
echo ""
echo "==== CentOS-Testumgebung eingerichtet ===="
echo ""
echo "🔹 Container-Management:"
echo "   - Stoppen:  podman stop centos-test"
echo "   - Starten:  podman start centos-test"
echo "   - Löschen:  podman rm -f centos-test"
echo ""
echo "🔹 In den Container einloggen:"
echo "   podman exec -it centos-test /bin/bash"
echo ""
echo "🔹 Unterschiede zu Ubuntu:"
echo "   - Paketmanager: dnf statt apt"
echo "   - Konfiguration: /etc/sysconfig/ statt /etc/default/"
echo "   - Dienste: systemctl wie in Ubuntu (aber im Container eingeschränkt)"
echo ""
echo "🔹 Webserver testen:"
echo "   - Browser: http://localhost:8080"
echo "   - Terminal: curl http://localhost:8080"
echo ""
echo "Viel Spaß beim Testen von CentOS auf Ubuntu 24.04!"
