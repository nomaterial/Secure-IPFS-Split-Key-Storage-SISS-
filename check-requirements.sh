#!/bin/bash

# Script de vérification des dépendances SISS

echo "=== Vérification des dépendances SISS ==="
echo ""

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Compteurs
REQUIRED_OK=0
REQUIRED_TOTAL=1
OPTIONAL_OK=0
OPTIONAL_TOTAL=2

# OpenSSL (obligatoire)
echo -n "OpenSSL: "
if command -v openssl >/dev/null 2>&1; then
    VERSION=$(openssl version 2>/dev/null | head -1)
    echo -e "${GREEN}✅ Installé${NC} ($VERSION)"
    REQUIRED_OK=$((REQUIRED_OK + 1))
else
    echo -e "${RED}❌ Manquant${NC}"
fi

echo ""

# IPFS CLI (Requis pour SISS)
echo -n "IPFS CLI: "

# Ajoute ~/.local/bin au PATH pour la vérification
export PATH="$HOME/.local/bin:$PATH"

if command -v ipfs >/dev/null 2>&1; then
    VERSION=$(ipfs version 2>/dev/null | head -1)
    echo -e "${GREEN}✅ Installé${NC} ($VERSION)"
    REQUIRED_OK=$((REQUIRED_OK + 1))
else
    echo -e "${YELLOW}⚠️  Non détecté${NC}"
    echo -e "   Lancez ${YELLOW}./install-ipfs.sh${NC} pour l'installer automatiquement."
fi

# curl (Requis pour l'installation auto)
echo -n "curl: "
if command -v curl >/dev/null 2>&1; then
    VERSION=$(curl --version 2>/dev/null | head -1 | cut -d' ' -f1-2)
    echo -e "${GREEN}✅ Installé${NC} ($VERSION)"
    REQUIRED_OK=$((REQUIRED_OK + 1))
else
    echo -e "${RED}❌ Manquant${NC} (Requis pour télécharger IPFS)"
fi

echo ""
echo "=== Résultat ==="

# Vérification finale (OpenSSL + curl + IPFS ou prêt à installer)
if [ $REQUIRED_OK -ge 3 ]; then
    echo -e "${GREEN}✅ Tout est prêt !${NC}"
    exit 0
elif command -v openssl >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Prérequis système OK.${NC}"
    echo -e "   Il ne manque plus qu'IPFS : Lancez ${GREEN}./install-ipfs.sh${NC}"
    exit 0
else
    echo -e "${RED}❌ Des outils système manquent (OpenSSL ou curl).${NC}"
    exit 1
fi

