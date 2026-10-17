# Changelog

Alle wesentlichen Änderungen am EVCC Trial Token Updater werden hier dokumentiert.

## [0.6.2] – 2026-10-17

### Entfernt
- Veraltete Datei `rootfs/usr/bin/update-token.sh` entfernt, da die Token-Aktualisierung vollständig durch `run.sh` übernommen wird.

## [0.6.1] – 2026-10-17

### Verbesserungen
- Neustartbehandlung für die EVCC-App überarbeitet.
- Tatsächlichen Status der EVCC-App nach einem fehlgeschlagenen Neustartaufruf prüfen.
- Bereits laufende EVCC-App erkennen und unnötige Neustartversuche vermeiden.
- Offenen Neustartvermerk entfernen, wenn EVCC nachweislich läuft.
- Fehlerbehandlung bei nicht erreichbarer Supervisor-API verbessert.

## [0.6.0] – 2026-10-17

### Hinzugefügt
- Automatischer Abruf des EVCC Trial Sponsor Tokens aus der offiziellen EVCC-Dokumentation.
- Konfigurierbares Aktualisierungsintervall von 1 bis 168 Stunden.
- Prüfung des JWT-Ablaufdatums vor der Aktualisierung.
- Automatisches Aktualisieren des vorhandenen `sponsortoken`-Eintrags in `evcc.yaml`.
- YAML-Validierung vor dem Schreiben der Konfiguration.
- Sicherungskopie der Konfiguration vor jeder Änderung.
- Atomare Dateiaktualisierung zur Vermeidung unvollständiger Konfigurationsdateien.
- Automatische Anforderung eines EVCC-Neustarts nach einer Tokenänderung.
- Speicherung eines offenen Neustartvermerks für spätere Wiederholungsversuche.
- Protokollierung der Aktualisierungsschritte und Fehler.

### Sicherheit und Zuverlässigkeit
- Prüfung der Token-Gültigkeit vor der Übernahme.
- Keine Änderung der Konfiguration, wenn der lokale Token bereits aktuell ist.
- Keine Ausgabe des vollständigen Tokens im Protokoll.
