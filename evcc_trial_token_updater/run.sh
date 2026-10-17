#!/command/with-contenv bash
set -uo pipefail

DOC_URL="https://docs.evcc.io/de/sponsorship/"
CONFIG_FILE="/addon_configs/49686a9f_evcc/evcc.yaml"
EVCC_SLUG="49686a9f_evcc"
PENDING_FILE="/data/evcc_restart_pending"

get_interval() {
    local response value
    response=$(curl -fsS \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        http://supervisor/addons/self/options/config 2>/dev/null || true)

    value=$(printf '%s' "$response" |
        jq -r '.data.options.update_interval // .data.update_interval // 24' \
        2>/dev/null || echo 24)

    if [[ "$value" =~ ^[0-9]+$ ]] &&
       [ "$value" -ge 1 ] && [ "$value" -le 168 ]; then
        printf '%s' "$value"
    else
        printf '24'
    fi
}

evcc_is_started() {
    local response state

    response=$(curl -fsS --max-time 8 \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor/addons/${EVCC_SLUG}/info" 2>/dev/null) || return 1

    state=$(printf '%s' "$response" |
        jq -r '.data.state // empty' 2>/dev/null) || return 1

    [ "$state" = "started" ]
}

restart_evcc() {
    echo "Fordere Neustart der EVCC-App an ..."

    if curl -fsS --max-time 10 -o /dev/null -X POST \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        "http://supervisor/addons/${EVCC_SLUG}/restart"; then
        echo "EVCC-Neustart vom Supervisor bestätigt."
        rm -f "$PENDING_FILE"
        return 0
    fi

    echo "Keine rechtzeitige Antwort auf die Neustartanforderung."
    echo "Prüfe den tatsächlichen Status der EVCC-App ..."

    if evcc_is_started; then
        echo "EVCC läuft. Es wird kein weiterer Neustart angefordert."
        rm -f "$PENDING_FILE"
        return 0
    fi

    echo "WARNUNG: EVCC läuft nicht nachweislich."
    echo "Der Neustartvermerk bleibt für einen späteren Versuch bestehen."
    return 1
}

update_once() {
    echo
    echo "=========================================="
    echo " EVCC Token Aktualisierung"
    echo "=========================================="
    date -u '+Zeitpunkt: %Y-%m-%d %H:%M:%S UTC'

    if [ -f "$PENDING_FILE" ]; then
        echo "Ein vorheriger Neustart steht noch aus."
        restart_evcc || return 1
    fi

    if [ ! -r "$CONFIG_FILE" ] || [ ! -w "$CONFIG_FILE" ]; then
        echo "FEHLER: EVCC-Konfiguration nicht les- und schreibbar."
        return 1
    fi

    echo "Rufe offizielle EVCC-Dokumentation ab ..."
    local page token payload exp now exp_date
    page=$(curl -fsSL --max-time 30 "$DOC_URL") || {
        echo "FEHLER: Dokumentation nicht erreichbar."
        return 1
    }

    token=$(printf '%s' "$page" |
        grep -oE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' |
        sed -n '1p')
    unset page

    if [ -z "$token" ]; then
        echo "FEHLER: Kein gültiger Token-Kandidat gefunden."
        return 1
    fi

    # JWT-Ablaufdatum prüfen, bevor irgendeine Datei geändert wird
    payload=$(printf '%s' "$token" | cut -d. -f2 | tr '_-' '/+')
    case $((${#payload} % 4)) in
        2) payload="${payload}==" ;;
        3) payload="${payload}=" ;;
        1)
            echo "FEHLER: JWT-Payload ungültig."
            return 1
            ;;
    esac

    exp=$(printf '%s' "$payload" |
        base64 -d 2>/dev/null |
        jq -r '.exp // empty' 2>/dev/null) || true
    unset payload

    if ! [[ "$exp" =~ ^[0-9]+$ ]]; then
        echo "FEHLER: Token-Ablaufdatum nicht lesbar."
        return 1
    fi

    now=$(date +%s)
    exp_date=$(date -u -d "@$exp" '+%Y-%m-%d %H:%M:%S UTC')
    echo "Online-Token-Länge: ${#token}"
    echo "Token gültig bis: $exp_date"

    if [ "$exp" -le "$now" ]; then
        echo "FEHLER: Online-Token ist abgelaufen."
        return 1
    fi

    # Nur den vorhandenen sponsortoken ersetzen.
    # YAML vor dem Schreiben validieren und vorher sichern.
    local result rc backup
    result=$(NEW_TOKEN="$token" python3 - "$CONFIG_FILE" <<'PY'
import datetime
import os
import re
import shutil
import stat
import sys
import tempfile
import yaml

path = sys.argv[1]
token = os.environ["NEW_TOKEN"]

try:
    with open(path, "r", encoding="utf-8") as f:
        original = f.read()

    lines = original.splitlines(keepends=True)
    matches = []

    for i, line in enumerate(lines):
        newline = "\r\n" if line.endswith("\r\n") else (
            "\n" if line.endswith("\n") else ""
        )
        body = line[:-len(newline)] if newline else line
        m = re.match(r"^([ \t]*sponsortoken[ \t]*:[ \t]*)(.*)$", body)
        if m:
            matches.append((i, m, newline, body))

    if len(matches) != 1:
        print("ERROR: Es muss genau einen sponsortoken-Eintrag geben.",
              file=sys.stderr)
        sys.exit(1)

    i, m, newline, body = matches[0]
    prefix, raw = m.group(1), m.group(2)

    # Kommentar und vorhandene Anführungszeichen möglichst erhalten
    hash_index = raw.find("#")
    if hash_index >= 0:
        before, comment = raw[:hash_index], raw[hash_index:]
        whitespace = before[len(before.rstrip()):]
        old_value = before.rstrip()
        suffix = whitespace + comment
    else:
        old_value = raw.rstrip()
        suffix = raw[len(old_value):]

    stripped = old_value.strip()
    if stripped.startswith('"') and stripped.endswith('"'):
        new_value = '"' + token + '"'
    elif stripped.startswith("'") and stripped.endswith("'"):
        new_value = "'" + token + "'"
    else:
        new_value = token

    lines[i] = prefix + new_value + suffix + newline
    candidate = "".join(lines)

    parsed = yaml.safe_load(candidate)
    if not isinstance(parsed, dict) or parsed.get("sponsortoken") != token:
        print("ERROR: YAML-Prüfung fehlgeschlagen.", file=sys.stderr)
        sys.exit(1)

    current_doc = yaml.safe_load(original)
    if isinstance(current_doc, dict) and current_doc.get("sponsortoken") == token:
        print("UNCHANGED")
        sys.exit(0)

    info = os.stat(path)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y%m%dT%H%M%SZ"
    )
    backup = path + ".bak." + stamp
    shutil.copy2(path, backup)

    fd, temp_path = tempfile.mkstemp(
        prefix=".evcc-token-", dir=os.path.dirname(path)
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(candidate)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(temp_path, stat.S_IMODE(info.st_mode))
        os.replace(temp_path, path)
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    print("UPDATED|" + backup)

except Exception as exc:
    print("ERROR: " + str(exc), file=sys.stderr)
    sys.exit(1)
PY
)
    rc=$?
    unset token

    if [ "$rc" -ne 0 ]; then
        echo "FEHLER: Konfiguration wurde nicht aktualisiert."
        return 1
    fi

    if [ "$result" = "UNCHANGED" ]; then
        echo "Der lokale Token ist bereits aktuell."
        echo "Keine Datei geändert; kein Neustart erforderlich."
        return 0
    fi

    case "$result" in
        UPDATED\|*)
            backup="${result#UPDATED|}"
            echo "Token aktualisiert."
            echo "Sicherung erstellt: $backup"
            ;;
        *)
            echo "FEHLER: Unerwartetes Ergebnis beim Aktualisieren."
            return 1
            ;;
    esac

    # Bleibt bei einem Fehler bestehen und veranlasst einen erneuten Versuch
    touch "$PENDING_FILE"
    restart_evcc
}

if [ -z "${SUPERVISOR_TOKEN:-}" ]; then
    echo "FEHLER: SUPERVISOR_TOKEN fehlt."
    exit 1
fi

INTERVAL_HOURS=$(get_interval)
INTERVAL_SECONDS=$((INTERVAL_HOURS * 3600))

echo "EVCC Trial Token Updater gestartet."
echo "Prüfintervall: $INTERVAL_HOURS Stunden"

while true; do
    update_once || echo "Durchlauf fehlgeschlagen; nächster Versuch folgt planmäßig."
    echo "Nächste Prüfung in $INTERVAL_HOURS Stunden."
    sleep "$INTERVAL_SECONDS"
done
