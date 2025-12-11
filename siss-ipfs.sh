#!/bin/bash

# SISS - Secure IPFS Split-Key Storage
# https://github.com/votre-user/SISS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOADS_DIR="${SCRIPT_DIR}/uploads"
OUTPUTS_DIR="${SCRIPT_DIR}/outputs"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Aide
usage() {
    cat << EOF
Usage: ./siss-ipfs.sh <command> [arguments]

Commandes:
  upload <fichier> <nom>    Chiffre et upload un fichier sur IPFS
  read <nom>                Récupère, vérifie et déchiffre un projet
  list                      Liste les projets locaux
  help                      Affiche cette aide

Exemples:
  ./siss-ipfs.sh upload contrat.pdf audit-2025
  ./siss-ipfs.sh read audit-2025
  ./siss-ipfs.sh list
EOF
}

# Vérifie les dépendances système de base
check_dependencies() {
    local missing=()
    command -v openssl >/dev/null 2>&1 || missing+=("openssl")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Erreur: Outils système manquants: ${missing[*]}${NC}" >&2
        echo "Installez-les via votre gestionnaire de paquets (apt, brew...)" >&2
        exit 1
    fi
}

# Génère une clé AES-256 (32 bytes = 256 bits)
generate_aes_key() {
    openssl rand -hex 32
}

# Génère une paire de clés (RSA pour compatibilité)
generate_ed25519_keys() {
    local key_dir="$1"
    local private_key="${key_dir}/ed25519_private.pem"
    local public_key="${key_dir}/ed25519_public.pem"
    
    # Utilise RSA-2048 (plus compatible et fiable)
    openssl genrsa -out "${private_key}" 2048 2>/dev/null
    openssl rsa -in "${private_key}" -pubout -out "${public_key}" 2>/dev/null
    echo "${private_key}"
}

# Chiffre un fichier avec AES-256-CBC
encrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local key_hex="$3"
    
    # Chiffre avec AES-256-CBC
    # Utilise la clé hex comme mot de passe avec -pbkdf2 pour utiliser -salt correctement
    echo -n "${key_hex}" | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 10000 \
        -in "${input_file}" -out "${output_file}" \
        -pass stdin 2>/dev/null
}

# Déchiffre un fichier avec AES-256-CBC
decrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local key_hex="$3"
    
    # Déchiffre avec AES-256-CBC
    # Utilise la clé hex comme mot de passe avec -pbkdf2
    echo -n "${key_hex}" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -iter 10000 \
        -in "${input_file}" -out "${output_file}" \
        -pass stdin 2>/dev/null
}

# Signe un message avec RSA
sign_message() {
    local message="$1"
    local private_key="$2"
    
    # Utilise RSA avec SHA256 (compatible et fiable)
    echo -n "${message}" | openssl dgst -sha256 -sign "${private_key}" | base64 -w 0
}

# Vérifie une signature
verify_signature() {
    local message="$1"
    local signature_b64="$2"
    local public_key="$3"
    
    # Détecte le type de clé
    local key_type=$(openssl pkey -pubin -in "${public_key}" -noout -text 2>/dev/null | grep -i "ASN1 OID" | head -1)
    
    # Pour Ed25519, on utilise pkeyutl sans digest (EdDSA n'utilise pas de digest)
    if echo "${key_type}" | grep -qi "ED25519\|Ed25519"; then
        echo -n "${signature_b64}" | base64 -d | openssl pkeyutl -verify -pubin -inkey "${public_key}" \
            -rawin -sigfile /dev/stdin <(echo -n "${message}") 2>/dev/null
    else
        # Pour RSA (utilise digest)
        echo -n "${signature_b64}" | base64 -d > /tmp/sig.bin
        echo -n "${message}" | openssl dgst -sha256 -verify "${public_key}" -signature /tmp/sig.bin >/dev/null 2>&1
        local result=$?
        rm -f /tmp/sig.bin
        return $result
    fi
}

# Extrait la clé publique en base64
get_public_key_base64() {
    local public_key="$1"
    cat "${public_key}" | base64 -w 0
}

# Upload sur IPFS (via CLI)
upload_to_ipfs() {
    local file_path="$1"
    
    # Ajoute ~/.local/bin au PATH si IPFS y est installé
    if [ -f ~/.local/bin/ipfs ]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    # Vérifie si IPFS CLI est disponible
    if ! command -v ipfs >/dev/null 2>&1; then
        echo -e "${RED}Erreur: IPFS non installé${NC}" >&2
        echo -e "${YELLOW}Exécutez: ./install-ipfs.sh${NC}" >&2
        return 1
    fi
    
    # Vérifie si le daemon est accessible
    if ! ipfs id >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Démarrage du daemon IPFS...${NC}" >&2
        ipfs daemon >/dev/null 2>&1 &
        sleep 5
        
        if ! ipfs id >/dev/null 2>&1; then
            echo -e "${RED}Erreur: Impossible de démarrer le daemon IPFS${NC}" >&2
            echo -e "${YELLOW}Essayez manuellement: ipfs daemon &${NC}" >&2
            return 1
        fi
    fi
    
    # Upload sur IPFS
    local cid=$(ipfs add -q "${file_path}" 2>/dev/null | head -n 1)
    if [ -n "${cid}" ]; then
        echo "${cid}"
        return 0
    fi
    
    echo -e "${RED}Erreur: Échec de l'upload${NC}" >&2
    return 1
}

# Télécharge depuis IPFS
download_from_ipfs() {
    local cid="$1"
    local output_file="$2"
    
    # Ajoute ~/.local/bin au PATH si IPFS y est installé
    if [ -f ~/.local/bin/ipfs ]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    # Utilise IPFS CLI
    if command -v ipfs >/dev/null 2>&1; then
        # Vérifie si le daemon est accessible
        if ! ipfs id >/dev/null 2>&1; then
            echo -e "${YELLOW}[*] Démarrage du daemon IPFS...${NC}" >&2
            ipfs daemon >/dev/null 2>&1 &
            sleep 5
        fi
        
        if ipfs get "${cid}" -o "${output_file}" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # Fallback: utilise HTTP gateway (lecture seule, pas besoin d'API key)
    if command -v curl >/dev/null 2>&1; then
        local gateways=(
            "https://ipfs.io/ipfs/${cid}"
            "https://cloudflare-ipfs.com/ipfs/${cid}"
            "https://gateway.pinata.cloud/ipfs/${cid}"
        )
        
        for gateway in "${gateways[@]}"; do
            if curl -s -f -o "${output_file}" "${gateway}" 2>/dev/null; then
                return 0
            fi
        done
    fi
    
    return 1
}

# Génère les gateways IPFS
generate_gateways() {
    local cid="$1"
    cat << EOF
    "https://ipfs.io/ipfs/${cid}",
    "https://cloudflare-ipfs.com/ipfs/${cid}",
    "https://gateway.pinata.cloud/ipfs/${cid}"
EOF
}

# Commande upload
cmd_upload() {
    local file_path="$1"
    local upload_name="$2"
    
    if [ ! -f "${file_path}" ]; then
        echo -e "${RED}Erreur: Fichier introuvable: ${file_path}${NC}" >&2
        exit 1
    fi
    
    local upload_dir="${UPLOADS_DIR}/${upload_name}"
    mkdir -p "${upload_dir}"
    
    echo -e "${GREEN}[*] Chiffrement du fichier...${NC}"
    
    # Génère la clé AES
    local aes_key=$(generate_aes_key)
    echo "${aes_key}" > "${upload_dir}/secret.key"
    chmod 600 "${upload_dir}/secret.key"
    
    # Chiffre le fichier
    local encrypted_file=$(mktemp)
    encrypt_file "${file_path}" "${encrypted_file}" "${aes_key}"
    
    echo -e "${GREEN}[*] Upload sur IPFS...${NC}"
    
    # Upload sur IPFS
    local cid=$(upload_to_ipfs "${encrypted_file}")
    
    if [ -z "${cid}" ]; then
        echo -e "${RED}Erreur: Échec de l'upload sur IPFS${NC}" >&2
        echo -e "${YELLOW}Solutions possibles :${NC}" >&2
        echo -e "${YELLOW}  1. Installez IPFS CLI et lancez 'ipfs daemon'${NC}" >&2
        echo -e "${YELLOW}  2. Vérifiez votre connexion Internet${NC}" >&2
        echo -e "${YELLOW}  3. Les services IPFS publics peuvent être temporairement indisponibles${NC}" >&2
        rm -f "${encrypted_file}"
        exit 1
    fi
    
    echo -e "${GREEN}[*] CID: ${cid}${NC}"
    
    # Génère les clés de signature
    echo -e "${GREEN}[*] Génération des clés de signature...${NC}"
    local private_key=$(generate_ed25519_keys "${upload_dir}")
    local public_key="${upload_dir}/ed25519_public.pem"
    
    if [ ! -f "${public_key}" ]; then
        # Si la clé publique n'a pas été générée, on l'extrait
        openssl pkey -in "${private_key}" -pubout -out "${public_key}" 2>/dev/null
    fi
    
    # Algorithme de signature (RSA-SHA256)
    local sig_algo="rsa-sha256"
    
    # Signe le CID (AVANT de supprimer la clé privée)
    local signature=$(sign_message "${cid}" "${private_key}")
    local public_key_b64=$(get_public_key_base64 "${public_key}")
    
    # Algorithme utilisé (toujours CBC pour compatibilité)
    local enc_algo="aes-256-cbc"
    
    # Crée le manifest.json
    local manifest_file="${upload_dir}/manifest.json"
    local created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local gateways_json=$(generate_gateways "${cid}" | tr '\n' ' ' | sed 's/,$//')
    
    cat > "${manifest_file}" << EOF
{
  "version": "1.0",
  "cid": "${cid}",
  "gateways": [
$(generate_gateways "${cid}" | sed 's/^/    /')
  ],
  "encryption": {
    "algo": "${enc_algo}"
  },
  "signature": {
    "algo": "${sig_algo}",
    "public_key": "${public_key_b64}",
    "value": "${signature}"
  },
  "created_at": "${created_at}",
  "original_filename": "$(basename "${file_path}")"
}
EOF
    
    # Nettoie
    rm -f "${encrypted_file}"
    rm -f "${private_key}"  # On ne garde que la clé publique dans le manifest
    
    echo -e "${GREEN}[✓] Upload terminé avec succès!${NC}"
    echo -e "${GREEN}    Dossier: ${upload_dir}${NC}"
    echo -e "${YELLOW}    ⚠️  Conservez secret.key en sécurité!${NC}"
}

# Commande read
cmd_read() {
    local upload_name="$1"
    local upload_dir="${UPLOADS_DIR}/${upload_name}"
    
    if [ ! -d "${upload_dir}" ]; then
        echo -e "${RED}Erreur: Upload introuvable: ${upload_name}${NC}" >&2
        exit 1
    fi
    
    local manifest_file="${upload_dir}/manifest.json"
    local secret_key_file="${upload_dir}/secret.key"
    
    if [ ! -f "${manifest_file}" ]; then
        echo -e "${RED}Erreur: manifest.json introuvable${NC}" >&2
        exit 1
    fi
    
    if [ ! -f "${secret_key_file}" ]; then
        echo -e "${RED}Erreur: secret.key introuvable${NC}" >&2
        exit 1
    fi
    
    # Parse le manifest.json (simple extraction avec grep/sed)
    local cid=$(grep -o '"cid":\s*"[^"]*"' "${manifest_file}" | cut -d'"' -f4)
    local sig_algo=$(grep -o '"algo":\s*"[^"]*"' "${manifest_file}" | head -n 2 | tail -n 1 | cut -d'"' -f4)
    local public_key_b64=$(grep -o '"public_key":\s*"[^"]*"' "${manifest_file}" | cut -d'"' -f4)
    local signature=$(grep -o '"value":\s*"[^"]*"' "${manifest_file}" | cut -d'"' -f4)
    local original_filename=$(grep -o '"original_filename":\s*"[^"]*"' "${manifest_file}" | cut -d'"' -f4)
    local enc_algo=$(grep -o '"algo":\s*"[^"]*"' "${manifest_file}" | head -n 1 | cut -d'"' -f4)
    
    if [ -z "${cid}" ]; then
        echo -e "${RED}Erreur: CID introuvable dans manifest.json${NC}" >&2
        exit 1
    fi
    
    echo -e "${GREEN}[*] CID: ${cid}${NC}"
    echo -e "${GREEN}[*] Téléchargement depuis IPFS...${NC}"
    
    # Télécharge depuis IPFS
    local encrypted_file=$(mktemp)
    if ! download_from_ipfs "${cid}" "${encrypted_file}"; then
        echo -e "${RED}Erreur: Échec du téléchargement depuis IPFS${NC}" >&2
        rm -f "${encrypted_file}"
        exit 1
    fi
    
    echo -e "${GREEN}[*] Vérification de la signature...${NC}"
    
    # Vérifie la signature
    local public_key_file=$(mktemp)
    echo -n "${public_key_b64}" | base64 -d > "${public_key_file}"
    
    if ! verify_signature "${cid}" "${signature}" "${public_key_file}"; then
        echo -e "${RED}Erreur: Signature invalide! Le fichier peut être corrompu.${NC}" >&2
        rm -f "${encrypted_file}" "${public_key_file}"
        exit 1
    fi
    
    echo -e "${GREEN}[✓] Signature valide${NC}"
    rm -f "${public_key_file}"
    
    echo -e "${GREEN}[*] Déchiffrement...${NC}"
    
    # Lit la clé secrète
    local aes_key=$(cat "${secret_key_file}")
    
    # Déchiffre
    local output_dir="${OUTPUTS_DIR}/${upload_name}"
    mkdir -p "${output_dir}"
    
    local output_filename="${original_filename:-output.bin}"
    local output_file="${output_dir}/${output_filename}"
    
    decrypt_file "${encrypted_file}" "${output_file}" "${aes_key}"
    
    rm -f "${encrypted_file}"
    
    echo -e "${GREEN}[✓] Fichier déchiffré avec succès!${NC}"
    echo -e "${GREEN}    Fichier: ${output_file}${NC}"
}

# Commande list
cmd_list() {
    if [ ! -d "${UPLOADS_DIR}" ] || [ -z "$(ls -A "${UPLOADS_DIR}" 2>/dev/null)" ]; then
        echo "Aucun upload disponible."
        return 0
    fi
    
    echo "Uploads disponibles:"
    echo ""
    for upload_dir in "${UPLOADS_DIR}"/*; do
        if [ -d "${upload_dir}" ]; then
            local upload_name=$(basename "${upload_dir}")
            local manifest_file="${upload_dir}/manifest.json"
            
            if [ -f "${manifest_file}" ]; then
                local cid=$(grep -o '"cid":\s*"[^"]*"' "${manifest_file}" | cut -d'"' -f4)
                local created_at=$(grep -o '"created_at":\s*"[^"]*"' "${manifest_file}" | cut -d'"' -f4)
                local filename=$(grep -o '"original_filename":\s*"[^"]*"' "${manifest_file}" | cut -d'"' -f4)
                
                echo -e "${GREEN}  ${upload_name}${NC}"
                echo "    CID: ${cid}"
                echo "    Fichier: ${filename}"
                echo "    Créé: ${created_at}"
                echo ""
            fi
        fi
    done
}

# Main
main() {
    check_dependencies
    
    case "${1:-}" in
        upload)
            if [ $# -ne 3 ]; then
                echo -e "${RED}Erreur: Usage: $0 upload <file_path> <upload_name>${NC}" >&2
                exit 1
            fi
            cmd_upload "$2" "$3"
            ;;
        read)
            if [ $# -ne 2 ]; then
                echo -e "${RED}Erreur: Usage: $0 read <upload_name>${NC}" >&2
                exit 1
            fi
            cmd_read "$2"
            ;;
        list)
            cmd_list
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo -e "${RED}Erreur: Commande inconnue: ${1:-}${NC}" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"

