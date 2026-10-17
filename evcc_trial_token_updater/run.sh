
#!/command/with-contenv bash
set -uo pipefail

DOC_URL="https://docs.evcc.io/de/sponsorship/"
CONFIG_FILE="/addon_configs/49686a9f_evcc/evcc.yaml"

mask_token() {
    local token="$1"
    if [ "${#token}" -gt 8 ]; then
        printf '%s****%s' "${token:0:4}" "${token: -4}"
    else
        printf '[maskiert]'
    fi
}

echo "=========================================="
echo " EVCC Trial Token Diagnose"
echo "=========================================="

# Aktuellen Token aus der lokalen Konfiguration lesen
FILE_TOKEN=""
if [ -r "$CONFIG_FILE" ]; then
    FILE_TOKEN=$(sed -nE \
        's/^[[:space:]]*sponsortoken:[[:space:]]*["'\'']?([^"'\'']+).*$/\1/p' \
        "$CONFIG_FILE" | sed -n '1p')

    if [ -n "$FILE_TOKEN" ]; then
        echo "Lokaler Token: $(mask_token "$FILE_TOKEN")"
        echo "Lokale Token-Länge: ${#FILE_TOKEN}"
    else
        echo "Lokaler Token: nicht gefunden oder leer"
    fi
else
    echo "FEHLER: Konfigurationsdatei nicht lesbar"
    exit 1
fi

# Aktuellen Test-Token aus der offiziellen Dokumentation abrufen
echo "Rufe offizielle EVCC-Dokumentation ab ..."

PAGE=$(curl -fsSL --max-time 30 "$DOC_URL") || {
    echo "FEHLER: Dokumentation konnte nicht abgerufen werden"
    exit 1
}

TRIAL_TOKEN=$(printf '%s' "$PAGE" |
    grep -oE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' |
    sed -n '1p')

unset PAGE

if [ -z "$TRIAL_TOKEN" ]; then
    echo "FEHLER: Kein JWT-Testtoken auf der Dokumentationsseite erkannt"
    echo "Möglicherweise wurde das Format der Seite geändert."
    exit 1
fi

echo "Online-Testtoken: $(mask_token "$TRIAL_TOKEN")"
echo "Online-Token-Länge: ${#TRIAL_TOKEN}"

# Ablaufdatum aus dem JWT-Payload lesen
PAYLOAD=$(printf '%s' "$TRIAL_TOKEN" | cut -d. -f2 | tr '_-' '/+')

case $((${#PAYLOAD} % 4)) in
    2) PAYLOAD="${PAYLOAD}==" ;;
    3) PAYLOAD="${PAYLOAD}=" ;;
    1)
        echo "FEHLER: JWT-Payload ist ungültig"
        exit 1
        ;;
esac

TOKEN_EXP=$(printf '%s' "$PAYLOAD" |
    base64 -d 2>/dev/null |
    jq -r '.exp // empty') || true

if ! [[ "$TOKEN_EXP" =~ ^[0-9]+$ ]]; then
    echo "FEHLER: Ablaufdatum konnte nicht gelesen werden"
    exit 1
fi

NOW=$(date +%s)
echo "Token gültig bis: $(date -u -d "@$TOKEN_EXP" '+%Y-%m-%d %H:%M:%S UTC')"

if [ "$TOKEN_EXP" -le "$NOW" ]; then
    echo "WARNUNG: Online-Token ist bereits abgelaufen."
    echo "Keine Aktualisierung durchführen."
    exit 1
fi

echo "Ablaufprüfung: Token ist noch gültig."

if [ "$FILE_TOKEN" = "$TRIAL_TOKEN" ]; then
    echo "Vergleich: Lokaler und Online-Token sind identisch"
else
    echo "Vergleich: Lokaler und Online-Token unterscheiden sich"
fi

echo "Diagnose abgeschlossen. Keine Datei wurde verändert."
