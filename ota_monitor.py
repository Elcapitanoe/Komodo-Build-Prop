import requests
import re
import json
import os
import sys
import datetime

TARGET_URL = "https://developer.android.com/about/versions/16/qpr3/download-ota"
DEVICE_CODENAME = "komodo" 
STATE_FILE = "ota_state.json"
USER_AGENT = "Mozilla/5.0 (compatible; AndroidOTAMonitor/1.0; +https://github.com/your-username/repo)"

def log(level, message):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] [{level.upper()}] {message}")

def send_telegram(message):
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")

    if not token or not chat_id:
        log("ERROR", "Telegram credentials missing in environment variables.")
        sys.exit(1)

    url = f"https://api.telegram.org/bot{token}/sendMessage"
    payload = {
        "chat_id": chat_id, 
        "text": message, 
        "parse_mode": "Markdown",
        "disable_web_page_preview": True
    }
    
    try:
        response = requests.post(url, json=payload, timeout=10)
        response.raise_for_status()
    except Exception as e:
        log("ERROR", f"Failed to dispatch Telegram notification: {e}")

def fetch_and_parse_links():
    headers = {"User-Agent": USER_AGENT}
    
    try:
        log("INFO", f"Checking endpoint: {TARGET_URL}")
        response = requests.get(TARGET_URL, headers=headers, timeout=20)
        response.raise_for_status()
    except requests.RequestException as e:
        log("FATAL", f"Network unreachable or HTTP error: {e}")
        sys.exit(1)

    regex_pattern = r'https:\/\/dl\.google\.com\/developers\/android\/[a-zA-Z0-9]+\/images\/ota\/[a-zA-Z0-9_.-]+\.zip'
    all_links = re.findall(regex_pattern, response.text)
    
    target_links = [
        link for link in all_links 
        if f"/{DEVICE_CODENAME}_" in link or f"/{DEVICE_CODENAME}-" in link or f"{DEVICE_CODENAME}_" in link.split('/')[-1]
    ]
    
    unique_links = sorted(list(set(target_links)))
    
    log("INFO", f"Parsed {len(all_links)} total links. Found {len(unique_links)} for device '{DEVICE_CODENAME}'.")
    return unique_links

def load_previous_state():
    if not os.path.exists(STATE_FILE):
        return []
    try:
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        log("WARN", "State file corrupted. Resetting state.")
        return []

def main():
    current_links = fetch_and_parse_links()
    
    if not current_links:
        log("WARN", f"No links found specifically for {DEVICE_CODENAME} (other devices might exist).")

    old_links = load_previous_state()
    new_links = set(current_links) - set(old_links)
    
    if new_links:
        count = len(new_links)
        log("INFO", f"DETECTED {count} NEW UPDATE(S) FOR {DEVICE_CODENAME}")
        
        msg = [f"[ALERT] OTA DETECTED: {DEVICE_CODENAME.upper()} ({count})\n"]
        for link in new_links:
            filename = link.split('/')[-1]
            msg.append(f"FILE: {filename}")
            msg.append(f"LINK: {link}\n")
            
        send_telegram("\n".join(msg))
        
        with open(STATE_FILE, "w") as f:
            json.dump(current_links, f, indent=2)
            
        with open(os.environ['GITHUB_OUTPUT'], 'a') as fh:
            print("updated=true", file=fh)
            
    else:
        log("INFO", f"NO CHANGES DETECTED FOR {DEVICE_CODENAME}")
        with open(os.environ['GITHUB_OUTPUT'], 'a') as fh:
            print("updated=false", file=fh)

if __name__ == "__main__":
    main()
