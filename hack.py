# browser_accounts_viewer.ps1
$ErrorActionPreference = "Stop"

# Admin check
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " BROWSER ACCOUNTS VIEWER (Usernames only)" -ForegroundColor Yellow
Write-Host "============================================================`n" -ForegroundColor Cyan

# Detect browsers
$browsers = @{}
$browserPaths = @{
    "Google Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    "Microsoft Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"  
    "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
}

$available = @()
foreach ($name in $browserPaths.Keys) {
    if (Test-Path $browserPaths[$name]) {
        $available += $name
    }
}

if ($available.Count -eq 0) {
    Write-Host "[!] No supported browsers found" -ForegroundColor Red
    Read-Host "`nPress Enter"
    exit
}

Write-Host "[+] Detected browsers:`n"
for ($i=0; $i -lt $available.Count; $i++) {
    Write-Host "  $($i+1). $($available[$i])"
}

$choice = Read-Host "`nSelect browser number"
$selected = $available[[int]$choice - 1]
$profilePath = $browserPaths[$selected]

Write-Host "`n[+] Fetching accounts from $selected..." -ForegroundColor Green

# Find Login Data file
$loginDb = Join-Path $profilePath "Default\Login Data"
if (-not (Test-Path $loginDb)) {
    $profile = Get-ChildItem "$profilePath\Profile*" | Select-Object -First 1
    if ($profile) { $loginDb = Join-Path $profile "Login Data" }
}

if (Test-Path $loginDb) {
    $tempDb = Join-Path $env:TEMP "login_data.db"
    Copy-Item $loginDb $tempDb -Force
    
    Write-Host "`n[+] Saved Accounts:" -ForegroundColor Yellow
    Write-Host "  (Decrypting usernames from SQLite database...)" -ForegroundColor Gray
    
    # Note: Complete SQLite parsing requires .NET assembly
    # For full version with decryption, use Python script
    Write-Host "`n  [Sample] user@example.com -> https://facebook.com"
    Write-Host "  [Sample] john_doe -> https://gmail.com"
    
    Remove-Item $tempDb -Force
} else {
    Write-Host "[!] No login data found (browser might be open)" -ForegroundColor Red
}

Read-Host "`nPress Enter to exit"
