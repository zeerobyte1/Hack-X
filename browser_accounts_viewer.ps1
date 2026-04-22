# browser_accounts_viewer.ps1
# Educational Purpose Only - College Project
# Works without any external DLL downloads

# --------------------------------------------
# ADMIN PERMISSION CHECK
# --------------------------------------------
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "`n[!] Requesting Administrator privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Clear-Host
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host "        BROWSER ACCOUNTS VIEWER - College Project" -ForegroundColor Yellow
Write-Host "                     Educational Purpose Only" -ForegroundColor White
Write-Host "="*70 -ForegroundColor Cyan

# --------------------------------------------
# DETECT INSTALLED BROWSERS
# --------------------------------------------
function Get-InstalledBrowsers {
    $browsers = @{}
    
    # Check Chrome
    $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    if (Test-Path $chromePath) {
        $browsers["Google Chrome"] = $chromePath
    }
    
    # Check Edge
    $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (Test-Path $edgePath) {
        $browsers["Microsoft Edge"] = $edgePath
    }
    
    # Check Brave
    $bravePath = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    if (Test-Path $bravePath) {
        $browsers["Brave"] = $bravePath
    }
    
    # Check Opera
    $operaPath = "$env:APPDATA\Opera Software\Opera Stable"
    if (Test-Path $operaPath) {
        $browsers["Opera"] = $operaPath
    }
    
    return $browsers
}

# --------------------------------------------
# DECRYPT PASSWORD USING WINDOWS API
# --------------------------------------------
function Decrypt-Password {
    param([byte[]]$EncryptedData)
    
    if (-not $EncryptedData -or $EncryptedData.Length -eq 0) {
        return "[No Password]"
    }
    
    try {
        Add-Type -AssemblyName System.Security
        $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect($EncryptedData, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($decrypted)
    }
    catch {
        return "[Encrypted - Cannot Decrypt]"
    }
}

# --------------------------------------------
# READ BROWSER LOGIN DATABASE (DIRECT BINARY READ)
# --------------------------------------------
function Get-BrowserAccounts {
    param(
        [string]$BrowserName,
        [string]$ProfilePath
    )
    
    # Find the Login Data file
    $loginDbPath = ""
    
    # Check Default profile
    $defaultPath = Join-Path $ProfilePath "Default\Login Data"
    if (Test-Path $defaultPath) {
        $loginDbPath = $defaultPath
    }
    else {
        # Check for Profile 1, Profile 2, etc.
        for ($i=1; $i -le 10; $i++) {
            $profilePath2 = Join-Path $ProfilePath "Profile $i\Login Data"
            if (Test-Path $profilePath2) {
                $loginDbPath = $profilePath2
                break
            }
        }
    }
    
    if (-not $loginDbPath -or -not (Test-Path $loginDbPath)) {
        Write-Host "  [!] No login database found for $BrowserName" -ForegroundColor Red
        Write-Host "      Make sure you have saved logins in this browser" -ForegroundColor Gray
        return @()
    }
    
    Write-Host "  [*] Reading login database..." -ForegroundColor Gray
    
    # Copy to temp because browser locks the file
    $tempDb = Join-Path $env:TEMP "temp_login_$([System.DateTime]::Now.Ticks).db"
    Copy-Item $loginDbPath $tempDb -Force
    
    # Read SQLite database using simple byte search (no DLL needed!)
    $accounts = @()
    
    try {
        # Read file as bytes
        $bytes = [System.IO.File]::ReadAllBytes($tempDb)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        
        # Find all URLs and usernames using regex
        # Pattern for URLs
        $urlPattern = 'https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(/[a-zA-Z0-9\-\._\?\,\&/%=]*)?'
        $urls = [regex]::Matches($text, $urlPattern) | Where-Object { $_.Value -notmatch 'chrome|google|microsoft|edge|brave|opera' } | Select-Object -Unique
        
        # Pattern for emails/ usernames
        $emailPattern = '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
        $emails = [regex]::Matches($text, $emailPattern) | Select-Object -Unique
        
        # Pattern for password fields in SQLite
        $passwordPattern = 'password_value[^\x00-\x1f]{10,200}'
        
        # Combine data
        $seenUrls = @{}
        $index = 1
        
        foreach ($url in $urls) {
            $urlValue = $url.Value
            # Clean up URL
            if ($urlValue.Length -gt 100) { $urlValue = $urlValue.Substring(0, 100) }
            
            # Find associated username (try to find email near the URL)
            $associatedUsername = "[Username found in database]"
            foreach ($email in $emails) {
                $emailValue = $email.Value
                # Check if email appears near URL in the text
                $urlIndex = $text.IndexOf($urlValue)
                $emailIndex = $text.IndexOf($emailValue)
                if ($urlIndex -ne -1 -and $emailIndex -ne -1 -and [Math]::Abs($urlIndex - $emailIndex) -lt 500) {
                    $associatedUsername = $emailValue
                    break
                }
            }
            
            # Extract domain for display
            $domain = ""
            if ($urlValue -match 'https?://([^/]+)') {
                $domain = $matches[1]
            }
            
            if (-not $seenUrls.ContainsKey($domain) -and $domain -ne "") {
                $seenUrls[$domain] = $true
                
                $accounts += [PSCustomObject]@{
                    Index = $index
                    URL = $urlValue
                    Domain = $domain
                    Username = $associatedUsername
                    Password = "[Encrypted - Use browser's password manager to view]"
                }
                $index++
            }
            
            if ($accounts.Count -ge 20) { break } # Limit to 20 accounts
        }
    }
    catch {
        Write-Host "  [!] Error reading database: $_" -ForegroundColor Red
    }
    finally {
        # Cleanup temp file
        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
    }
    
    return $accounts
}

# --------------------------------------------
# GET FULL ACCOUNT DETAILS (For selected account)
# --------------------------------------------
function Get-AccountDetails {
    param(
        [string]$BrowserName,
        [string]$ProfilePath,
        [string]$SelectedDomain
    )
    
    $loginDbPath = ""
    $defaultPath = Join-Path $ProfilePath "Default\Login Data"
    if (Test-Path $defaultPath) {
        $loginDbPath = $defaultPath
    }
    else {
        for ($i=1; $i -le 10; $i++) {
            $profilePath2 = Join-Path $ProfilePath "Profile $i\Login Data"
            if (Test-Path $profilePath2) {
                $loginDbPath = $profilePath2
                break
            }
        }
    }
    
    if (-not $loginDbPath) { return $null }
    
    $tempDb = Join-Path $env:TEMP "temp_detail_$([System.DateTime]::Now.Ticks).db"
    Copy-Item $loginDbPath $tempDb -Force
    
    $accountDetail = $null
    
    try {
        $bytes = [System.IO.File]::ReadAllBytes($tempDb)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        
        # Search for the specific domain
        $lines = $text -split "`n"
        $foundUrl = ""
        $foundUsername = ""
        
        # Simple pattern matching
        $urlPattern = 'https?://[a-zA-Z0-9\-\.]+' + [regex]::Escape($SelectedDomain) + '[^"''\s]*'
        $match = [regex]::Match($text, $urlPattern)
        if ($match.Success) {
            $foundUrl = $match.Value
        }
        
        # Find username/email near this URL
        $emailPattern = '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
        $emailMatches = [regex]::Matches($text, $emailPattern)
        foreach ($email in $emailMatches) {
            $urlIndex = $text.IndexOf($foundUrl)
            $emailIndex = $text.IndexOf($email.Value)
            if ($urlIndex -ne -1 -and $emailIndex -ne -1 -and [Math]::Abs($urlIndex - $emailIndex) -lt 1000) {
                $foundUsername = $email.Value
                break
            }
        }
        
        if ($foundUrl -ne "") {
            $accountDetail = [PSCustomObject]@{
                URL = $foundUrl
                Username = $foundUsername
                Password = "[Password is encrypted by browser]`n`n    To view actual password:`n    1. Open $BrowserName`n    2. Go to Settings → Passwords`n    3. Click 'Show Password' after verifying identity"
            }
        }
    }
    catch {
        Write-Host "  Error getting details: $_" -ForegroundColor Red
    }
    finally {
        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
    }
    
    return $accountDetail
}

# --------------------------------------------
# MAIN PROGRAM
# --------------------------------------------

# Step 1: Get installed browsers
Write-Host "`n[STEP 1] Scanning for installed browsers..." -ForegroundColor Cyan
$browsers = Get-InstalledBrowsers

if ($browsers.Count -eq 0) {
    Write-Host "`n[!] No supported browsers found!" -ForegroundColor Red
    Write-Host "    Supported: Chrome, Edge, Brave, Opera" -ForegroundColor Gray
    Read-Host "`nPress Enter to exit"
    exit
}

Write-Host "`n[+] Detected Browsers:" -ForegroundColor Green
$browserList = @($browsers.Keys)
for ($i = 0; $i -lt $browserList.Count; $i++) {
    Write-Host "    $($i+1). $($browserList[$i])" -ForegroundColor White
}

# Step 2: User selects browser
$choice = Read-Host "`n[STEP 2] Select browser number"
$index = [int]$choice - 1

if ($index -lt 0 -or $index -ge $browserList.Count) {
    Write-Host "[!] Invalid selection!" -ForegroundColor Red
    Read-Host "Press Enter"
    exit
}

$selectedBrowser = $browserList[$index]
$profilePath = $browsers[$selectedBrowser]

Write-Host "`n[STEP 3] Fetching accounts from $selectedBrowser..." -ForegroundColor Cyan
Write-Host "    [*] Please wait... (Browser should be closed for best results)" -ForegroundColor Gray

# Step 3: Get all accounts
$accounts = Get-BrowserAccounts -BrowserName $selectedBrowser -ProfilePath $profilePath

if ($accounts.Count -eq 0) {
    Write-Host "`n[!] No saved accounts found in $selectedBrowser" -ForegroundColor Red
    Write-Host "`nPossible reasons:" -ForegroundColor Yellow
    Write-Host "    - Browser is still running (close it and try again)" -ForegroundColor Gray
    Write-Host "    - No saved usernames/passwords in this browser" -ForegroundColor Gray
    Write-Host "    - Login database is empty" -ForegroundColor Gray
    Read-Host "`nPress Enter to exit"
    exit
}

# Step 4: Display all accounts
Write-Host "`n[STEP 4] Saved Accounts Found:" -ForegroundColor Green
Write-Host "="*70

foreach ($acc in $accounts) {
    Write-Host "`n    [$($acc.Index)]" -ForegroundColor Cyan
    Write-Host "        Website : $($acc.Domain)" -ForegroundColor White
    Write-Host "        URL     : $($acc.URL)" -ForegroundColor Gray
    Write-Host "        Username: $($acc.Username)" -ForegroundColor Yellow
}

Write-Host "`n" + "="*70

# Step 5: User selects account
$accountChoice = Read-Host "`n[STEP 5] Select account number to view details"
$accIndex = [int]$accountChoice - 1

if ($accIndex -lt 0 -or $accIndex -ge $accounts.Count) {
    Write-Host "[!] Invalid selection!" -ForegroundColor Red
    Read-Host "Press Enter"
    exit
}

$selectedAccount = $accounts[$accIndex]

Write-Host "`n[STEP 6] Fetching full details for selected account..." -ForegroundColor Cyan

# Step 6: Get full details
$details = Get-AccountDetails -BrowserName $selectedBrowser -ProfilePath $profilePath -SelectedDomain $selectedAccount.Domain

# Step 7: Display final result
Write-Host "`n" + "="*70 -ForegroundColor Green
Write-Host "              ACCOUNT DETAILS" -ForegroundColor Yellow
Write-Host "="*70 -ForegroundColor Green

if ($details -and $details.URL) {
    Write-Host "`n    [✓] Website Link : $($details.URL)" -ForegroundColor Cyan
    Write-Host "    [✓] Email/Username: $($details.Username)" -ForegroundColor Yellow
    Write-Host "    [✓] Password      : $($details.Password)" -ForegroundColor Red
} else {
    Write-Host "`n    [✗] Could not extract full details" -ForegroundColor Red
    Write-Host "    [✗] Website : $($selectedAccount.Domain)" -ForegroundColor Gray
    Write-Host "    [✗] Username: $($selectedAccount.Username)" -ForegroundColor Gray
}

Write-Host "`n" + "="*70
Write-Host "`n[!] EDUCATIONAL PURPOSE ONLY - College Project" -ForegroundColor Yellow
Write-Host "    Passwords are encrypted by the browser for security." -ForegroundColor Gray
Write-Host "    To view actual passwords, use browser's built-in" -ForegroundColor Gray
Write-Host "    password manager (chrome://settings/passwords)" -ForegroundColor Gray
Write-Host "="*70

Read-Host "`nPress Enter to exit"
