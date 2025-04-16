# AidenGuard Firewall Automation (abusescan)

**Author:** iimawtin  
**Repository:** https://github.com/iimawtin/abusescan  

---

## 📖 Overview
This project provides a set of Bash scripts to **automate** the installation, configuration, and management of a hardened firewall on Linux servers. Key features include:

- **Automated installation** of `iptables`, `ipset`, and persistence tools.
- **Dynamic IP blacklist** fetched from GitHub (`update-blacklist.sh`).
- **Menu-driven management** (`firewall-menu.sh`) for easy operations:
  1. Install Firewall
  2. Add New Port
  3. Remove Port
  4. Disable Firewall
  5. Update IP Blacklist Range
  6. Show IP Blacklist
  7. Show Firewall Rules
  8. Show Open Ports (listening + user-defined)
  9. Our Telegram Channel
  10. Exit
- **Real-time monitoring** script (`firewall-monitor.sh`) that:
  - Parses `/var/log/syslog` for scan or login attempts.
  - Automatically blocks offending IPs/subnets via `ipset`.
  - Sends alerts to your Telegram using Bot API.
- **Customizable banner** with ASCII art and colors.
- **Built-in log rotation** for `/var/log/firewall.log`.

---

## 🛠️ Files and Structure

```
abusescan/
├── INSTALL-ANTISCAN.SH      # Main installer script (install-antiscan.sh)
├── UPDATE-BLACKLIST.SH      # Static IP blacklist ranges updater
├── FIREWALL-MENU.SH         # Interactive menu for firewall management
├── FIREWALL-MONITOR.SH      # Log watcher & auto-block script
├── FIREWALL-LOG-WATCHER.SH  # Cron wrapper to invoke monitor
└── README.md                # This documentation
```

### 1. `install-antiscan.sh`
- **Installs**: `iptables`, `ipset`, `iptables-persistent`, `curl`.  
- **Configures**:
  - DNS (`/etc/resolv.conf` → `8.8.8.8`, `4.2.2.4`).  
  - `logrotate` for `/var/log/firewall.log`.  
- **Fetches** latest `update-blacklist.sh` from GitHub and applies it.  
- **Applies** default firewall policies:
  - DROP all incoming by default, allow established & ICMP.  
  - Opens user-defined + internal service ports.  
  - Drops all traffic from blacklisted IPs/subnets.
- **Schedules** `firewall-log-watcher.sh` via cron every 10 minutes.
- **Sends** a Telegram notification when initialization completes.

### 2. `update-blacklist.sh`
- Defines two `ipset` sets: `blacklist` and `blacklist_subnet`.  
- Populates them with a curated list of known private, reserved, or abuse-prone IP ranges.  
- Can be updated independently in GitHub; installer always pulls the latest.

### 3. `firewall-menu.sh`
- Provides an **interactive TUI** for common operations without editing scripts:
  1. **Install Firewall** → runs `install-antiscan.sh`.
  2. **Add/Remove Port** → updates `iptables` + persists.
  3. **Disable Firewall** → flushes and accepts all.
  4. **Update IP Blacklist** → fetches & runs `update-blacklist.sh`.
  5. **Show IP Blacklist** → lists both `blacklist` and `blacklist_subnet`.
  6. **Show Firewall Rules** → `iptables -L -n --line-numbers`.
  7. **Show Open Ports** → `ss -tulpn` + user-defined open ports parsed from `iptables`.
  8. **Our Telegram Channel** → displays link: `t.me/iimawtin`.
  9. **Exit**.

### 4. `firewall-monitor.sh` & `firewall-log-watcher.sh`
- **Monitor** scans and login failures in `/var/log/syslog`.  
- **Blocks** offending IPs via `ipset add blacklist` and corresponding `/24` subnet in `blacklist_subnet`.  
- **Logs** blocks to `/var/log/firewall.log`.  
- **Alerts** via Telegram Bot (hidden in console).  

---

## 🚀 Quick Start

1. **Clone the repo**:
   ```bash
   git clone https://github.com/iimawtin/abusescan.git
   cd abusescan
   ```

2. **Run the menu** (no install needed):
   ```bash
   bash firewall-menu.sh
   ```

3. **Or** directly install via curl:
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/iimawtin/abusescan/main/install-antiscan.sh)
   ```

4. **Follow prompts** for Telegram Token, Chat ID, and allowed ports.

---

## 📡 Telegram Integration
- Create a Bot via [@BotFather](https://t.me/BotFather) and obtain **API Token**.  
- Get your **Chat ID** (e.g., via [@get_id_bot](https://t.me/get_id_bot)).  
- Enter both when prompted by installer.  
- Alerts & setup confirmation will be sent to your chat.

---

## ⚙️ Customization
- **Ports**: edit `INTERNAL_ALLOWED_PORTS` in `install-antiscan.sh`.  
- **Blacklist**: update `update-blacklist.sh` ranges.  
- **Cron frequency**: modify `/etc/cron.d/firewall-logger`.  
- **Banner**: adjust ASCII art in `firewall-menu.sh`.

---

## 📝 License
MIT © iimawtin

---

*Stay secure and informed — AidenGuard by iimawtin*

