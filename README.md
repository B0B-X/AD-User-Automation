# AD-User-Automation
Automatisiert das Anlegen von Active-Directory-Benutzern aus einer CSV-Datei

## Problem
Manuelles Anlegen vieler AD-Konten ist fehleranfällig und zeitraubend.

## Lösung
Das Skript liest eine CSV (Name, Abteilung, Gruppe) und legt Konten
inkl. Gruppenzuordnung und Standard-OU an.

## Verwendung
    .\New-ADUsers.ps1 -CsvPath users.csv

## Umgebung
Windows Server 2025, PowerShell 5.1, AD-Modul
