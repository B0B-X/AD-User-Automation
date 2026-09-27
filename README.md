# Active Directory – Benutzerverwaltung per PowerShell

Automatisiertes Anlegen und Verwalten von Active-Directory-Benutzerkonten
aus einer CSV-Datei – inklusive Gruppenzuordnung und Ablage in der
richtigen Organisationseinheit (OU).

---

## Problem

Das manuelle Anlegen von AD-Benutzerkonten über die grafische Oberfläche
ist bei mehreren Konten zeitaufwändig und fehleranfällig: uneinheitliche
Namens­konventionen, vergessene Gruppen­zuordnungen, falsche OUs.

## Lösung

Dieses PowerShell-Skript liest eine CSV-Datei mit den Benutzerdaten ein und
legt die Konten automatisiert an:

- Benutzerkonto mit einheitlicher Namens­konvention (`Vorname.Nachname`)
- Zuweisung zur passenden Organisationseinheit (OU)
- Aufnahme in die vorgesehenen Sicherheits­gruppen
- Setzen eines Initial­passworts mit Zwang zur Änderung bei erster Anmeldung

---

## Voraussetzungen

- Windows Server 2019 (getestet) mit installierter Rolle **Active Directory Domain Services**
- PowerShell 5.1
- PowerShell-Modul **ActiveDirectory** (`Import-Module ActiveDirectory`)
- Ausführung mit einem Konto, das über Rechte zum Anlegen von AD-Objekten verfügt

---

## Verwendung

1. CSV-Datei nach folgendem Muster vorbereiten (`users.csv`):

   ```csv
   Vorname,Nachname,Abteilung,Gruppe
   Anna,Beispiel,IT,IT-Team
   Max,Muster,Vertrieb,Sales-Team
   ```

2. Skript ausführen:

   ```powershell
   .\New-ADUsers.ps1 -CsvPath .\users.csv
   ```
   <!-- anpassen: echter Skriptname + echte Parameter -->

3. Das Skript legt die Konten an und gibt eine Zusammenfassung aus
   (angelegt / übersprungen / Fehler).

---

## Parameter

| Parameter   | Beschreibung                                  | Pflicht |
|-------------|-----------------------------------------------|---------|
| `-CsvPath`  | Pfad zur CSV-Datei mit den Benutzerdaten       | ja      |
| `-OU`       | Ziel-Organisationseinheit (Distinguished Name) | nein    |

<!-- anpassen: an die echten Parameter deines Skripts angleichen -->

---

## Beispiel

```powershell
.\New-ADUsers.ps1 -CsvPath .\users.csv -OU "OU=Mitarbeiter,DC=firma,DC=local"
```

---

## Hinweise

- Bereits existierende Konten werden erkannt und übersprungen (kein Überschreiben).
- Initial­passwörter werden so gesetzt, dass eine Änderung bei der ersten
  Anmeldung erzwungen wird.
- Vor dem Produktiv­einsatz in einer Test­umgebung prüfen.

<!-- anpassen oder löschen, je nach Funktionsumfang -->

---

## Kontext

Entstanden im Rahmen meiner Umschulung zum Fachinformatiker für
Systemintegration als Übung zur Automatisierung wiederkehrender
Administrations­aufgaben in einer Active-Directory-Umgebung.
