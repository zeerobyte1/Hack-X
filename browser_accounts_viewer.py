import os
import sys
import sqlite3
import shutil
import json
import subprocess
import ctypes
from pathlib import Path

# --------------------------------------------
# Admin permission check and request
# --------------------------------------------
def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

def request_admin():
    if not is_admin():
        ctypes.windll.shell32.ShellExecuteW(
            None, "runas", sys.executable, " ".join(sys.argv), None, 1
        )
        sys.exit()

# --------------------------------------------
# Detect all installed browsers
# --------------------------------------------
def get_installed_browsers():
    browsers = []
    
    # Common browser paths (Windows)
    browser_paths = {
        "Google Chrome": r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        "Microsoft Edge": r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "Brave": r"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
        "Opera": r"C:\Program Files\Opera\launcher.exe",
        "Firefox": r"C:\Program Files\Mozilla Firefox\firefox.exe"
    }
    
    for name, path in browser_paths.items():
        if os.path.exists(path):
            browsers.append(name)
    
    # Also check for portable/alternative installs
    edge_chromium = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
    if os.path.exists(edge_chromium) and "Microsoft Edge" not in browsers:
        browsers.append("Microsoft Edge (Chromium)")
    
    return browsers

# --------------------------------------------
# Get login data from Chromium-based browsers
# --------------------------------------------
def get_chromium_logins(browser_name):
    # Map browser name to profile path and executable
    browser_profiles = {
        "Google Chrome": os.path.expanduser("~") + r"\AppData\Local\Google\Chrome\User Data",
        "Microsoft Edge": os.path.expanduser("~") + r"\AppData\Local\Microsoft\Edge\User Data",
        "Microsoft Edge (Chromium)": os.path.expanduser("~") + r"\AppData\Local\Microsoft\Edge\User Data",
        "Brave": os.path.expanduser("~") + r"\AppData\Local\BraveSoftware\Brave-Browser\User Data"
    }
    
    if browser_name not in browser_profiles:
        return []
    
    profile_path = browser_profiles[browser_name]
    login_db_path = os.path.join(profile_path, "Default", "Login Data")
    
    if not os.path.exists(login_db_path):
        # Try to find first profile
        for item in os.listdir(profile_path):
            if item.startswith("Profile") or item == "Default":
                login_db_path = os.path.join(profile_path, item, "Login Data")
                if os.path.exists(login_db_path):
                    break
    
    if not os.path.exists(login_db_path):
        return []
    
    # Copy database to temp location (because it's locked by browser)
    temp_db = os.path.join(os.environ['TEMP'], "login_data_copy.db")
    try:
        shutil.copy2(login_db_path, temp_db)
    except:
        return []
    
    accounts = []
    try:
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        cursor.execute("SELECT origin_url, username_value FROM logins WHERE username_value != ''")
        rows = cursor.fetchall()
        for row in rows:
            url = row[0]
            username = row[1]
            accounts.append(f"{username}  ->  {url}")
        conn.close()
    except Exception as e:
        accounts = [f"Error reading database: {str(e)}"]
    
    # Cleanup
    try:
        os.remove(temp_db)
    except:
        pass
    
    return accounts

# --------------------------------------------
# Get Firefox logins (more complex)
# --------------------------------------------
def get_firefox_logins():
    # Firefox uses logins.json + key3.db / key4.db (encrypted)
    # This requires decryption, not done here for simplicity
    return ["Firefox passwords are encrypted. Use Firefox's built-in password manager."]

# --------------------------------------------
# Main menu
# --------------------------------------------
def main():
    # Request admin
    request_admin()
    
    print("\n" + "="*60)
    print(" BROWSER ACCOUNTS VIEWER (Usernames only)")
    print("="*60)
    
    # Get browsers
    browsers = get_installed_browsers()
    
    if not browsers:
        print("\n[!] No supported browsers found on this system.")
        input("\nPress Enter to exit...")
        return
    
    print("\n[+] Detected browsers:\n")
    for idx, browser in enumerate(browsers, start=1):
        print(f"  {idx}. {browser}")
    
    # User selection
    while True:
        try:
            choice = int(input("\nSelect browser number: "))
            if 1 <= choice <= len(browsers):
                selected_browser = browsers[choice-1]
                break
            else:
                print("Invalid choice. Try again.")
        except:
            print("Enter a valid number.")
    
    print(f"\n[+] Fetching accounts from {selected_browser}...")
    
    if "Firefox" in selected_browser:
        accounts = get_firefox_logins()
    else:
        accounts = get_chromium_logins(selected_browser)
    
    # Display accounts
    if not accounts:
        print("\n[!] No saved usernames found or unable to read database.")
    else:
        print(f"\n[+] Saved Accounts ({len(accounts)} found):\n")
        for acc in accounts:
            print(f"  - {acc}")
    
    input("\n\nPress Enter to exit...")

if __name__ == "__main__":
    main()