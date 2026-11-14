# ==============================================================================
# Script : Hub d'Outils de Diagnostic & Réparation Système Windows Multi-langues
# Version : 0.16.7
#  - Textes de confirmation corrigés pour SFC, DISM et Winsock
#  - Rapport SFC limité aux entrées de l'analyse en cours
#  - Langue initiale basée sur la langue d'affichage Windows
# Créé avec l'aide des IA Google Gemini, Mistral Vibe et OpenAI Chatgpt
# Exécution : Nécessite les privilèges Administrateur pour certains outils
# ==============================================================================

# ======================================================================
# INITIALISATION DU SCRIPT
# ======================================================================

# Trace minimale pour récupérer les erreurs du processus ADMIN relancé.
$Script:StartupLogPath = Join-Path $env:TEMP 'WindowsMaintenanceHub-startup.log'
function Write-StartupLog {
    param ([string]$Message)
    try {
        Add-Content -LiteralPath $Script:StartupLogPath -Value ("{0:yyyy-MM-dd HH:mm:ss.fff} {1}" -f (Get-Date), $Message) -Encoding UTF8
    } catch {}
}

trap {
    $StartupError = $_
    $ErrorDetails = $StartupError | Format-List * -Force | Out-String
    Write-StartupLog ("FATAL startup error:`r`n" + $ErrorDetails)
    try {
        $Line = $StartupError.InvocationInfo.ScriptLineNumber
        [void][System.Windows.Forms.MessageBox]::Show(
            ("Le démarrage a échoué. Consultez le journal :`r`n$Script:StartupLogPath`r`n`r`nLigne $Line : $($StartupError.Exception.Message)"),
            'Windows Maintenance Hub',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    } catch {}
    break
}

Write-StartupLog ("Script start; PowerShell $($PSVersionTable.PSVersion); path=$PSCommandPath")

# ÉTAPE A : Charger obligatoirement les outils graphiques en PREMIER
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Activer les styles visuels AVANT toute création de formulaire (rendu cohérent)
[System.Windows.Forms.Application]::EnableVisualStyles()

# Commande standard pour redimensionner proprement toutes les consoles
# NOTE : chaîne single-quote pour éviter l'interprétation des variables $H
$ConsoleSetup = '$H=(Get-Host).UI.RawUI;$H.WindowSize=New-Object System.Management.Automation.Host.Size(80,25);$H.BufferSize=New-Object System.Management.Automation.Host.Size(80,1000);'

# Appliquer la taille compacte à la 1re fenêtre courante
try {
    $H = (Get-Host).UI.RawUI
    $H.WindowSize = New-Object System.Management.Automation.Host.Size(80, 25)
    $H.BufferSize = New-Object System.Management.Automation.Host.Size(80, 1000)
} catch {}

# ----------------------------------------------------------------------
# 1. Choix du Mode d'Exécution (Boîte Personnalisée ADMIN / USER)
# ----------------------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Choisir la langue initiale à partir de la langue d'affichage Windows.
$LaunchLang = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName.ToUpperInvariant()
if ($LaunchLang -notin @('FR', 'EN', 'DE', 'IT', 'ES')) { $LaunchLang = 'EN' }
$LaunchTexts = @{
    FR = @{ Title = 'Mode de lancement'; Prompt = "Choisissez le mode d’exécution :"; Admin = 'ADMINISTRATEUR'; User = 'UTILISATEUR' }
    EN = @{ Title = 'Launch Mode'; Prompt = 'Choose your execution mode:'; Admin = 'ADMIN'; User = 'USER' }
    DE = @{ Title = 'Startmodus'; Prompt = 'Wählen Sie den Ausführungsmodus:'; Admin = 'ADMINISTRATOR'; User = 'BENUTZER' }
    IT = @{ Title = 'Modalità di avvio'; Prompt = 'Scegliere la modalità di esecuzione:'; Admin = 'AMMINISTRATORE'; User = 'UTENTE' }
    ES = @{ Title = 'Modo de inicio'; Prompt = 'Elija el modo de ejecución:'; Admin = 'ADMINISTRADOR'; User = 'USUARIO' }
}
$LaunchText = $LaunchTexts[$LaunchLang]

if (-not $IsAdmin) {
    $ChoiceForm = New-Object System.Windows.Forms.Form
    $ChoiceForm.Text = $LaunchText.Title
    $ChoiceForm.Size = New-Object System.Drawing.Size(420, 180)
    $ChoiceForm.StartPosition = "CenterScreen"
    $ChoiceForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $ChoiceForm.MaximizeBox = $false
    $ChoiceForm.MinimizeBox = $false
    $ChoiceForm.BackColor = [System.Drawing.Color]::FromArgb(243, 243, 243)

    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = "$($LaunchText.Prompt)`r`n"
    $Label.Location = New-Object System.Drawing.Point(20, 20)
    $Label.Size = New-Object System.Drawing.Size(380, 40)
    $Label.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::Bold)
    $Label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $ChoiceForm.Controls.Add($Label)

    $Script:UserDecision = "Exit"

    $BtnChoiceAdmin = New-Object System.Windows.Forms.Button
    $BtnChoiceAdmin.Text = $LaunchText.Admin
    $BtnChoiceAdmin.Location = New-Object System.Drawing.Point(40, 80)
    $BtnChoiceAdmin.Size = New-Object System.Drawing.Size(150, 40)
    $BtnChoiceAdmin.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::Bold)
    $BtnChoiceAdmin.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
    $BtnChoiceAdmin.ForeColor = [System.Drawing.Color]::White
    $BtnChoiceAdmin.FlatStyle = "Flat"
    $BtnChoiceAdmin.FlatAppearance.BorderSize = 0
    $BtnChoiceAdmin.Add_Click({ $Script:UserDecision = "Admin"; $ChoiceForm.Close() })
    $ChoiceForm.Controls.Add($BtnChoiceAdmin)

    $BtnChoiceUser = New-Object System.Windows.Forms.Button
    $BtnChoiceUser.Text = $LaunchText.User
    $BtnChoiceUser.Location = New-Object System.Drawing.Point(210, 80)
    $BtnChoiceUser.Size = New-Object System.Drawing.Size(150, 40)
    $BtnChoiceUser.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::Bold)
    $BtnChoiceUser.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
    $BtnChoiceUser.ForeColor = [System.Drawing.Color]::White
    $BtnChoiceUser.FlatStyle = "Flat"
    $BtnChoiceUser.FlatAppearance.BorderSize = 0
    $BtnChoiceUser.Add_Click({ $Script:UserDecision = "User"; $ChoiceForm.Close() })
    $ChoiceForm.Controls.Add($BtnChoiceUser)

    [void]$ChoiceForm.ShowDialog()

    if ($Script:UserDecision -eq "Admin") {
        $PowerShellExe = Join-Path $PSHOME 'powershell.exe'
        if (-not (Test-Path -LiteralPath $PowerShellExe)) {
            $PowerShellExe = Join-Path $PSHOME 'pwsh.exe'
        }
        $ArgumentLine = '-NoProfile -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
        try {
            $PolicySummary = Get-ExecutionPolicy -List | Out-String
            Set-Content -LiteralPath $Script:StartupLogPath -Value ("{0:yyyy-MM-dd HH:mm:ss.fff} ADMIN relaunch requested; executable=$PowerShellExe; script=$PSCommandPath`r`nExecution policies:`r`n$PolicySummary" -f (Get-Date)) -Encoding UTF8
            $ElevatedProcess = Start-Process -FilePath $PowerShellExe -ArgumentList $ArgumentLine -Verb RunAs -PassThru -ErrorAction Stop
            Write-StartupLog "ADMIN process started; PID=$($ElevatedProcess.Id)"
            Start-Sleep -Milliseconds 1200
            $ElevatedProcess.Refresh()
            if ($ElevatedProcess.HasExited -and $ElevatedProcess.ExitCode -ne 0) {
                Write-StartupLog "ADMIN process exited immediately; exit code=$($ElevatedProcess.ExitCode)"
                [System.Windows.Forms.MessageBox]::Show("Le processus ADMIN s'est arrêté au démarrage.`r`nConsultez le journal : $($Script:StartupLogPath)", "Launch Mode", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        } catch {
            Write-StartupLog ("ADMIN relaunch failed:`r`n" + ($_ | Format-List * -Force | Out-String))
            [System.Windows.Forms.MessageBox]::Show("Élévation refusée ou échec du lancement.`r`nDétails : $($Script:StartupLogPath)`r`n`r`n$($_.Exception.Message)", "Launch Mode", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
        Exit
    }
    elseif ($Script:UserDecision -eq "Exit") {
        Exit
    }
}

# ----------------------------------------------------------------------
# Dictionnaire des traductions (Centralisation FR / EN / DE / IT / ES)
# ----------------------------------------------------------------------
$Translations = @{
    FR = @{
        Title        = "Hub de Maintenance Windows"
        Header       = "Hub de Maintenance Windows"
        TabSystem    = "Système & Réparation"
        TabClean     = "Nettoyage & Optimisation"
        TabDiag      = "Matériel & Diagnostics"
        TabPerf      = "Performances & Journaux"
        TabNet       = "Réseau & Internet"
        TabAdv       = "Outils Avancés"
        BtnScan      = "DISM ScanHealth"
        BtnRestore   = "DISM RestoreHealth"
        BtnSfc       = "SFC Scannow"
        BtnSysRestore= "Protection du système (Restauration)"
        BtnChkdsk    = "Vérification disque (CHKDSK)"
        BtnCleanMgr  = "Nettoyage de Disque (Cleanmgr)"
        BtnWinClean  = "Nettoyage Composants (WinSxS)"
        BtnOptDrive  = "Optimiseur de lecteur (TRIM/Défrag)"
        BtnWinsock   = "Réinitialiser le catalogue Winsock"
        BtnIpReset   = "Réinitialiser la pile TCP/IP"
        BtnFlushDns  = "Vider le cache DNS"
        BtnSysInfo   = "Informations Système (Msinfo32)"
        BtnDevMgr    = "Gestionnaire de périphériques"
        BtnDiskMgr   = "Gestionnaire de disques"
        BtnDxDiag    = "Diagnostic DirectX (DxDiag)"
        BtnMemDiag   = "Diagnostic Mémoire RAM"
        MemDiagHint  = "(avec redémarrage)"
        BtnEventVwr  = "Observateur d'événements"
        BtnResMon    = "Moniteur de ressources"
        BtnPerfDiag  = "Diagnostic de Performance"
        BtnReliability= "Moniteur de Fiabilité"
        BtnMsConfig  = "Configuration du Système (Msconfig)"
        BtnFirewall  = "Pare-feu Windows Avancé"
        BtnNetConn   = "Connexions Réseau (ncpa.cpl)"
        BtnMRT       = "Outil de Suppression Malwares (MRT)"
        BtnUserPass  = "Gestion des Comptes (Netplwiz)"
        BtnPower     = "Options d'Alimentation"
        BtnServices  = "Services (services.msc)"
        BtnCompMgmt  = "Gestion de l'ordinateur (compmgmt)"
        BtnSfcLog    = "📄 Voir les détails du rapport SFC"
        ConfTitle    = "Confirmation"
        MsgSfc       = "SFC /scannow vérifie l'intégrité des fichiers système protégés et tente de remplacer ceux qui sont corrompus.`n`nVoulez-vous lancer l'analyse et la réparation dans une console ?"
        MsgScan      = "Ce diagnostic vérifie l'image système sans la modifier.`n`nVoulez-vous lancer l'analyse dans une console ?"
        MsgRestore   = "Analyse le magasin de composants de l'image Windows et tente de réparer les corruptions détectées.`n`nVoulez-vous lancer la réparation dans une console ?"
        MsgSysRestore= "Ouvre l'interface de Windows pour gérer et créer des points de restauration.`n`nOuvrir la Protection du système ?"
        MsgChkdsk    = "Vérifie le système de fichiers de C: en lecture seule.`n⚠️ Cette commande ne répare pas les erreurs et ne planifie pas de réparation au redémarrage.`n`nLancer la vérification ?"
        MsgCleanMgr  = "Ouvre Nettoyage de disque pour repérer les fichiers temporaires et autres fichiers Windows pouvant être supprimés. Vous choisissez les catégories à nettoyer.`n`nContinuer ?"
        MsgWinClean  = "Nettoie les composants Windows remplacés pour réduire WinSxS. L'opération peut durer plusieurs minutes. La commande n'utilise pas /ResetBase.`n`nContinuer ?"
        MsgOptDrive  = "Ouvre l'outil natif pour vérifier l'état du TRIM (SSD) et défragmenter vos disques.`n`nOuvrir l'Optimiseur de lecteur ?"
        MsgWinsock   = "Réinitialise le catalogue Winsock et supprime les fournisseurs réseau personnalisés (LSP). Certains logiciels réseau tiers peuvent être affectés.`n⚠️ Un redémarrage du PC sera nécessaire.`n`nExécuter la réinitialisation ?"
        MsgIpReset   = "Réinitialise le protocole TCP/IP à son état par défaut.`n⚠️ Peut effacer vos configurations d'IP fixe.`n⚠️ Un redémarrage du PC sera nécessaire.`n`nExécuter la réinitialisation ?"
        MsgFlushDns  = "Vide le cache de résolution DNS local.`n⚡ Aucun redémarrage requis.`n`nExécuter le vidage ?"
        MsgSysInfo   = "Affiche des informations détaillées sur votre matériel et BIOS.`n`nOuvrir Msinfo32 ?"
        MsgDevMgr    = "Affiche les appareils détectés et l'état de leurs pilotes. Permet notamment de mettre à jour, désactiver ou désinstaller un pilote.`n`nContinuer ?"
        MsgDiskMgr   = "Affiche et gère les disques, volumes et partitions. Le formatage ou la suppression d'un volume peut entraîner une perte de données.`n`nContinuer ?"
        MsgDxDiag    = "Analyse les composants graphiques, audio et pilotes DirectX.`n`nLancer DxDiag ?"
        MsgMemDiag   = "Vérifie les défauts physiques de la RAM (nécessite un redémarrage).`n`nOuvrir l'outil de diagnostic ?"
        MsgEventVwr  = "Consulte les journaux Windows pour repérer les erreurs, avertissements et événements système récents.`n`nContinuer ?"
        MsgResMon    = "Ouvre le Moniteur de ressources (CPU, RAM, Disque, Réseau en temps réel).`n`nOuvrir l'outil ?"
        MsgPerfDiag  = "Génère un rapport de performance de 60 secondes en arrière-plan.`n`nLancer l'analyse ?"
        MsgReliability= "Affiche l'historique de stabilité de Windows, notamment les plantages d'applications, erreurs système et mises à jour.`n`nOuvrir le Moniteur de fiabilité ?"
        MsgMsConfig  = "Permet de configurer les options de démarrage de Windows et certains services. Modifier ces réglages peut empêcher des services ou applications de démarrer.`n`nOuvrir l'outil ?"
        MsgFirewall  = "Permet de consulter et modifier les règles entrantes et sortantes du pare-feu. Une modification peut bloquer une application ou une connexion réseau.`n`nOuvrir le Pare-feu ?"
        MsgNetConn   = "Affiche les adaptateurs réseau et leurs paramètres. Désactiver un adaptateur ou modifier sa configuration peut couper la connexion.`n`nContinuer ?"
        MsgMRT       = "Lance l'outil d'analyse et de suppression des logiciels malveillants de Windows.`n`nLancer MRT ?"
        MsgUserPass  = "Permet de gérer les comptes utilisateurs et certaines options de connexion.`n`nContinuer ?"
        MsgPower     = "Permet de choisir un mode de gestion de l'alimentation et de régler la veille ou l'extinction de l'écran.`n`nContinuer ?"
        MsgServices  = "Ouvre la console des Services Windows (démarrage/arrêt des services).`n`nContinuer ?"
        MsgCompMgmt  = "Ouvre la console Gestion de l'ordinateur (disques, périphériques, événements, dossiers partagés).`n`nContinuer ?"
        LogStart     = "[DÉBUT] Lancement de l'outil natif..."
        LogEnd       = "[FIN] Fenêtre du hub fermée."
        SfcExtracted = "[INFO] Les détails de cette analyse SFC ont été extraits dans %LOGPATH%."
        SfcEmpty     = "[INFO] Aucun détail SFC n'a été trouvé pour cette analyse."
        SfcRunning   = "[INFO] SFC lancé dans une console séparée. Le rapport de cette analyse sera détecté à la fin."
        ToolNotFound = "[ERREUR] Impossible de lancer l'outil : %TOOL% introuvable ou inaccessible."
        AboutTitle   = "À propos"
        AboutBody    = "Windows Maintenance Hub`r`nTous les outils de ce hub sont nativement intégrés à Windows.`r`n`r`nVersion 0.16.7`r`n`r`nOpen Source`r`nCréé avec l'aide de Google Gemini & Mistral Vibe.`r`nOS : Windows 10 & 11.`r`n2026/11"
    }
    EN = @{
        Title        = "Windows Maintenance Hub"
        Header       = "Windows Maintenance Hub"
        TabSystem    = "System & Repair"
        TabClean     = "Cleanup & Optimization"
        TabDiag      = "Hardware & Diagnostics"
        TabPerf      = "Performance & Logs"
        TabNet       = "Network & Internet"
        TabAdv       = "Advanced Tools"
        BtnScan      = "DISM ScanHealth"
        BtnRestore   = "DISM RestoreHealth"
        BtnSfc       = "SFC Scannow"
        BtnSysRestore= "System Protection (Restore)"
        BtnChkdsk    = "Disk Check (CHKDSK)"
        BtnCleanMgr  = "Disk Cleanup (Cleanmgr)"
        BtnWinClean  = "Component Cleanup (WinSxS)"
        BtnOptDrive  = "Drive Optimizer (TRIM/Defrag)"
        BtnWinsock   = "Reset Winsock Catalog"
        BtnIpReset   = "Reset TCP/IP Stack"
        BtnFlushDns  = "Flush DNS Cache"
        BtnSysInfo   = "System Information (Msinfo32)"
        BtnDevMgr    = "Device Manager"
        BtnDiskMgr   = "Disk Management"
        BtnDxDiag    = "DirectX Diagnostic (DxDiag)"
        BtnMemDiag   = "RAM Memory Diagnostic"
        MemDiagHint  = "(with reboot)"
        BtnEventVwr  = "Event Viewer"
        BtnResMon    = "Resource Monitor"
        BtnPerfDiag  = "Performance Diagnostic"
        BtnReliability= "Reliability Monitor"
        BtnMsConfig  = "System Configuration (Msconfig)"
        BtnFirewall  = "Advanced Windows Firewall"
        BtnNetConn   = "Network Connections (ncpa.cpl)"
        BtnMRT       = "Malware Removal Tool (MRT)"
        BtnUserPass  = "Advanced User Accounts (Netplwiz)"
        BtnPower     = "Power Options"
        BtnServices  = "Services (services.msc)"
        BtnCompMgmt  = "Computer Management (compmgmt)"
        BtnSfcLog    = "📄 View SFC report details"
        ConfTitle    = "Confirmation"
        MsgSfc       = "SFC /scannow checks protected system files and attempts to replace corrupted files.`n`nStart the scan and repair in a console?"
        MsgScan      = "This diagnostic checks the system image without modifying it.`n`nStart the scan in a console?"
        MsgRestore   = "Scans the Windows image component store and attempts to repair detected corruption.`n`nStart the repair in a console?"
        MsgSysRestore= "Opens the Windows interface to manage and create restore points.`n`nOpen System Protection?"
        MsgChkdsk    = "Checks the C: file system in read-only mode.`n⚠️ This command does not repair errors or schedule a repair at restart.`n`nRun the check?"
        MsgCleanMgr  = "Opens Disk Cleanup to review temporary and other removable Windows files. You choose which categories to clean.`n`nContinue?"
        MsgWinClean  = "Cleans superseded Windows components to reduce WinSxS. This can take several minutes. The command does not use /ResetBase.`n`nContinue?"
        MsgOptDrive  = "Opens the native tool to check TRIM (SSD) status and defrag drives.`n`nOpen Drive Optimizer?"
        MsgWinsock   = "Resets the Winsock catalog and removes custom Layered Service Providers (LSPs). Some third-party network software may be affected.`n⚠️ System restart required.`n`nRun reset?"
        MsgIpReset   = "Resets TCP/IP protocol to default state.`n⚠️ May clear static IP settings.`n⚠️ System restart required.`n`nRun reset?"
        MsgFlushDns  = "Flushes the local DNS resolver cache.`n⚡ No restart required.`n`nFlush DNS?"
        MsgSysInfo   = "Displays detailed information about your hardware and BIOS.`n`nOpen Msinfo32?"
        MsgDevMgr    = "Shows detected devices and their driver status. You can update drivers, disable devices, or uninstall them here.`n`nContinue?"
        MsgDiskMgr   = "Displays and manages disks, volumes, and partitions. Formatting or deleting a volume can cause data loss.`n`nContinue?"
        MsgDxDiag    = "Analyzes graphics, audio components, and DirectX drivers.`n`nLaunch DxDiag?"
        MsgMemDiag   = "Checks RAM for physical defects (requires reboot).`n`nOpen diagnostic tool?"
        MsgEventVwr  = "Reviews Windows event logs to find recent errors, warnings, and system events.`n`nContinue?"
        MsgResMon    = "Opens Resource Monitor (CPU, RAM, Disk, Network in real-time).`n`nOpen tool?"
        MsgPerfDiag  = "Generates a 60-second performance report in the background.`n`nStart analysis?"
        MsgReliability= "Shows Windows stability history, including app crashes, system errors, and updates.`n`nOpen Reliability Monitor?"
        MsgMsConfig  = "Configures Windows startup options and some services. Changes can prevent services or apps from starting.`n`nOpen the tool?"
        MsgFirewall  = "Lets you review and change inbound and outbound firewall rules. A change can block an app or network connection.`n`nOpen Firewall?"
        MsgNetConn   = "Shows network adapters and their settings. Disabling an adapter or changing its configuration can interrupt connectivity.`n`nContinue?"
        MsgMRT       = "Launches the built-in Windows Malicious Software Removal Tool.`n`nLaunch MRT?"
        MsgUserPass  = "Manages user accounts and some sign-in options.`n`nContinue?"
        MsgPower     = "Lets you choose a power plan and adjust sleep or screen-off settings.`n`nContinue?"
        MsgServices  = "Opens the Windows Services console (start/stop services).`n`nContinue?"
        MsgCompMgmt  = "Opens Computer Management (disks, devices, events, shared folders).`n`nContinue?"
        LogStart     = "[START] Launching native tool..."
        LogEnd       = "[END] Hub window closed."
        SfcExtracted = "[INFO] Details from this SFC scan were extracted to %LOGPATH%."
        SfcEmpty     = "[INFO] No SFC details were found for this scan."
        SfcRunning   = "[INFO] SFC launched in a separate console. This scan's report will be detected when it finishes."
        ToolNotFound = "[ERROR] Could not launch tool: %TOOL% not found or inaccessible."
        AboutTitle   = "About"
        AboutBody    = "Windows Maintenance Hub`r`nAll tools in this hub are natively built into Windows.`r`n`r`nVersion 0.16.7`r`n`r`nOpen Source`r`nCreated with the help of Google Gemini & Mistral Vibe.`r`nOS : Windows 10 & 11.`r`n2026/11"
    }
    DE = @{
        Title        = "Windows Wartungs-Hub"
        Header       = "Windows Wartungs-Hub"
        TabSystem    = "System & Reparatur"
        TabClean     = "Bereinigung & Optimierung"
        TabDiag      = "Hardware & Diagnose"
        TabPerf      = "Leistung & Protokolle"
        TabNet       = "Netzwerk & Internet"
        TabAdv       = "Erweiterte Tools"
        BtnScan      = "DISM ScanHealth"
        BtnRestore   = "DISM RestoreHealth"
        BtnSfc       = "SFC Scannow"
        BtnSysRestore= "Computerschutz (Wiederherstellung)"
        BtnChkdsk    = "Datenträgerprüfung (CHKDSK)"
        BtnCleanMgr  = "Datenträgerbereinigung (Cleanmgr)"
        BtnWinClean  = "Komponentenbereinigung (WinSxS)"
        BtnOptDrive  = "Laufwerksoptimierung (TRIM/Defrag)"
        BtnWinsock   = "Winsock-Katalog zurücksetzen"
        BtnIpReset   = "TCP/IP-Stapel zurücksetzen"
        BtnFlushDns  = "DNS-Cache leeren"
        BtnSysInfo   = "Systeminformationen (Msinfo32)"
        BtnDevMgr    = "Geräte-Manager"
        BtnDiskMgr   = "Datenträgerverwaltung"
        BtnDxDiag    = "DirectX-Diagnose (DxDiag)"
        BtnMemDiag   = "RAM-Speicherdiagnose"
        MemDiagHint  = "(mit Neustart)"
        BtnEventVwr  = "Ereignisanzeige"
        BtnResMon    = "Ressourcenmonitor"
        BtnPerfDiag  = "Leistungsdiagnose"
        BtnReliability= "Zuverlässigkeitsüberwachung"
        BtnMsConfig  = "Systemkonfiguration (Msconfig)"
        BtnFirewall  = "Erweiterte Windows-Firewall"
        BtnNetConn   = "Netzwerkverbindungen (ncpa.cpl)"
        BtnMRT       = "Malware-Entfernungstool (MRT)"
        BtnUserPass  = "Erweiterte Benutzerkonten (Netplwiz)"
        BtnPower     = "Energieoptionen"
        BtnServices  = "Dienste (services.msc)"
        BtnCompMgmt  = "Computerverwaltung (compmgmt)"
        BtnSfcLog    = "📄 SFC-Berichtsdetails anzeigen"
        ConfTitle    = "Bestätigung"
        MsgSfc       = "SFC /scannow überprüft geschützte Systemdateien und versucht, beschädigte Dateien zu ersetzen.`n`nAnalyse und Reparatur in einer Konsole starten?"
        MsgScan      = "Diese Diagnose überprüft das Systemabbild, ohne es zu ändern.`n`nScan in einer Konsole starten?"
        MsgRestore   = "Überprüft den Komponentenspeicher des Windows-Abbilds und versucht, erkannte Beschädigungen zu reparieren.`n`nReparatur in einer Konsole starten?"
        MsgSysRestore= "Öffnet die Windows-Oberfläche zum Verwalten von Wiederherstellungspunkten.`n`nComputerschutz öffnen?"
        MsgChkdsk    = "Prüft das Dateisystem von C: im schreibgeschützten Modus.`n⚠️ Dieser Befehl repariert keine Fehler und plant keine Prüfung beim Neustart.`n`nPrüfung starten?"
        MsgCleanMgr  = "Öffnet die Datenträgerbereinigung, um temporäre und andere entbehrliche Windows-Dateien auszuwählen und zu löschen. Sie wählen die zu bereinigenden Kategorien.`n`nFortfahren?"
        MsgWinClean  = "Entfernt ersetzte Windows-Komponenten, um WinSxS zu verkleinern. Das kann mehrere Minuten dauern. Der Befehl verwendet nicht /ResetBase.`n`nFortfahren?"
        MsgOptDrive  = "Öffnet das native Tool zur Überprüfung des TRIM-Status (SSD).`n`nLaufwerksoptimierung öffnen?"
        MsgWinsock   = "Setzt den Winsock-Katalog zurück und entfernt benutzerdefinierte Layered Service Provider (LSPs). Netzwerksoftware von Drittanbietern kann betroffen sein.`n⚠️ Ein Neustart ist erforderlich.`n`nZurücksetzen ausführen?"
        MsgIpReset   = "Setzt das TCP/IP-Protokoll zurück.`n⚠️ Kann statische IP-Einstellungen löschen.`n⚠️ Neustart erforderlich.`n`nZurücksetzen ausführen?"
        MsgFlushDns  = "Leert den lokalen DNS-Auflösungscache.`n⚡ Kein Neustart erforderlich.`n`nDNS-Cache leeren?"
        MsgSysInfo   = "Zeigt detaillierte Informationen zu Hardware und BIOS.`n`nMsinfo32 öffnen?"
        MsgDevMgr    = "Zeigt erkannte Geräte und den Status ihrer Treiber. Treiber können aktualisiert sowie Geräte deaktiviert oder deinstalliert werden.`n`nFortfahren?"
        MsgDiskMgr   = "Zeigt und verwaltet Datenträger, Volumes und Partitionen. Formatieren oder Löschen kann Datenverlust verursachen.`n`nFortfahren?"
        MsgDxDiag    = "Analysiert Grafik-, Audiokomponenten und DirectX-Treiber.`n`nDxDiag starten?"
        MsgMemDiag   = "Überprüft den RAM auf Fehler (Neustart erforderlich).`n`nDiagnosetool öffnen?"
        MsgEventVwr  = "Durchsucht die Windows-Ereignisprotokolle nach Fehlern, Warnungen und aktuellen Systemereignissen.`n`nFortfahren?"
        MsgResMon    = "Öffnet den Ressourcenmonitor.`n`nTool öffnen?"
        MsgPerfDiag  = "Erstellt im Hintergrund einen 60-sekündigen Leistungsbericht.`n`nAnalyse starten?"
        MsgReliability= "Zeigt den Windows-Stabilitätsverlauf mit App-Abstürzen, Systemfehlern und Updates.`n`nZuverlässigkeitsüberwachung öffnen?"
        MsgMsConfig  = "Konfiguriert Windows-Startoptionen und bestimmte Dienste. Änderungen können verhindern, dass Dienste oder Programme starten.`n`nTool öffnen?"
        MsgFirewall  = "Zeigt und konfiguriert eingehende und ausgehende Firewallregeln. Änderungen können Apps oder Netzwerkverbindungen blockieren.`n`nFirewall öffnen?"
        MsgNetConn   = "Zeigt Netzwerkadapter und Verbindungseinstellungen. Das Deaktivieren eines Adapters oder Ändern seiner Einstellungen kann die Verbindung unterbrechen.`n`nFortfahren?"
        MsgMRT       = "Startet das integrierte Windows-Tool zum Entfernen bösartiger Software.`n`nMRT starten?"
        MsgUserPass  = "Verwaltet Benutzerkonten und bestimmte Anmeldeoptionen.`n`nFortfahren?"
        MsgPower     = "Dient zur Auswahl eines Energiesparplans und zum Anpassen von Bildschirm- und Energiespareinstellungen.`n`nFortfahren?"
        MsgServices  = "Öffnet die Windows-Dienste-Konsole (Dienste starten/stoppen).`n`nFortfahren?"
        MsgCompMgmt  = "Öffnet die Computerverwaltung (Datenträger, Geräte, Ereignisse, freigegebene Ordner).`n`nFortfahren?"
        LogStart     = "[START] Natives Tool wird gestartet..."
        LogEnd       = "[ENDE] Hub-Fenster geschlossen."
        SfcExtracted = "[INFO] Details dieses SFC-Scans extrahiert nach %LOGPATH%."
        SfcEmpty     = "[INFO] Für diesen SFC-Scan wurden keine Details gefunden."
        SfcRunning   = "[INFO] SFC in einer separaten Konsole gestartet. Der Bericht dieses Scans wird nach Abschluss erkannt."
        ToolNotFound = "[FEHLER] Tool konnte nicht gestartet werden: %TOOL% nicht gefunden oder nicht zugänglich."
        AboutTitle   = "Über"
        AboutBody    = "Windows Wartungs-Hub`r`nAlle Tools in diesem Hub sind nativ in Windows integriert.`r`n`r`nVersion 0.16.7`r`n`r`nOpen Source`r`nErstellt mit Hilfe von Google Gemini & Mistral Vibe.`r`nOS : Windows 10 & 11.`r`n2026/11"
    }
    IT = @{
        Title        = "Hub di Manutenzione Windows"
        Header       = "Hub di Manutenzione Windows"
        TabSystem    = "Sistema e Ripristino"
        TabClean     = "Pulizia e Ottimizzazione"
        TabDiag      = "Hardware e Diagnostica"
        TabPerf      = "Prestazioni e Registri"
        TabNet       = "Rete & Internet"
        TabAdv       = "Strumenti Avanzati"
        BtnScan      = "DISM ScanHealth"
        BtnRestore   = "DISM RestoreHealth"
        BtnSfc       = "SFC Scannow"
        BtnSysRestore= "Protezione di sistema (Ripristino)"
        BtnChkdsk    = "Verifica disco (CHKDSK)"
        BtnCleanMgr  = "Pulizia disco (Cleanmgr)"
        BtnWinClean  = "Pulizia Componenti (WinSxS)"
        BtnOptDrive  = "Ottimizzatore unità (TRIM/Defrag)"
        BtnWinsock   = "Ripristina il catalogo Winsock"
        BtnIpReset   = "Ripristina Stack TCP/IP"
        BtnFlushDns  = "Svuota Cache DNS"
        BtnSysInfo   = "Informazioni di Sistema (Msinfo32)"
        BtnDevMgr    = "Gestione dispositivi"
        BtnDiskMgr   = "Gestione disco"
        BtnDxDiag    = "Diagnostica DirectX (DxDiag)"
        BtnMemDiag   = "Diagnostica Memoria RAM"
        MemDiagHint  = "(con riavvio)"
        BtnEventVwr  = "Visualizzatore eventi"
        BtnResMon    = "Monitoraggio risorse"
        BtnPerfDiag  = "Diagnostica Prestazioni"
        BtnReliability= "Monitoraggio Affidabilità"
        BtnMsConfig  = "Configurazione di Sistema (Msconfig)"
        BtnFirewall  = "Windows Firewall Avanzato"
        BtnNetConn   = "Connessioni di Rete (ncpa.cpl)"
        BtnMRT       = "Strumento Rimozione Malware (MRT)"
        BtnUserPass  = "Gestione Account (Netplwiz)"
        BtnPower     = "Opzioni Risparmio Energia"
        BtnServices  = "Servizi (services.msc)"
        BtnCompMgmt  = "Gestione computer (compmgmt)"
        BtnSfcLog    = "📄 Visualizza dettagli rapporto SFC"
        ConfTitle    = "Conferma"
        MsgSfc       = "SFC /scannow verifica i file di sistema protetti e tenta di sostituire quelli danneggiati.`n`nAvviare l'analisi e la riparazione in una console?"
        MsgScan      = "Questa diagnostica verifica l'immagine di sistema senza modificarla.`n`nAvviare la scansione in una console?"
        MsgRestore   = "Analizza l'archivio dei componenti dell'immagine Windows e tenta di riparare i danneggiamenti rilevati.`n`nAvviare la riparazione in una console?"
        MsgSysRestore= "Apre l'interfaccia di Windows per gestire i punti di ripristino.`n`nAprire la Protezione di sistema?"
        MsgChkdsk    = "Verifica il file system di C: in modalità di sola lettura.`n⚠️ Questo comando non ripara gli errori e non pianifica una riparazione al riavvio.`n`nAvviare la verifica?"
        MsgCleanMgr  = "Apre Pulizia disco per individuare file temporanei e altri file Windows rimovibili. Puoi scegliere le categorie da pulire.`n`nContinuare?"
        MsgWinClean  = "Pulisce i componenti Windows sostituiti per ridurre WinSxS. L'operazione può richiedere alcuni minuti. Il comando non usa /ResetBase.`n`nContinuare?"
        MsgOptDrive  = "Apre lo strumento nativo per verificare il TRIM (SSD) e deframmentare.`n`nAprire l'Ottimizzatore unità?"
        MsgWinsock   = "Reimposta il catalogo Winsock e rimuove i Layered Service Provider (LSP) personalizzati. Alcuni software di rete di terze parti potrebbero essere interessati.`n⚠️ Sarà necessario riavviare il PC.`n`nEseguire il ripristino?"
        MsgIpReset   = "Ripristina il protocollo TCP/IP allo stato iniziale.`n⚠️ Può cancellare le configurazioni IP statiche.`n⚠️ Richiede il riavvio del PC.`n`nEseguire il ripristino?"
        MsgFlushDns  = "Svuota la cache del resolver DNS locale.`n⚡ Nessun riavvio richiesto.`n`nSvuotare la cache?"
        MsgSysInfo   = "Mostra informazioni dettagliate su hardware e BIOS.`n`nAprire Msinfo32?"
        MsgDevMgr    = "Mostra i dispositivi rilevati e lo stato dei driver. Da qui puoi aggiornare i driver, disabilitare i dispositivi o disinstallarli.`n`nContinuare?"
        MsgDiskMgr   = "Visualizza e gestisce dischi, volumi e partizioni. La formattazione o l'eliminazione di un volume può causare la perdita di dati.`n`nContinuare?"
        MsgDxDiag    = "Analizza i componenti grafici, audio e i driver DirectX.`n`nAvviare DxDiag?"
        MsgMemDiag   = "Verifica i difetti fisici della RAM (richiede riavvio).`n`nAprire lo strumento?"
        MsgEventVwr  = "Consulta i registri eventi di Windows per individuare errori, avvisi ed eventi di sistema recenti.`n`nContinuare?"
        MsgResMon    = "Apre il Monitoraggio risorse (CPU, RAM, Disco, Rete in tempo reale).`n`nAprire lo strumento?"
        MsgPerfDiag  = "Genera un rapporto di 60 secondi in background.`n`nAvviare l'analisi?"
        MsgReliability= "Mostra la cronologia di stabilità di Windows, inclusi arresti anomali delle app, errori di sistema e aggiornamenti.`n`nAprire il Monitoraggio affidabilità?"
        MsgMsConfig  = "Configura le opzioni di avvio di Windows e alcuni servizi. Le modifiche possono impedire l'avvio di servizi o programmi.`n`nAprire lo strumento?"
        MsgFirewall  = "Consente di consultare e modificare le regole firewall in entrata e in uscita. Una modifica può bloccare un'app o una connessione di rete.`n`nAprire il Firewall?"
        MsgNetConn   = "Mostra le schede di rete e le relative impostazioni. Disattivare una scheda o modificarne la configurazione può interrompere la connessione.`n`nContinuare?"
        MsgMRT       = "Avvia lo strumento integrato di Windows per la rimozione del software dannoso.`n`nAvviare MRT?"
        MsgUserPass  = "Consente di gestire gli account utente e alcune opzioni di accesso.`n`nContinuare?"
        MsgPower     = "Consente di scegliere un piano di alimentazione e regolare la sospensione o lo spegnimento dello schermo.`n`nContinuare?"
        MsgServices  = "Apre la console dei Servizi di Windows (avvio/arresto dei servizi).`n`nContinuare?"
        MsgCompMgmt  = "Apre Gestione computer (dischi, dispositivi, eventi, cartelle condivise).`n`nContinuare?"
        LogStart     = "[INIZIO] Avvio strumento nativo..."
        LogEnd       = "[FINE] Finestra dell'hub chiusa."
        SfcExtracted = "[INFO] I dettagli di questa scansione SFC sono stati estratti in %LOGPATH%."
        SfcEmpty     = "[INFO] Non sono stati trovati dettagli SFC per questa scansione."
        SfcRunning   = "[INFO] SFC avviato in una console separata. Il rapporto di questa scansione sarà rilevato al termine."
        ToolNotFound = "[ERRORE] Impossibile avviare lo strumento: %TOOL% non trovato o inaccessibile."
        AboutTitle   = "Informazioni"
        AboutBody    = "Hub di Manutenzione Windows`r`nTutti gli strumenti di questo hub sono nativamente integrati in Windows.`r`n`r`nVersione 0.16.7`r`n`r`nOpen Source`r`nCreato con l'aiuto di Google Gemini & Mistral Vibe.`r`nOS : Windows 10 & 11.`r`n2026/11"
    }
    ES = @{
        Title        = "Hub de Mantenimiento de Windows"
        Header       = "Hub de Mantenimiento de Windows"
        TabSystem    = "Sistema y Reparación"
        TabClean     = "Limpieza y Optimización"
        TabDiag      = "Hardware y Diagnósticos"
        TabPerf      = "Rendimiento y Registros"
        TabNet       = "Red & Internet"
        TabAdv       = "Herramientas Avanzadas"
        BtnScan      = "DISM ScanHealth"
        BtnRestore   = "DISM RestoreHealth"
        BtnSfc       = "SFC Scannow"
        BtnSysRestore= "Protección del sistema (Restaurar)"
        BtnChkdsk    = "Verificación de disco (CHKDSK)"
        BtnCleanMgr  = "Liberador de espacio (Cleanmgr)"
        BtnWinClean  = "Limpieza Componentes (WinSxS)"
        BtnOptDrive  = "Optimizador de unidades (TRIM)"
        BtnWinsock   = "Restablecer catálogo Winsock"
        BtnIpReset   = "Restablecer pila TCP/IP"
        BtnFlushDns  = "Vaciar caché DNS"
        BtnSysInfo   = "Información del Sistema (Msinfo32)"
        BtnDevMgr    = "Administrador de dispositivos"
        BtnDiskMgr   = "Administración de discos"
        BtnDxDiag    = "Diagnóstico DirectX (DxDiag)"
        BtnMemDiag   = "Diagnóstico de Memoria RAM"
        MemDiagHint  = "(con reinicio)"
        BtnEventVwr  = "Visor de eventos"
        BtnResMon    = "Monitor de recursos"
        BtnPerfDiag  = "Diagnóstico de Rendimiento"
        BtnReliability= "Monitor de Confiabilidad"
        BtnMsConfig  = "Configuración del Sistema (Msconfig)"
        BtnFirewall  = "Firewall de Windows Avanzado"
        BtnNetConn   = "Conexiones de Red (ncpa.cpl)"
        BtnMRT       = "Herramienta de Eliminación (MRT)"
        BtnUserPass  = "Cuentas de Usuario (Netplwiz)"
        BtnPower     = "Opciones de Energía"
        BtnServices  = "Servicios (services.msc)"
        BtnCompMgmt  = "Administración de equipos (compmgmt)"
        BtnSfcLog    = "📄 Ver detalles del informe SFC"
        ConfTitle    = "Confirmación"
        MsgSfc       = "SFC /scannow comprueba los archivos de sistema protegidos e intenta reemplazar los que están dañados.`n`n¿Iniciar el análisis y la reparación en una consola?"
        MsgScan      = "Este diagnóstico verifica la imagen del sistema sin modificarla.`n`n¿Iniciar el análisis en consola?"
        MsgRestore   = "Analiza el almacén de componentes de la imagen de Windows e intenta reparar los daños detectados.`n`n¿Iniciar la reparación en una consola?"
        MsgSysRestore= "Abre la interfaz de Windows para administrar puntos de restauración.`n`n¿Abrir Protección del sistema?"
        MsgChkdsk    = "Comprueba el sistema de archivos de C: en modo de solo lectura.`n⚠️ Este comando no repara errores ni programa una reparación al reiniciar.`n`n¿Iniciar la comprobación?"
        MsgCleanMgr  = "Abre el Liberador de espacio para revisar archivos temporales y otros archivos de Windows que se pueden quitar. Tú eliges las categorías que se limpian.`n`n¿Continuar?"
        MsgWinClean  = "Limpia componentes de Windows reemplazados para reducir WinSxS. Puede tardar varios minutos. El comando no usa /ResetBase.`n`n¿Continuar?"
        MsgOptDrive  = "Abre la herramienta nativa para verificar el TRIM (SSD) y desfragmentar.`n`n¿Abrir Optimizador de unidades?"
        MsgWinsock   = "Restablece el catálogo Winsock y elimina los proveedores de servicio por capas (LSP) personalizados. Puede afectar a algunos programas de red de terceros.`n⚠️ Requiere reiniciar el equipo.`n`n¿Ejecutar el restablecimiento?"
        MsgIpReset   = "Restablece el protocolo TCP/IP a su estado predeterminado.`n⚠️ Puede borrar la configuración de IP estática.`n⚠️ Requiere reiniciar el equipo.`n`n¿Ejecutar el restablecimiento?"
        MsgFlushDns  = "Vacía la caché de resolución DNS local.`n⚡ No requiere reinicio.`n`n¿Vaciar la caché?"
        MsgSysInfo   = "Muestra información detallada sobre hardware y BIOS.`n`n¿Abrir Msinfo32?"
        MsgDevMgr    = "Muestra los dispositivos detectados y el estado de sus controladores. Permite actualizar controladores, deshabilitar dispositivos o desinstalarlos.`n`n¿Continuar?"
        MsgDiskMgr   = "Muestra y administra discos, volúmenes y particiones. Formatear o eliminar un volumen puede causar pérdida de datos.`n`n¿Continuar?"
        MsgDxDiag    = "Analiza componentes gráficos, audio y controladores DirectX.`n`n¿Iniciar DxDiag?"
        MsgMemDiag   = "Verifica los defectos físicos de la RAM (requiere reinicio).`n`n¿Abrir herramienta?"
        MsgEventVwr  = "Consulta los registros de eventos de Windows para localizar errores, advertencias y eventos recientes del sistema.`n`n¿Continuar?"
        MsgResMon    = "Abre el Monitor de recursos (CPU, RAM, Disco, Red en tiempo real).`n`n¿Abrir herramienta?"
        MsgPerfDiag  = "Genera un informe de rendimiento de 60 segundos en segundo plano.`n`n¿Iniciar análisis?"
        MsgReliability= "Muestra el historial de estabilidad de Windows, incluidos cierres inesperados de aplicaciones, errores del sistema y actualizaciones.`n`n¿Abrir Monitor de confiabilidad?"
        MsgMsConfig  = "Permite configurar las opciones de inicio de Windows y algunos servicios. Los cambios pueden impedir que se inicien servicios o aplicaciones.`n`n¿Abrir la herramienta?"
        MsgFirewall  = "Permite consultar y cambiar las reglas de entrada y salida del firewall. Un cambio puede bloquear una aplicación o conexión de red.`n`n¿Abrir Firewall?"
        MsgNetConn   = "Muestra los adaptadores de red y su configuración. Deshabilitar un adaptador o cambiar sus ajustes puede interrumpir la conexión.`n`n¿Continuar?"
        MsgMRT       = "Inicia la herramienta integrada de Windows para la eliminación de software malintencionado.`n`n¿Iniciar MRT?"
        MsgUserPass  = "Permite administrar cuentas de usuario y algunas opciones de inicio de sesión.`n`n¿Continuar?"
        MsgPower     = "Permite elegir un plan de energía y ajustar la suspensión o el apagado de la pantalla.`n`n¿Continuar?"
        MsgServices  = "Abre la consola de Servicios de Windows (iniciar/detener servicios).`n`n¿Continuar?"
        MsgCompMgmt  = "Abre Administración de equipos (discos, dispositivos, eventos, carpetas compartidas).`n`n¿Continuar?"
        LogStart     = "[INICIO] Iniciando herramienta nativa..."
        LogEnd       = "[FIN] Se cerró la ventana del Hub."
        SfcExtracted = "[INFO] Los detalles de esta ejecución de SFC se extrajeron en %LOGPATH%."
        SfcEmpty     = "[INFO] No se encontraron detalles de SFC para este análisis."
        SfcRunning   = "[INFO] SFC se inició en una consola independiente. El informe de este análisis se detectará al finalizar."
        ToolNotFound = "[ERROR] No se pudo iniciar la herramienta: %TOOL% no encontrado o inaccesible."
        AboutTitle   = "Acerca de"
        AboutBody    = "Hub de Mantenimiento de Windows`r`nTodas las herramientas de este hub están integradas nativamente en Windows.`r`n`r`nVersion 0.16.7`r`n`r`nOpen Source`r`nCreado con la ayuda de Google Gemini & Mistral Vibe.`r`nOS : Windows 10 & 11.`r`n2026/11"
    }
}

# Texte du point de restauration
$Translations.FR['BtnRestorePoint'] = "Créer un point de restauration"
$Translations.FR['MsgRestorePoint'] = "Créer maintenant un point de restauration système ?"
$Translations.FR['RestorePointCreated'] = "Point de restauration créé."
$Translations.FR['RestorePointFailed'] = "Windows n'a pas pu créer le point. La Protection du système est peut-être désactivée ou un point a déjà été créé dans les dernières 24 heures."
$Translations.FR['MsgContinueWithoutRestorePoint'] = "Le point de restauration n'a pas été créé. Voulez-vous continuer sans ce filet de sécurité ?"

$Translations.EN['BtnRestorePoint'] = "Create a restore point"
$Translations.EN['MsgRestorePoint'] = "Create a Windows system restore point now?"
$Translations.EN['RestorePointCreated'] = "Restore point created."
$Translations.EN['RestorePointFailed'] = "Windows could not create the restore point. System Protection may be disabled, or a point may already have been created in the last 24 hours."
$Translations.EN['MsgContinueWithoutRestorePoint'] = "The restore point was not created. Continue without this safeguard?"

$Translations.DE['BtnRestorePoint'] = "Wiederherstellungspunkt erstellen"
$Translations.DE['MsgRestorePoint'] = "Jetzt einen Windows-Systemwiederherstellungspunkt erstellen?"
$Translations.DE['RestorePointCreated'] = "Wiederherstellungspunkt erstellt."
$Translations.DE['RestorePointFailed'] = "Windows konnte den Wiederherstellungspunkt nicht erstellen. Der Computerschutz ist möglicherweise deaktiviert oder innerhalb der letzten 24 Stunden wurde bereits ein Punkt erstellt."
$Translations.DE['MsgContinueWithoutRestorePoint'] = "Der Wiederherstellungspunkt wurde nicht erstellt. Ohne diesen Schutz fortfahren?"

$Translations.IT['BtnRestorePoint'] = "Crea un punto di ripristino"
$Translations.IT['MsgRestorePoint'] = "Creare ora un punto di ripristino del sistema Windows?"
$Translations.IT['RestorePointCreated'] = "Punto di ripristino creato."
$Translations.IT['RestorePointFailed'] = "Windows non è riuscito a creare il punto. La Protezione sistema potrebbe essere disattivata oppure potrebbe essere già stato creato un punto nelle ultime 24 ore."
$Translations.IT['MsgContinueWithoutRestorePoint'] = "Il punto di ripristino non è stato creato. Continuare senza questa protezione?"

$Translations.ES['BtnRestorePoint'] = "Crear un punto de restauración"
$Translations.ES['MsgRestorePoint'] = "¿Crear ahora un punto de restauración del sistema de Windows?"
$Translations.ES['RestorePointCreated'] = "Punto de restauración creado."
$Translations.ES['RestorePointFailed'] = "Windows no pudo crear el punto. Es posible que Protección del sistema esté desactivada o que ya se haya creado un punto en las últimas 24 horas."
$Translations.ES['MsgContinueWithoutRestorePoint'] = "No se creó el punto de restauración. ¿Continuar sin esta protección?"

$Script:CurrentLang = $LaunchLang

# ----------------------------------------------------------------------
# 2. Création de la Fenêtre Principale & Boutons
# ----------------------------------------------------------------------
$Form = New-Object System.Windows.Forms.Form
$Form.Text = $Translations[$Script:CurrentLang].Title
$Form.Size = New-Object System.Drawing.Size(950, 720) #taille de la fenetre globale
$Form.MinimumSize = New-Object System.Drawing.Size(950, 720) #taille de la fenetre globale
$Form.StartPosition = "CenterScreen"
$Form.BackColor = [System.Drawing.Color]::FromArgb(243, 243, 243)
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$Form.MaximizeBox = $false

# --- Bandeau Supérieur ---
$LabelTitre = New-Object System.Windows.Forms.Label
$LabelTitre.Text = $Translations[$Script:CurrentLang].Header
$LabelTitre.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 14, [System.Drawing.FontStyle]::Bold)
$LabelTitre.Size = New-Object System.Drawing.Size(450, 30)
$LabelTitre.Location = New-Object System.Drawing.Point(20, 15)
$Form.Controls.Add($LabelTitre)

# --- Bouton "Langue" ---
$ComboLang = New-Object System.Windows.Forms.ComboBox
$ComboLang.Location = New-Object System.Drawing.Point(660, 17)
$ComboLang.Size = New-Object System.Drawing.Size(100, 30)
$ComboLang.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$ComboLang.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::Bold)
[void]$ComboLang.Items.AddRange(@("EN", "FR", "DE", "IT", "ES"))
$ComboLang.SelectedItem = $Script:CurrentLang
$Form.Controls.Add($ComboLang)

# --- Bouton "About" ---
$BtnAbout = New-Object System.Windows.Forms.Button
$BtnAbout.Text = "?"
$BtnAbout.Location = New-Object System.Drawing.Point(770, 16)
$BtnAbout.Size = New-Object System.Drawing.Size(30, 25)
$BtnAbout.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::Bold)
$BtnAbout.FlatStyle = "Flat"
$BtnAbout.FlatAppearance.BorderSize = 1
$BtnAbout.BackColor = [System.Drawing.Color]::White
$Form.Controls.Add($BtnAbout)

# --- SplitContainer --- fenêtre noire/dos
$SplitContainer = New-Object System.Windows.Forms.SplitContainer
$SplitContainer.Orientation = [System.Windows.Forms.Orientation]::Horizontal
$SplitContainer.Location = New-Object System.Drawing.Point(20, 60)
$SplitContainer.Size = New-Object System.Drawing.Size(($Form.ClientSize.Width - 40), ($Form.ClientSize.Height - 80))
$SplitContainer.SplitterDistance = 430 #valeur haut
$SplitContainer.Panel1MinSize = 430
$SplitContainer.Panel2MinSize = 100
$SplitContainer.IsSplitterFixed = $true  # Bloque le déplacement de la barre
$Form.Controls.Add($SplitContainer)

# --- Onglets ---
$TabControl = New-Object System.Windows.Forms.TabControl
$TabControl.Alignment = "Top"
$TabControl.Multiline = $false 
$TabControl.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10)
$TabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$SplitContainer.Panel1.Controls.Add($TabControl)

$TabSys   = New-Object System.Windows.Forms.TabPage
$TabClean = New-Object System.Windows.Forms.TabPage
$TabDiag  = New-Object System.Windows.Forms.TabPage
$TabPerf  = New-Object System.Windows.Forms.TabPage
$TabNet   = New-Object System.Windows.Forms.TabPage
$TabAdv   = New-Object System.Windows.Forms.TabPage

$TabControl.TabPages.Add($TabSys)
$TabControl.TabPages.Add($TabClean)
$TabControl.TabPages.Add($TabDiag)
$TabControl.TabPages.Add($TabPerf)
$TabControl.TabPages.Add($TabNet)
$TabControl.TabPages.Add($TabAdv)

function Create-StackedTabButton {
    param ([System.Windows.Forms.TabPage]$ParentTab, [string]$Text, [int]$Index, [System.Drawing.Color]$BgColor)
    $Btn = New-Object System.Windows.Forms.Button
    $Btn.Text = $Text
    $Btn.Size = New-Object System.Drawing.Size(640, 45)
    $Y = 15 + ($Index * 55)
    $Btn.Location = New-Object System.Drawing.Point(20, $Y)
    $Btn.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::Bold)
    $Btn.FlatStyle = "Flat"
    $Btn.FlatAppearance.BorderSize = 0
    $Btn.BackColor = $BgColor
    $Btn.ForeColor = [System.Drawing.Color]::White
    $ParentTab.Controls.Add($Btn)
    $Btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    return $Btn
}

$C_Sys   = [System.Drawing.Color]::FromArgb(0, 120, 215)
$C_Clean = [System.Drawing.Color]::FromArgb(16, 124, 65)
$C_Diag  = [System.Drawing.Color]::FromArgb(225, 112, 20)
$C_Perf  = [System.Drawing.Color]::FromArgb(114, 30, 149)
$C_Net   = [System.Drawing.Color]::FromArgb(0, 150, 200)
$C_Adv   = [System.Drawing.Color]::FromArgb(240, 200, 30)
$C_Log   = [System.Drawing.Color]::FromArgb(100, 100, 100)

# Group 1 - Système
$BtnScan = Create-StackedTabButton -ParentTab $TabSys -Text "" -Index 0 -BgColor $C_Sys
$BtnScan.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnScan.Enabled = $false }

$BtnRestore = Create-StackedTabButton -ParentTab $TabSys -Text "" -Index 1 -BgColor $C_Sys
$BtnRestore.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnRestore.Enabled = $false }

$BtnSfc = Create-StackedTabButton -ParentTab $TabSys -Text "" -Index 2 -BgColor $C_Sys
$BtnSfc.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnSfc.Enabled = $false }

$BtnSysRestore = Create-StackedTabButton -ParentTab $TabSys -Text "" -Index 3 -BgColor $C_Sys
$BtnSysRestore.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnSysRestore.Enabled = $false }

$BtnChkdsk = Create-StackedTabButton -ParentTab $TabSys -Text "" -Index 4 -BgColor $C_Sys
$BtnChkdsk.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnChkdsk.Enabled = $false }

# Bouton log SFC (Masqué par défaut)
$BtnViewSfcLog = Create-StackedTabButton -ParentTab $TabSys -Text "" -Index 5 -BgColor $C_Log
$BtnViewSfcLog.Visible = $false

$BtnRestorePoint = Create-StackedTabButton -ParentTab $TabSys -Text "" -Index 6 -BgColor $C_Log
$BtnRestorePoint.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)

# Group 2 - Nettoyage (3 boutons)
$BtnCleanMgr = Create-StackedTabButton -ParentTab $TabClean -Text "" -Index 0 -BgColor $C_Clean

$BtnWinClean = Create-StackedTabButton -ParentTab $TabClean -Text "" -Index 1 -BgColor $C_Clean
$BtnWinClean.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnWinClean.Enabled = $false }

$BtnOptDrive = Create-StackedTabButton -ParentTab $TabClean -Text "" -Index 2 -BgColor $C_Clean

# Group Réseau & Internet (4 boutons)
$BtnWinsock  = Create-StackedTabButton -ParentTab $TabNet -Text "" -Index 0 -BgColor $C_Net
$BtnWinsock.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnWinsock.Enabled = $false }

$BtnIpReset  = Create-StackedTabButton -ParentTab $TabNet -Text "" -Index 1 -BgColor $C_Net
$BtnIpReset.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnIpReset.Enabled = $false }

$BtnFlushDns = Create-StackedTabButton -ParentTab $TabNet -Text "" -Index 2 -BgColor $C_Net
$BtnNetConn  = Create-StackedTabButton -ParentTab $TabNet -Text "" -Index 3 -BgColor $C_Net

# Group 3 - Diagnostics (5 boutons)
$BtnSysInfo  = Create-StackedTabButton -ParentTab $TabDiag -Text "" -Index 0 -BgColor $C_Diag
$BtnDevMgr   = Create-StackedTabButton -ParentTab $TabDiag -Text "" -Index 1 -BgColor $C_Diag
$BtnDiskMgr  = Create-StackedTabButton -ParentTab $TabDiag -Text "" -Index 2 -BgColor $C_Diag
if (-not $IsAdmin) { $BtnDiskMgr.Enabled = $false }
$BtnDxDiag   = Create-StackedTabButton -ParentTab $TabDiag -Text "" -Index 3 -BgColor $C_Diag

$BtnMemDiag  = Create-StackedTabButton -ParentTab $TabDiag -Text "" -Index 4 -BgColor $C_Diag
$BtnMemDiag.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnMemDiag.Enabled = $false }

# Group 4 - Performances (5 boutons)
$BtnEventVwr = Create-StackedTabButton -ParentTab $TabPerf -Text "" -Index 0 -BgColor $C_Perf

$BtnResMon   = Create-StackedTabButton -ParentTab $TabPerf -Text "" -Index 1 -BgColor $C_Perf
$BtnResMon.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnResMon.Enabled = $false }

$BtnPerfDiag = Create-StackedTabButton -ParentTab $TabPerf -Text "" -Index 2 -BgColor $C_Perf
$BtnPerfDiag.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnPerfDiag.Enabled = $false }

$BtnReliability = Create-StackedTabButton -ParentTab $TabPerf -Text "" -Index 3 -BgColor $C_Perf

$BtnMsConfig = Create-StackedTabButton -ParentTab $TabPerf -Text "" -Index 4 -BgColor $C_Perf
$BtnMsConfig.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnMsConfig.Enabled = $false }

# Group 5 - Avancés (6 boutons)
$BtnFirewall = Create-StackedTabButton -ParentTab $TabAdv -Text "" -Index 0 -BgColor $C_Adv
$BtnFirewall.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnFirewall.Enabled = $false }

$BtnServices = Create-StackedTabButton -ParentTab $TabAdv -Text "" -Index 1 -BgColor $C_Adv
$BtnServices.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnServices.Enabled = $false }

$BtnCompMgmt = Create-StackedTabButton -ParentTab $TabAdv -Text "" -Index 2 -BgColor $C_Adv
$BtnCompMgmt.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnCompMgmt.Enabled = $false }

$BtnMRT      = Create-StackedTabButton -ParentTab $TabAdv -Text "" -Index 3 -BgColor $C_Adv
$BtnMRT.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnMRT.Enabled = $false }

$BtnUserPass = Create-StackedTabButton -ParentTab $TabAdv -Text "" -Index 4 -BgColor $C_Adv
$BtnUserPass.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 10, [System.Drawing.FontStyle]::bold)
if (-not $IsAdmin) { $BtnUserPass.Enabled = $false }

$BtnPower    = Create-StackedTabButton -ParentTab $TabAdv -Text "" -Index 5 -BgColor $C_Adv

foreach($tab in $TabControl.TabPages) {
    foreach($ctl in $tab.Controls) {
        if ($ctl -is [System.Windows.Forms.Button]) {
            $ctl.Width = $Form.ClientSize.Width - 80
        }
    }
}

# Journal intégré ; les outils système s'ouvrent dans leurs propres fenêtres.
$TxtOutput = New-Object System.Windows.Forms.TextBox
$TxtOutput.Multiline = $true
$TxtOutput.ScrollBars = "Vertical"
$TxtOutput.Font = New-Object System.Drawing.Font("Consolas", 10)
$TxtOutput.BackColor = [System.Drawing.Color]::Black
$TxtOutput.ForeColor = [System.Drawing.Color]::Lime
$TxtOutput.ReadOnly = $true
$TxtOutput.Dock = [System.Windows.Forms.DockStyle]::Fill
$SplitContainer.Panel2.Controls.Add($TxtOutput)

# ----------------------------------------------------------------------
# 3. Logique d'actualisation de la Traduction
# ----------------------------------------------------------------------
function Update-InterfaceLanguage {
    $L = $Translations[$Script:CurrentLang]
    $Form.Text             = $L.Title
    $LabelTitre.Text       = $L.Header
    if ($IsAdmin) {
        $Form.Text += " [ADMIN]"
    } else {
        $Form.Text += " [USER]"
    }

    $TabSys.Text           = $L.TabSystem
    $TabClean.Text         = $L.TabClean
    $TabDiag.Text          = $L.TabDiag
    $TabPerf.Text          = $L.TabPerf
    $TabNet.Text           = $L.TabNet
    $TabAdv.Text           = $L.TabAdv

    $BtnScan.Text          = $L.BtnScan + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnRestore.Text       = $L.BtnRestore + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnSfc.Text           = $L.BtnSfc + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnSysRestore.Text    = $L.BtnSysRestore + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnChkdsk.Text        = $L.BtnChkdsk + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnViewSfcLog.Text    = $L.BtnSfcLog
    $BtnRestorePoint.Text  = $L.BtnRestorePoint
    
    $BtnCleanMgr.Text      = $L.BtnCleanMgr
    $BtnWinClean.Text      = $L.BtnWinClean + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnOptDrive.Text      = $L.BtnOptDrive
    
    $BtnWinsock.Text       = $L.BtnWinsock + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnIpReset.Text       = $L.BtnIpReset + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnFlushDns.Text      = $L.BtnFlushDns
    
    $BtnSysInfo.Text       = $L.BtnSysInfo
    $BtnDevMgr.Text        = $L.BtnDevMgr
    $BtnDiskMgr.Text       = $L.BtnDiskMgr + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnDxDiag.Text        = $L.BtnDxDiag
    $BtnMemDiag.Text       = $L.BtnMemDiag + " $($L.MemDiagHint)" + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    
    $BtnEventVwr.Text      = $L.BtnEventVwr
    $BtnResMon.Text        = $L.BtnResMon + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnPerfDiag.Text      = $L.BtnPerfDiag + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnReliability.Text   = $L.BtnReliability
    $BtnMsConfig.Text      = $L.BtnMsConfig + $(if (-not $IsAdmin) { " 🔒" } else { "" })

    $BtnFirewall.Text      = $L.BtnFirewall + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnServices.Text      = $L.BtnServices + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnCompMgmt.Text      = $L.BtnCompMgmt + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnNetConn.Text       = $L.BtnNetConn
    $BtnMRT.Text           = $L.BtnMRT + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnUserPass.Text      = $L.BtnUserPass + $(if (-not $IsAdmin) { " 🔒" } else { "" })
    $BtnPower.Text         = $L.BtnPower
}

Update-InterfaceLanguage

$ComboLang.Add_SelectedIndexChanged({
    $Script:CurrentLang = $ComboLang.SelectedItem.ToString()
    Update-InterfaceLanguage
})

# ----------------------------------------------------------------------
# 4. Helpers Fonctionnels & Exécution
# ----------------------------------------------------------------------
function Confirm-Action { 
    param ([string]$Message) 
    $L = $Translations[$Script:CurrentLang]
    $Result = [System.Windows.Forms.MessageBox]::Show($Message, $L.ConfTitle, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    return ($Result -eq [System.Windows.Forms.DialogResult]::Yes) 
}

function Write-Log {
    param ([string]$Message)
    if ($TxtOutput -and -not $TxtOutput.IsDisposed) {
        $TxtOutput.AppendText("`r`n$Message`r`n")
    }
}

function New-SystemRestorePoint {
    $WindowsPowerShell = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $WindowsPowerShell)) { return 'Failed' }

    $Description = 'Windows Maintenance Hub - {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')
    $RestoreCommand = "try { Checkpoint-Computer -Description '$Description' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; exit 0 } catch { exit 1 }"
    $EncodedRestoreCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($RestoreCommand))

    try {
        $StartParameters = @{
            FilePath = $WindowsPowerShell
            ArgumentList = "-NoProfile -NonInteractive -EncodedCommand $EncodedRestoreCommand"
            WindowStyle = 'Hidden'
            Wait = $true
            PassThru = $true
            ErrorAction = 'Stop'
        }
        if (-not $IsAdmin) { $StartParameters.Verb = 'RunAs' }
        $RestoreProcess = Start-Process @StartParameters
        if ($RestoreProcess.ExitCode -eq 0) { return 'Created' }
        return 'Failed'
    } catch {
        if ($_.Exception.NativeErrorCode -eq 1223) { return 'Cancelled' }
        return 'Failed'
    }
}

function Confirm-ActionWithRestorePoint {
    param ([string]$Message)
    if (-not (Confirm-Action $Message)) { return $false }

    $L = $Translations[$Script:CurrentLang]
    $RestoreResult = New-SystemRestorePoint
    if ($RestoreResult -eq 'Created') {
        Write-Log $L.RestorePointCreated
        return $true
    }
    if ($RestoreResult -eq 'Cancelled') { return $false }

    $Result = [System.Windows.Forms.MessageBox]::Show(
        ($L.RestorePointFailed + "`n`n" + $L.MsgContinueWithoutRestorePoint),
        $L.ConfTitle,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    return ($Result -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Resolve-SystemToolPath {
    param ([string]$Tool)
    # Correction spécifique pour powershell.exe situé dans le sous-dossier v1.0
    if ($Tool -eq 'powershell.exe') {
        $psPath = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (Test-Path -LiteralPath $psPath) { return $psPath }
    }
    $sys32 = Join-Path $env:windir "System32\$Tool"
    if (Test-Path -LiteralPath $sys32) { return $sys32 }
    return $null
}

function Invoke-NativeTool { 
    param ([string]$Command, [string]$Arguments) 
    $L = $Translations[$Script:CurrentLang]
    
    try {
        $fileName = $Command
        $fileArgs = $Arguments

        if ($Command -like '*.msc') {
            $mscPath = Resolve-SystemToolPath -Tool $Command
            if (-not $mscPath) { throw "Console MMC introuvable dans System32 : $Command" }
            $fileName = Resolve-SystemToolPath -Tool 'mmc.exe'
            if (-not $fileName) { throw 'mmc.exe introuvable dans System32.' }
            $fileArgs = "`"$mscPath`""
            if ($Arguments) { $fileArgs += " $Arguments" }
        }
        elseif ($Command -like '*.cpl') {
            $cplPath = Resolve-SystemToolPath -Tool $Command
            if (-not $cplPath) { throw "Applet .cpl introuvable dans System32 : $Command" }
            $fileName = Resolve-SystemToolPath -Tool 'control.exe'
            if (-not $fileName) { throw 'control.exe introuvable dans System32.' }
            $fileArgs = "`"$cplPath`""
            if ($Arguments) { $fileArgs += " $Arguments" }
        }
        else {
            $fileName = Resolve-SystemToolPath -Tool $Command
        }

        if (-not $fileName) {
            throw "Outil Windows introuvable dans System32 : $Command"
        }

        $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $StartInfo.FileName = $fileName
        if ($fileArgs) { $StartInfo.Arguments = $fileArgs }
        $StartInfo.UseShellExecute = $true 
        
        [void][System.Diagnostics.Process]::Start($StartInfo)
        Write-Log "$($L.LogStart) $Command $Arguments"
    }
    catch {
        $errMsg = $L.ToolNotFound -replace '%TOOL%', $Command
        Write-Log $errMsg
    }
}

# ----------------------------------------------------------------------
# 5. Gestion des Événements Clics
# ----------------------------------------------------------------------
$BtnScan.Add_Click({ 
    if (Confirm-Action $Translations[$Script:CurrentLang].MsgScan) { 
        Invoke-NativeTool "powershell.exe" "-NoProfile -NoExit -Command `"$ConsoleSetup DISM.exe /Online /Cleanup-Image /ScanHealth`"" 
    } 
})

$BtnRestore.Add_Click({ 
    if (Confirm-ActionWithRestorePoint $Translations[$Script:CurrentLang].MsgRestore) { 
        Invoke-NativeTool "powershell.exe" "-NoProfile -NoExit -Command `"$ConsoleSetup DISM.exe /Online /Cleanup-image /Restorehealth`"" 
    } 
})

$Script:SfcTimer = New-Object System.Windows.Forms.Timer
$Script:SfcTimer.Interval = 1000
$Script:SfcTimer.Add_Tick({
    if ($Script:SfcProc -and $Script:SfcProc.HasExited) {
        $Script:SfcTimer.Stop()
        $BtnSfc.Enabled = $true
        Remove-Item Env:\WMH_SFC_REPORT_PATH -ErrorAction SilentlyContinue
        if ((Test-Path -LiteralPath $Script:SfcReportPath) -and ((Get-Item -LiteralPath $Script:SfcReportPath).Length -gt 0)) {
            $BtnViewSfcLog.Visible = $true
            $L = $Translations[$Script:CurrentLang]
            Write-Log ($L.SfcExtracted -replace '%LOGPATH%', $Script:SfcReportPath)
        } else {
            Write-Log $Translations[$Script:CurrentLang].SfcEmpty
        }
        $Script:SfcProc = $null
    }
})

$BtnSfc.Add_Click({ 
    $BtnViewSfcLog.Visible = $false

    if (Confirm-ActionWithRestorePoint $Translations[$Script:CurrentLang].MsgSfc) { 
        $L = $Translations[$Script:CurrentLang]
        $Script:SfcReportPath = Join-Path $env:TEMP ("WindowsMaintenanceHub_SFC_{0}.txt" -f [guid]::NewGuid().ToString('N'))
        $env:WMH_SFC_REPORT_PATH = $Script:SfcReportPath

        $SfcCmd = "$ConsoleSetup " +
                  "`$StartTime = [datetime]::ParseExact((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture); " +
                  "sfc.exe /scannow; " +
                  "`$LogPath = `$env:WMH_SFC_REPORT_PATH; " +
                  "if (Test-Path `"`$env:windir`\Logs`\CBS`\CBS.log`") { " +
                  "  try { Select-String -LiteralPath `"`$env:windir`\Logs`\CBS`\CBS.log`" -Pattern '\[SR\]' -ErrorAction Stop | " +
                  "    Where-Object { if (`$_.Line -match '^(?<Timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { " +
                  "      [datetime]::ParseExact(`$Matches.Timestamp, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) -ge `$StartTime " +
                  "    } else { `$false } } | ForEach-Object { `$_.Line } | Set-Content -LiteralPath `$LogPath -Encoding UTF8 " +
                  "  } catch { } " +
                  "}"
        
        try {
            $BtnSfc.Enabled = $false
            $SfcPowerShell = Resolve-SystemToolPath -Tool 'powershell.exe'
            $SfcEncodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($SfcCmd))
            $Script:SfcProc = Start-Process -FilePath $SfcPowerShell -ArgumentList "-NoProfile -EncodedCommand $SfcEncodedCommand" -PassThru -ErrorAction Stop
            Write-Log $L.SfcRunning
            $Script:SfcTimer.Start()
        } catch {
            $BtnSfc.Enabled = $true
            Remove-Item Env:\WMH_SFC_REPORT_PATH -ErrorAction SilentlyContinue
            $SfcError = $L.ToolNotFound -replace '%TOOL%', 'SFC / PowerShell'
            Write-Log $SfcError
        }
    } 
})

$BtnViewSfcLog.Add_Click({ 
    if (Test-Path -LiteralPath $Script:SfcReportPath) {
        Invoke-NativeTool "notepad.exe" "`"$Script:SfcReportPath`""
    } else {
        Write-Log $Translations[$Script:CurrentLang].SfcEmpty
    }
})

$BtnWinClean.Add_Click({ 
    if (Confirm-ActionWithRestorePoint $Translations[$Script:CurrentLang].MsgWinClean) { 
        Invoke-NativeTool "powershell.exe" "-NoProfile -NoExit -Command `"$ConsoleSetup DISM.exe /Online /Cleanup-Image /StartComponentCleanup`"" 
    } 
})

$BtnChkdsk.Add_Click({ 
    if (Confirm-Action $Translations[$Script:CurrentLang].MsgChkdsk) { 
        Invoke-NativeTool "powershell.exe" "-NoProfile -NoExit -Command `"$ConsoleSetup chkdsk.exe C:`"" 
    } 
})

$BtnWinsock.Add_Click({ 
    if (Confirm-ActionWithRestorePoint $Translations[$Script:CurrentLang].MsgWinsock) { 
        Invoke-NativeTool "powershell.exe" "-NoProfile -NoExit -Command `"$ConsoleSetup netsh winsock reset`"" 
    } 
})

$BtnIpReset.Add_Click({ 
    if (Confirm-ActionWithRestorePoint $Translations[$Script:CurrentLang].MsgIpReset) { 
        Invoke-NativeTool "powershell.exe" "-NoProfile -NoExit -Command `"$ConsoleSetup netsh int ip reset`"" 
    } 
})

$BtnFlushDns.Add_Click({ 
    if (Confirm-Action $Translations[$Script:CurrentLang].MsgFlushDns) { 
        Invoke-NativeTool "powershell.exe" "-NoProfile -NoExit -Command `"$ConsoleSetup ipconfig /flushdns`"" 
    } 
})

# Outils natifs système Windows
$BtnSysRestore.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgSysRestore) { Invoke-NativeTool "SystemPropertiesProtection.exe" "" } })
$BtnRestorePoint.Add_Click({
    $L = $Translations[$Script:CurrentLang]
    if (Confirm-Action $L.MsgRestorePoint) {
        $RestoreResult = New-SystemRestorePoint
        if ($RestoreResult -eq 'Created') {
            Write-Log $L.RestorePointCreated
        } elseif ($RestoreResult -eq 'Failed') {
            [void][System.Windows.Forms.MessageBox]::Show($L.RestorePointFailed, $L.ConfTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }
})
$BtnCleanMgr.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgCleanMgr) { Invoke-NativeTool "cleanmgr.exe" "" } })

$BtnOptDrive.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgOptDrive) { Invoke-NativeTool "dfrgui.exe" "" } })
$BtnSysInfo.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgSysInfo) { Invoke-NativeTool "msinfo32.exe" "" } })
$BtnDevMgr.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgDevMgr) { Invoke-NativeTool "devmgmt.msc" "" } })
$BtnDiskMgr.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgDiskMgr) { Invoke-NativeTool "diskmgmt.msc" "" } })
$BtnDxDiag.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgDxDiag) { Invoke-NativeTool "dxdiag.exe" "" } })
$BtnMemDiag.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgMemDiag) { Invoke-NativeTool "mdsched.exe" "" } })
$BtnEventVwr.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgEventVwr) { Invoke-NativeTool "eventvwr.msc" "" } })
$BtnResMon.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgResMon) { Invoke-NativeTool "resmon.exe" "" } })
$BtnPerfDiag.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgPerfDiag) { Invoke-NativeTool "perfmon.exe" "/report" } })
$BtnReliability.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgReliability) { Invoke-NativeTool "perfmon.exe" "/rel" } })
$BtnMsConfig.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgMsConfig) { Invoke-NativeTool "msconfig.exe" "" } })
$BtnFirewall.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgFirewall) { Invoke-NativeTool "wf.msc" "" } })
$BtnNetConn.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgNetConn) { Invoke-NativeTool "ncpa.cpl" "" } })

$BtnServices.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgServices) { Invoke-NativeTool "services.msc" "" } })
$BtnCompMgmt.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgCompMgmt) { Invoke-NativeTool "compmgmt.msc" "" } })

$BtnMRT.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgMRT) { Invoke-NativeTool "mrt.exe" "" } })
$BtnUserPass.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgUserPass) { Invoke-NativeTool "netplwiz.exe" "" } })
$BtnPower.Add_Click({ if (Confirm-Action $Translations[$Script:CurrentLang].MsgPower) { Invoke-NativeTool "control.exe" "powercfg.cpl" } })

# --- BOUTON ABOUT ---
$BtnAbout.Add_Click({
    $L = $Translations[$Script:CurrentLang]
    [System.Windows.Forms.MessageBox]::Show($L.AboutBody, $L.AboutTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::None)
})

# Nettoyage à la fermeture (log de session)
$Form.Add_FormClosing({
    $L = $Translations[$Script:CurrentLang]
    Write-Log $L.LogEnd
})

# Onglet sélectionné par défaut à l'ouverture
$TabControl.SelectedTab = $TabDiag

Write-StartupLog "UI initialized; IsAdmin=$IsAdmin; language=$Script:CurrentLang"
[void]$Form.ShowDialog()
Write-StartupLog 'Main window closed normally.'
