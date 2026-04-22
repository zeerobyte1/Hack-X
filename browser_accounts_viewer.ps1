# browser_accounts_viewer.ps1
# Educational Purpose Only - View your own saved browser accounts

# Check and request admin permissions
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Function to decrypt Chrome passwords using Windows API
function Decrypt-ChromePassword {
    param([byte[]]$EncryptedData)
    
    try {
        Add-Type -AssemblyName System.Security
        $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect($EncryptedData, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($decrypted)
    }
    catch {
        return "[Encrypted - Cannot Decrypt]"
    }
}

# Function to read Chrome/Edge/Brave login database
function Get-BrowserLogins {
    param(
        [string]$BrowserName,
        [string]$ProfilePath
    )
    
    $loginDbPath = Join-Path $ProfilePath "Default\Login Data"
    
    # Find profile if not in Default
    if (-not (Test-Path $loginDbPath)) {
        $profiles = Get-ChildItem "$ProfilePath\Profile*" -Directory -ErrorAction SilentlyContinue
        foreach ($profile in $profiles) {
            $testPath = Join-Path $profile.FullName "Login Data"
            if (Test-Path $testPath) {
                $loginDbPath = $testPath
                break
            }
        }
    }
    
    if (-not (Test-Path $loginDbPath)) {
        Write-Host "  No login data found for $BrowserName" -ForegroundColor Gray
        return @()
    }
    
    # Copy database to temp location (browser locks it)
    $tempDb = Join-Path $env:TEMP "login_data_$([System.Guid]::NewGuid().Guid).db"
    Copy-Item $loginDbPath $tempDb -Force
    
    # Read SQLite database using .NET
    $accounts = @()
    try {
        # Load SQLite assembly (download if needed)
        $sqlitePath = "$env:TEMP\System.Data.SQLite.dll"
        if (-not (Test-Path $sqlitePath)) {
            Write-Host "  Downloading SQLite support..." -ForegroundColor Gray
            Invoke-WebRequest -Uri "https://sqlite.org/2023/sqlite-dll-win64-x64-3440000.zip" -OutFile "$env:TEMP\sqlite.zip" -UseBasicParsing
            Expand-Archive -Path "$env:TEMP\sqlite.zip" -DestinationPath "$env:TEMP\" -Force
            Move-Item "$env:TEMP\sqlite3.dll" "$env:TEMP\System.Data.SQLite.dll" -Force
        }
        
        Add-Type -Path "$env:TEMP\System.Data.SQLite.dll" -ErrorAction SilentlyContinue
        
        $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tempDb")
        $conn.Open()
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT origin_url, username_value, password_value FROM logins WHERE username_value != ''"
        $reader = $cmd.ExecuteReader()
        
        while ($reader.Read()) {
            $url = $reader.GetString(0)
            $username = $reader.GetString(1)
            
            # Get encrypted password
            $passwordBytes = $null
            try {
                $passwordBytes = $reader.GetValue(2)
                if ($passwordBytes -is [byte[]]) {
                    $password = Decrypt-ChromePassword -EncryptedData $passwordBytes
                } else {
                    $password = "[No password]"
                }
            }
            catch {
                $password = "[Encrypted - Need master key]"
            }
            
            $accounts += [PSCustomObject]@{
                URL = $url
                Username = $username
                Password = $password
            }
        }
        
        $reader.Close()
        $conn.Close()
    }
    catch {
        Write-Host "  Error reading database: $_" -ForegroundColor Red
    }
    finally {
        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
    }
    
    return $accounts
}

# Detect installed browsers
function Get-InstalledBrowsers {
    $browsers = @{}
    
    $browserPaths = @{
        "Google Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        "Microsoft Edge" = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        "Brave" = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    }
    
    foreach ($name in $browserPaths.Keys) {
        if (Test-Path $browserPaths[$name]) {
            $browsers[$name] = $browserPaths[$name]
        }
    }
    
    return $browsers
}

# Main menu
Clear-Host
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host "     BROWSER ACCOUNTS VIEWER - Educational Purpose Only" -ForegroundColor Yellow
Write-Host "="*70 -ForegroundColor Cyan
Write-Host "  Shows saved usernames, passwords, and website links`n" -ForegroundColor Gray

# Get browsers
$browsers = Get-InstalledBrowsers

if ($browsers.Count -eq 0) {
    Write-Host "[!] No supported browsers found on this system." -ForegroundColor Red
    Write-Host "    Supported: Chrome, Edge, Brave" -ForegroundColor Gray
    Read-Host "`nPress Enter to exit"
    exit
}

Write-Host "[+] Detected browsers:`n" -ForegroundColor Green
$browserList = @($browsers.Keys)
for ($i = 0; $i -lt $browserList.Count; $i++) {
    Write-Host "  $($i+1). $($browserList[$i])" -ForegroundColor White
}

# User selection
$choice = Read-Host "`nSelect browser number"
$index = [int]$choice - 1
if ($index -lt 0 -or $index -ge $browserList.Count) {
    Write-Host "Invalid choice!" -ForegroundColor Red
    Read-Host "Press Enter"
    exit
}

$selectedBrowser = $browserList[$index]
$profilePath = $browsers[$selectedBrowser]

Write-Host "`n[+] Fetching accounts from $selectedBrowser..." -ForegroundColor Yellow
Write-Host "    (Make sure browser is closed for best results)`n" -ForegroundColor Gray

# Get accounts
$accounts = Get-BrowserLogins -BrowserName $selectedBrowser -ProfilePath $profilePath

# Display accounts
if ($accounts.Count -eq 0) {
    Write-Host "[!] No saved accounts found." -ForegroundColor Red
    Write-Host "    Possible reasons:" -ForegroundColor Gray
    Write-Host "    - Browser is still running (close it and try again)" -ForegroundColor Gray
    Write-Host "    - No saved logins in this browser" -ForegroundColor Gray
    Write-Host "    - Database is encrypted with Windows master key" -ForegroundColor Gray
} else {
    Write-Host "[+] Saved Accounts ($($accounts.Count) found):`n" -ForegroundColor Green
    Write-Host "-"*70
    
    for ($i = 0; $i -lt $accounts.Count; $i++) {
        $acc = $accounts[$i]
        Write-Host "`n [$($i+1)] Website  : $($acc.URL)" -ForegroundColor Cyan
        Write-Host "     Username : $($acc.Username)" -ForegroundColor Yellow
        Write-Host "     Password : $($acc.Password)" -ForegroundColor Green
    }
    Write-Host "`n" + "-"*70
}

Write-Host "`n" + "="*70 -ForegroundColor Gray
Write-Host " NOTE: This tool is for EDUCATIONAL purposes only." -ForegroundColor Red
Write-Host "       Use only on your own system with permission." -ForegroundColor Red
Write-Host "="*70 -ForegroundColor Gray

Read-Host "`nPress Enter to exit"
