#!/bin/bash

# Installation automatique d'IPFS pour SISS (sans sudo, sans API key)

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Installation IPFS pour SISS ==="
echo ""

# Ajoute ~/.local/bin au PATH si nécessaire
export PATH="$HOME/.local/bin:$PATH"

# Vérifie si IPFS est déjà installé
if command -v ipfs >/dev/null 2>&1; then
    IPFS_VERSION=$(ipfs version --number 2>/dev/null || echo "inconnue")
    echo -e "${GREEN}✓ IPFS déjà installé (${IPFS_VERSION})${NC}"
    
    # Vérifie si le repo est initialisé
    if [ ! -d ~/.ipfs ]; then
        echo "[*] Initialisation du repository..."
        ipfs init 2>/dev/null || true
    fi
    
    # Vérifie si le daemon est lancé
    if ipfs id >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Daemon IPFS actif${NC}"
        echo ""
        echo -e "${GREEN}✅ Prêt à utiliser !${NC}"
        exit 0
    else
        echo "[*] Démarrage du daemon IPFS..."
        ipfs daemon >/dev/null 2>&1 &
        sleep 5
        if ipfs id >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Daemon démarré${NC}"
            echo ""
            echo -e "${GREEN}✅ Prêt à utiliser !${NC}"
            exit 0
        fi
    fi
    exit 0
fi

# Installation automatique (sans sudo)
echo "[*] Installation d'IPFS..."

# Crée le répertoire si nécessaire
mkdir -p ~/.local/bin

# Détecte l'architecture
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ARCH="arm64"
fi

VERSION="v0.24.0"
URL="https://dist.ipfs.tech/kubo/${VERSION}/kubo_${VERSION}_${OS}-${ARCH}.tar.gz"

echo "[*] Téléchargement depuis ${URL}..."
cd /tmp
curl -L -f -o ipfs.tar.gz "$URL" || {
    echo -e "${RED}✗ Échec du téléchargement${NC}"
    exit 1
}

echo "[*] Extraction..."
tar -xzf ipfs.tar.gz 2>/dev/null || {
    echo -e "${RED}✗ Échec de l'extraction${NC}"
    exit 1
}

echo "[*] Installation dans ~/.local/bin/..."
cp kubo/ipfs ~/.local/bin/ipfs
chmod +x ~/.local/bin/ipfs
rm -rf kubo ipfs.tar.gz

# Vérifie l'installation
if [ ! -f ~/.local/bin/ipfs ]; then
    echo -e "${RED}✗ Échec de l'installation${NC}"
    exit 1
fi

echo -e "${GREEN}✓ IPFS installé dans ~/.local/bin/ipfs${NC}"

# Initialise le repository
echo "[*] Initialisation du repository IPFS..."
~/.local/bin/ipfs init 2>/dev/null || true

# Démarre le daemon
echo "[*] Démarrage du daemon IPFS..."
~/.local/bin/ipfs daemon >/dev/null 2>&1 &
sleep 5

# Vérifie que tout fonctionne
if ~/.local/bin/ipfs id >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Daemon IPFS démarré${NC}"
    echo ""
    echo -e "${GREEN}✅ Installation terminée !${NC}"
    echo ""
    echo "Note: Ajoutez cette ligne à votre ~/.bashrc ou ~/.zshrc :"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    echo "Ou utilisez directement :"
    echo "  ~/.local/bin/ipfs daemon &"
else
    echo -e "${YELLOW}⚠️  Le daemon peut prendre quelques secondes à démarrer${NC}"
    echo "Vérifiez avec: ~/.local/bin/ipfs id"
fi
