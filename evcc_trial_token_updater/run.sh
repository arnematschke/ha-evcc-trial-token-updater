#!/command/with-contenv bash
set -uo pipefail

echo "=========================================="
echo " EVCC Token Diagnose"
echo "=========================================="

CONFIG_FILE="/addon_configs/49686a9f_evcc/evcc.yaml"

# EVCC-App über die Supervisor-API finden
if [ -z "${SUPERVISOR_TOKEN:-}" ]; then
    echo "FEHLER: SUPERVISOR_TOKEN ist nicht verfügbar."
    exit 1
fi

ADDONS_JSON=$(curl -fsS \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    http://supervisor/addons) || {
    echo "FEHLER: Supervisor-API nicht erreichbar."
    exit 1
}

EVCC_SLUG=$(echo "$ADDONS_JSON" | jq -r '
    [.data.addons[]?
     | select(
         ((.slug // "") | ascii_downcase | contains("evcc"))
         or
         ((.name // "") | ascii_downcase | contains("evcc"))
       )]
    | first | .slug // empty
')

if [ -z "$EVCC_SLUG" ]; then
    echo "FEHLER: EVCC-App wurde nicht gefunden."
    exit 1
fi

echo "EVCC-App-Slug: $EVCC_SLUG"

# Konfiguration aus den EVCC-App-Einstellungen lesen
INFO_JSON=$(curl -fsS \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    "http://supervisor/addons/${EVCC_SLUG}/info") || {
    echo "FEHLER: EVCC-Einstellungen konnten nicht gelesen werden."
    exit 1
}

CONFIG_VALUE=$(echo "$INFO_JSON" | jq -r '
    .data.options.config_file
    // .data.config_file
    // empty
')

echo "EVCC config_file: ${CONFIG_VALUE:-NICHT AUSLESBAR}"

# Vorhandensein und maskierten Wert des Tokens prüfen
if [ ! -r "$CONFIG_FILE" ]; then
    echo "FEHLER: Datei nicht lesbar: $CONFIG_FILE"
    exit 1
fi

TOKEN=$(grep -m1 -E \
    '^[[:space:]]*sponsortoken[[:space:]]*:' \
    "$CONFIG_FILE" |
    sed -E \
    's/^[[:space:]]*sponsortoken[[:space:]]*:[[:space:]]*//; s/^["'\'']?//; s/["'\'']?$//')

if [ -z "$TOKEN" ]; then
    echo "Sponsor-Token: NICHT GEFUNDEN oder LEER"
else
    TOKEN_LENGTH=${#TOKEN}
    if [ "$TOKEN_LENGTH" -gt 8 ]; then
        echo "Sponsor-Token: ${TOKEN:0:4}****${TOKEN: -4}"
    else
        echo "Sponsor-Token: vorhanden (Wert maskiert)"
    fi
    echo "Token-Länge: $TOKEN_LENGTH Zeichen"
fi

echo "Diagnose abgeschlossen."
