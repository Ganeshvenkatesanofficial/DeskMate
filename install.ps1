# ==============================================================================
# DeskMate Windows 1-Line Installer (Open-Source Edition)
# Installs DeskMate to %LOCALAPPDATA%\DeskMate and launches automatically.
# ==============================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "         DeskMate Windows Auto-Installer                " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 1. Terminate running DeskMate processes
Write-Host "Checking for running DeskMate processes..."
Get-Process -Name "DeskMate", "deskmate_backend" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 2. Installation Target Directory
$TargetDir = Join-Path $env:LOCALAPPDATA "DeskMate"
$TempZip = Join-Path $env:TEMP "DeskMate-Windows.zip"
$ExtractTemp = Join-Path $env:TEMP "DeskMate_Extract_Temp"

$Repo = "Ganeshvenkatesanofficial/DeskMate"
$ReleaseUrls = @(
    "https://github.com/$Repo/releases/download/continuous/DeskMate-Windows.zip",
    "https://github.com/$Repo/releases/latest/download/DeskMate-Windows.zip"
)

# 3. Download Release
$Downloaded = $false
foreach ($url in $ReleaseUrls) {
    try {
        Write-Host "Downloading DeskMate from $url ..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $TempZip -UseBasicParsing
        if ((Test-Path $TempZip) -and ((Get-Item $TempZip).Length -gt 100000)) {
            Write-Host "Download successful!" -ForegroundColor Green
            $Downloaded = $true
            break
        }
    } catch {
        Write-Host "Notice: Could not download from $url" -ForegroundColor Yellow
    }
}

if (-not $Downloaded) {
    # Check if user already downloaded it to ~/Downloads
    $Candidate = Join-Path $HOME "Downloads\DeskMate-Windows.zip"
    if (Test-Path $Candidate) {
        Write-Host "Found DeskMate-Windows.zip in Downloads folder!" -ForegroundColor Green
        Copy-Item $Candidate -Destination $TempZip -Force
        $Downloaded = $true
    }
}

if (-not $Downloaded) {
    Write-Error "Failed to download DeskMate-Windows.zip. Please download it manually from https://github.com/$Repo/releases"
    exit 1
}

# 4. Extract Package
Write-Host "Extracting DeskMate package..."
if (Test-Path $ExtractTemp) { Remove-Item $ExtractTemp -Recurse -Force }
Expand-Archive -Path $TempZip -DestinationPath $ExtractTemp -Force

# Locate DeskMate.exe in extracted contents
$ExeCandidate = Get-ChildItem -Path $ExtractTemp -Filter "DeskMate.exe" -Recurse | Select-Object -First 1

if (-not $ExeCandidate) {
    Write-Error "DeskMate.exe not found in extracted archive."
    exit 1
}

$SourceFolder = $ExeCandidate.DirectoryName

# 5. Install to LocalAppData
Write-Host "Installing DeskMate to $TargetDir ..."
if (Test-Path $TargetDir) {
    Remove-Item $TargetDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
Copy-Item -Path "$SourceFolder\*" -Destination $TargetDir -Recurse -Force

# Clean up temporary files
Remove-Item $TempZip -Force -ErrorAction SilentlyContinue
Remove-Item $ExtractTemp -Recurse -Force -ErrorAction SilentlyContinue

# 6. Create Desktop & Start Menu Shortcuts
try {
    $WshShell = New-Object -ComObject WScript.Shell
    
    # Desktop Shortcut
    $DesktopPath = [Environment]::GetFolderPath('Desktop')
    $Shortcut = $WshShell.CreateShortcut((Join-Path $DesktopPath "DeskMate.lnk"))
    $Shortcut.TargetPath = (Join-Path $TargetDir "DeskMate.exe")
    $Shortcut.WorkingDirectory = $TargetDir
    $Shortcut.Save()
    
    # Start Menu Shortcut
    $ProgramsPath = [Environment]::GetFolderPath('Programs')
    $StartShortcut = $WshShell.CreateShortcut((Join-Path $ProgramsPath "DeskMate.lnk"))
    $StartShortcut.TargetPath = (Join-Path $TargetDir "DeskMate.exe")
    $StartShortcut.WorkingDirectory = $TargetDir
    $StartShortcut.Save()
    Write-Host "Created Desktop and Start Menu shortcuts." -ForegroundColor Green
} catch {
    Write-Host "Notice: Shortcut creation skipped." -ForegroundColor Yellow
}

# 7. Launch DeskMate
$InstalledExe = Join-Path $TargetDir "DeskMate.exe"
Write-Host "DeskMate installed successfully!" -ForegroundColor Green
Write-Host "Launching DeskMate..."
Start-Process -FilePath $InstalledExe

Write-Host "Done! DeskMate is now running." -ForegroundColor Cyan
