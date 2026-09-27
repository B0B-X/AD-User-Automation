#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Win11-Client ins Labornetz bringen und der Domäne beitreten.

.DESCRIPTION
    Läuft IN DER CLIENT-VM (als lokaler Administrator).
    1. Edition prüfen (Home kann keiner Domäne beitreten)
    2. Adapter und "Kabel" prüfen
    3. Statische IP, Gateway, DNS (DNS = Domain Controller!)
    4. Ping freigeben, PowerShell-Remoting aktivieren
    5. DNS-Auflösung der Domäne und SRV-Eintrag des DC prüfen
    6. Umbenennen + Domänenbeitritt in einem Schritt, Neustart

    Erster Start (Win11 blockiert Skripte standardmäßig):
        powershell -ExecutionPolicy Bypass -File C:\ADScript\Client-Join.ps1

.EXAMPLE
    .\Client-Join.ps1
    .\Client-Join.ps1 -IPAddress 10.0.10.22 -NewName CLIENT03
#>
param(
    [string]$IPAddress    = "10.0.10.21",
    [int]   $PrefixLength = 24,
    [string]$Gateway      = "10.0.10.1",
    [string]$DnsServer    = "10.0.10.11",      # = DC04
    [string]$DomainName   = "myad.local",
    [string]$DomainAdmin  = "MYAD\Administrator",
    [string]$NewName      = "CLIENT02"
)

$ErrorActionPreference = "Stop"
function Write-Schritt($Text) { Write-Host "`n--- $Text ---" -ForegroundColor Cyan }
function Write-Ok($Text)      { Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn($Text)    { Write-Host "  [!!] $Text" -ForegroundColor Yellow }

try {

    # ---------------------------------------------------------
    Write-Schritt "0. Ausführungsrichtlinie für Skripte"
    # ---------------------------------------------------------
    # Wirkt für KÜNFTIGE Skripte. Dieses Skript selbst muss beim ersten
    # Mal mit -ExecutionPolicy Bypass gestartet werden (Henne-Ei-Problem).

    $Richtlinie = Get-ExecutionPolicy -Scope LocalMachine
    if ($Richtlinie -in "Restricted", "AllSigned", "Undefined") {
        Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
        Write-Ok "Ausführungsrichtlinie: $Richtlinie -> RemoteSigned"
    }
    else {
        Write-Ok "Ausführungsrichtlinie bereits: $Richtlinie"
    }

    # Heruntergeladene/kopierte Skripte entsperren (Zone.Identifier entfernen)
    Get-ChildItem -Path $PSScriptRoot -Filter *.ps1 | Unblock-File
    Write-Ok "Skripte in $PSScriptRoot entsperrt"

    # ---------------------------------------------------------
    Write-Schritt "1. Ausgangslage"
    # ---------------------------------------------------------

    $OS = Get-CimInstance Win32_OperatingSystem
    $CS = Get-CimInstance Win32_ComputerSystem
    Write-Ok "$($OS.Caption) - Rechner: $env:COMPUTERNAME"

    if ($OS.Caption -match "Home") {
        throw "Windows Home kann keiner Domäne beitreten. Pro oder Enterprise nötig."
    }

    if ($CS.PartOfDomain) {
        Write-Ok "Bereits Mitglied der Domäne $($CS.Domain) - nichts zu tun."
        return
    }

    # ---------------------------------------------------------
    Write-Schritt "2. Adapter und Verbindung"
    # ---------------------------------------------------------

    $Adapter = @(Get-NetAdapter | Where-Object InterfaceDescription -like "*Hyper-V*")
    if ($Adapter.Count -ne 1) {
        Get-NetAdapter | Format-Table Name, InterfaceDescription, Status
        throw "Es gibt $($Adapter.Count) Hyper-V-Adapter - erwartet genau 1."
    }
    $Adapter = $Adapter[0]
    $Idx     = $Adapter.ifIndex

    if ($Adapter.Status -ne "Up") {
        Write-Warn "Adapter ist '$($Adapter.Status)' - 'Kabel' steckt nicht."
        Write-Warn "Auf dem HOST: Get-VMNetworkAdapter -VMName <VM> | Select VMName, SwitchName"
        throw "Abbruch: erst die VM mit dem Switch verbinden."
    }
    Write-Ok "$($Adapter.Name)  MAC $($Adapter.MacAddress)  $($Adapter.LinkSpeed)"

    # ---------------------------------------------------------
    Write-Schritt "3. IP, Gateway und DNS"
    # ---------------------------------------------------------

    $IstIP = @(Get-NetIPAddress -InterfaceIndex $Idx -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    Write-Host "  Ist:  $($IstIP.IPAddress -join ', ')"
    Write-Host "  Soll: $IPAddress/$PrefixLength  GW $Gateway  DNS $DnsServer"

    $IpOk = [bool]($IstIP | Where-Object { $_.IPAddress -eq $IPAddress -and $_.PrefixLength -eq $PrefixLength })

    if ($IpOk) {
        Write-Ok "IP stimmt bereits."
    }
    else {
        Set-NetIPInterface -InterfaceIndex $Idx -AddressFamily IPv4 -Dhcp Disabled
        $IstIP | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $Idx -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

        New-NetIPAddress -InterfaceIndex $Idx -IPAddress $IPAddress -PrefixLength $PrefixLength `
            -DefaultGateway $Gateway | Out-Null
        Write-Ok "IP gesetzt: $IPAddress/$PrefixLength  Gateway $Gateway"
    }

    Set-DnsClientServerAddress -InterfaceIndex $Idx -ServerAddresses $DnsServer
    Write-Ok "DNS: $DnsServer"

    # ---------------------------------------------------------
    Write-Schritt "4. Ping und PowerShell-Remoting"
    # ---------------------------------------------------------

    Enable-NetFirewallRule -Name "FPS-ICMP4-ERQ-In"
    Write-Ok "ICMPv4 eingehend erlaubt"

    # Vor dem Beitritt ist das Netzprofil meist "Public" -> Profilprüfung überspringen
    Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
    Write-Ok "WinRM aktiviert (Enable-PSRemoting)"

    # ---------------------------------------------------------
    Write-Schritt "5. Domain Controller erreichbar?"
    # ---------------------------------------------------------

    Start-Sleep -Seconds 3   # neue IP kurz aktiv werden lassen

    if (Test-Connection $DnsServer -Count 2 -Quiet) {
        Write-Ok "DC $DnsServer antwortet auf Ping"
    }
    else {
        throw "DC $DnsServer antwortet nicht. Läuft DC04? Gleicher Switch? ICMP auf dem DC frei?"
    }

    try {
        $Dom = Resolve-DnsName $DomainName -Type A -DnsOnly -ErrorAction Stop
        Write-Ok "$DomainName -> $($Dom.IPAddress -join ', ')"
    }
    catch {
        throw "DNS kann $DomainName nicht auflösen. DNS-Server richtig gesetzt?"
    }

    $Srv = Resolve-DnsName "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -DnsOnly -ErrorAction SilentlyContinue |
           Where-Object Type -eq "SRV"
    if ($Srv) {
        Write-Ok "DC per SRV gefunden: $($Srv.NameTarget -join ', ')"
    }
    else {
        throw "Kein SRV-Eintrag für den DC - Beitritt würde scheitern."
    }

    # ---------------------------------------------------------
    Write-Schritt "6. Umbenennen und Domänenbeitritt"
    # ---------------------------------------------------------

    $Cred = Get-Credential -UserName $DomainAdmin -Message "Kennwort für $DomainAdmin"

    $Param = @{
        DomainName = $DomainName
        Credential = $Cred
        Force      = $true
        PassThru   = $true
    }
    if ($NewName -and $NewName -ne $env:COMPUTERNAME) {
        $Param.NewName = $NewName
    }

    $Ergebnis = Add-Computer @Param
    if (-not $Ergebnis.HasSucceeded) {
        throw "Domänenbeitritt fehlgeschlagen."
    }

    Write-Ok "Beitritt zu $DomainName erfolgreich. Neuer Name: $NewName"
    Write-Host "`nNach dem Neustart anmelden mit 'Anderer Benutzer':" -ForegroundColor Yellow
    Write-Host "  $DomainAdmin  oder z. B.  MYAD\aschmidt" -ForegroundColor Yellow

    Read-Host "`nENTER = Neustart"
    Restart-Computer -Force
}
catch {
    Write-Host "`nFehler: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "ENTER drücken zum Beenden"
}
