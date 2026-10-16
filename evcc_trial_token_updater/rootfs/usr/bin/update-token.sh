#!/usr/bin/env bash

set -e

ADDON_SLUG=$(bashio::config 'addon_slug')

SUPERVISOR="http://supervisor"
TOKEN="${SUPERVISOR_TOKEN}"

echo "Lade aktuelles Trial-Token..."

TRIAL_TOKEN=$(
    curl -fsSL https://docs.evcc.io/de/sponsorship/ |
    grep -oE 'eyJ[A-Za-z0-9._-]+' |
    head -n1
)

if [ -z "$TRIAL_TOKEN" ]; then
    echo "Kein Trial-Token gefunden."
    exit 1
fi

echo "Lese aktuelle Add-on Konfiguration..."

CURRENT_CONFIG=$(
    curl -s \
      -H "Authorization: Bearer ${TOKEN}" \
      "${SUPERVISOR}/addons/${ADDON_SLUG}/options"
)

CURRENT_TOKEN=$(echo "$CURRENT_CONFIG" | jq -r '.data.sponsortoken // empty')

if [ "$CURRENT_TOKEN" = "$TRIAL_TOKEN" ]; then
    echo "Token unverändert."
    exit 0
fi

echo "Token geändert. Aktualisiere..."

NEW_OPTIONS=$(
    echo "$CURRENT_CONFIG" |
    jq --arg token "$TRIAL_TOKEN" '.data.sponsortoken=$token | .data'
)

curl -s \
  -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$NEW_OPTIONS" \
  "${SUPERVISOR}/addons/${ADDON_SLUG}/options"

echo "Starte EVCC neu..."

curl -s \
  -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  "${SUPERVISOR}/addons/${ADDON_SLUG}/restart"

echo "Fertig."
