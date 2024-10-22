# PowerShell Script to backup WSL Ansible files to Windows
# Ensure you run this script with appropriate permissions

# Configuration
$BackupRoot = C:\location\of\backup"
$WSL_User = "WSLUSername"
$WSL_Distro = "WSLname"
$SUDO_PASS = "WSLuserpassword?"

# Create backup directories
$Directories = @(
    "$BackupRoot\ansible_playbooks",
    "$BackupRoot\etc_ansible",
    "$BackupRoot\ssh"
)

# Create backup directories if they don't exist
foreach ($dir in $Directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force
        Write-Host "Created directory: $dir"
    }
}

# Function to execute WSL commands with sudo and handle errors
function Invoke-WSLCommand {
    param (
        [string]$Command,
        [bool]$UseSudo = $false
    )
    try {
        if ($UseSudo) {
            # Use expect-like behavior to handle sudo password prompt silently
            $Command = "echo '$SUDO_PASS' | sudo -S bash -c `$'" + $Command.Replace("'", "'\\''") + "' 2>/dev/null"
        }
        $output = wsl -d $WSL_Distro -u $WSL_User -- bash -c $Command
        return $output
    }
    catch {
        Write-Host "Error executing WSL command: $_"
        return $null
    }
}

# Function to copy files from WSL to Windows
function Copy-WSLToWindows {
    param (
        [string]$WSLPath,
        [string]$WindowsPath,
        [string]$Description,
        [bool]$RequireSudo = $false
    )
    
    Write-Host "Copying $Description from WSL path: $WSLPath to Windows path: $WindowsPath"
    
    try {
        # Create a temporary directory in the user's home directory
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $tempDirName = "backup_$timestamp"
        $userHome = Invoke-WSLCommand "echo `$HOME"
        $tempPath = "$userHome/$tempDirName"
        
        # Create temp directory
        Invoke-WSLCommand "mkdir -p $tempPath"
        
        if ($RequireSudo) {
            # Copy files with sudo and fix permissions
            Invoke-WSLCommand "cp -r $WSLPath/* $tempPath" $true
            Invoke-WSLCommand "chown -R $WSL_User : $WSL_User $tempPath" $true
        } else {
            # Regular copy
            Invoke-WSLCommand "cp -r $WSLPath/* $tempPath"
        }
        
        # Get Windows path and copy files
        $wslTempPath = wsl -d $WSL_Distro -u $WSL_User -- wslpath -w "$tempPath" 2>$null
        if (Test-Path $wslTempPath) {
            Copy-Item -Path "$wslTempPath\*" -Destination $WindowsPath -Recurse -Force
            Write-Host "Successfully copied $Description"
            
            # Cleanup
            Invoke-WSLCommand "rm -rf $tempPath"
            return $true
        } else {
            Write-Host "Failed to access WSL path: $wslTempPath"
            return $false
        }
    }
    catch {
        Write-Host "Error copying $Description`: $_"
        return $false
    }
}

# Verify WSL Distribution
Write-Host "Verifying WSL distribution..."
$wslDistros = wsl --list --verbose
Write-Host "Available WSL distributions:"
Write-Host $wslDistros

if ($wslDistros -notmatch $WSL_Distro) {
    Write-Host "Warning: Could not find exact match for '$WSL_Distro'. Available distributions are shown above."
    $WSL_Distro = Read-Host "Please enter the exact distribution name from the list above"
}

Write-Host "Starting Ansible backup from WSL to Windows..."

# Test WSL connectivity without showing sudo prompt
$wslTest = Invoke-WSLCommand "echo 'WSL Connection Test'"
if ($null -eq $wslTest) {
    Write-Error "Cannot connect to WSL. Please ensure WSL is running and the distribution '$WSL_Distro' exists."
    exit 1
}

# Test sudo access silently
$sudoTest = Invoke-WSLCommand "echo 'Sudo test'" $true
if ($null -eq $sudoTest) {
    Write-Error "Sudo authentication failed. Please check the provided password."
    exit 1
}

Write-Host "WSL connection and sudo access verified successfully."

# 1. Backup ansible_playbooks (including secrets.yml)
Write-Host "Backing up ansible playbooks..."
$result = Copy-WSLToWindows "/home/$WSL_User/ansible_playbooks" "$BackupRoot\ansible_playbooks" "Ansible playbooks"
if (-not $result) { Write-Host "Warning: Ansible playbooks backup may be incomplete" }

# 2. Backup /etc/ansible files
Write-Host "Backing up /etc/ansible configuration..."
$result = Copy-WSLToWindows "/etc/ansible" "$BackupRoot\etc_ansible" "Ansible configuration" $true
if (-not $result) { Write-Host "Warning: Ansible configuration backup may be incomplete" }

# 3. Backup SSH files
Write-Host "Backing up SSH files..."
$result = Copy-WSLToWindows "/home/$WSL_User/.ssh" "$BackupRoot\ssh" "SSH configuration"
if (-not $result) { Write-Host "Warning: SSH configuration backup may be incomplete" }

# Verify backup
Write-Host "`nVerifying backup contents..."
$backupCheck = @{
    "Ansible Playbooks" = "$BackupRoot\ansible_playbooks"
    "Etc Ansible" = "$BackupRoot\etc_ansible"
    "SSH Files" = "$BackupRoot\ssh"
}

foreach ($check in $backupCheck.GetEnumerator()) {
    Write-Host "`n$($check.Key):"
    if (Test-Path $check.Value) {
        Get-ChildItem $check.Value -Recurse | Select-Object FullName | ForEach-Object {
            Write-Host "  $($_.FullName)"
        }
    } else {
        Write-Host "  No files found in $($check.Value)"
    }
}

# Create backup manifest
$manifestPath = "$BackupRoot\backup_manifest.txt"
@"
Backup created on: $(Get-Date)
WSL Distribution: $WSL_Distro
WSL User: $WSL_User
Backup Location: $BackupRoot

Files backed up:
"@ | Out-File $manifestPath

Get-ChildItem $BackupRoot -Recurse | Select-Object FullName | Out-File $manifestPath -Append

Write-Host "`nBackup complete! Files are stored in $BackupRoot"
Write-Host "Backup manifest created at: $manifestPath"
Write-Host "Please verify the backup contents manually before proceeding with any system changes."
