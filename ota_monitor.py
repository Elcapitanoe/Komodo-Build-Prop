import requests
import re
import json
import os
import sys
import datetime

TARGET_URL = "https://developer.android.com/about/versions/16/qpr3/download-ota"
DEVICE_CONFIG_RAW = "komodo" 
STATE_FILE = "ota_state.json"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"

def log(level, message):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] [{level.upper()}] {message}")

def get_target_devices():
    devices = [d.strip() for d in DEVICE_CONFIG_RAW.split(',') if d.strip()]
    if not devices:
        log("FATAL", "No devices configured in DEVICE_CONFIG_RAW.")
        sys.exit(1)
    return devices

def send_telegram(message):
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")

    if not token or not chat_id:
        log("ERROR", "Telegram credentials missing. Skipping notification.")
        return

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

def fetch_all_links():
    headers = {"User-Agent": USER_AGENT}
    try:
        log("INFO", f"Fetching manifest from: {TARGET_URL}")
        response = requests.get(TARGET_URL, headers=headers, timeout=20)
        response.raise_for_status()
    except requests.RequestException as e:
        log("FATAL", f"Network unreachable or HTTP error: {e}")
        sys.exit(1)

    regex_pattern = r'https:\/\/dl\.google\.com\/developers\/android\/[a-zA-Z0-9]+\/images\/ota\/[a-zA-Z0-9_.-]+\.zip'
    return re.findall(regex_pattern, response.text)

def filter_links_for_device(all_links, device_codename):
    return sorted(list(set([
        link for link in all_links
        if f"/{device_codename}_" in link 
        or f"/{device_codename}-" in link 
        or f"{device_codename}_" in link.split('/')[-1]
    ])))

def load_previous_state():
    if not os.path.exists(STATE_FILE):
        return {}
    
    try:
        with open(STATE_FILE, "r") as f:
            data = json.load(f)
            if isinstance(data, list):
                log("WARN", "Legacy state format detected (list). Migrating to dictionary structure.")
                return {}
            return data
    except json.JSONDecodeError:
        log("WARN", "State file corrupted. Resetting state.")
        return {}

def main():
    target_devices = get_target_devices()
    all_found_links = fetch_all_links()
    state = load_previous_state()
    updates_detected = False
    notification_buffer = []
    log("INFO", f"Starting scan for devices: {target_devices}")
    
    for device in target_devices:
        current_device_links = filter_links_for_device(all_found_links, device)
        old_device_links = state.get(device, [])
        new_links = set(current_device_links) - set(old_device_links)
        
        if new_links:
            count = len(new_links)
            updates_detected = True
            log("INFO", f"[{device}] Found {count} new update(s).")
            state[device] = current_device_links
            notification_buffer.append(f"\n*Device: {device.capitalize()}* ({count} updates)")
            for link in new_links:
                filename = link.split('/')[-1]
                notification_buffer.append(f"File: `{filename}`")
                notification_buffer.append(f"Link: {link}")
        else:
            state[device] = current_device_links
            
    if updates_detected:
        header = "*System Notification: Multi-Device OTA Update Report*\n"
        full_message = header + "\n".join(notification_buffer)
        send_telegram(full_message)
        with open(STATE_FILE, "w") as f:
            json.dump(state, f, indent=2)
        with open(os.environ['GITHUB_OUTPUT'], 'a') as fh:
            print("updated=true", file=fh)
    else:
        log("INFO", "Scan complete. No new updates found for any configured device.")
        with open(os.environ['GITHUB_OUTPUT'], 'a') as fh:
            print("updated=false", file=fh)

if __name__ == "__main__":
    main()
