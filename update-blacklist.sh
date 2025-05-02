#!/bin/bash
set -e

# 📦 منبع لیست آی‌پی
IP_LIST_SOURCE="https://raw.githubusercontent.com/iimawtin/abusescan/main/ips.txt"
BLOCKLIST_CONF="/etc/ipset/blocklist.conf"

# ✅ ایجاد ipset اگر نبود
ipset list blacklist >/dev/null 2>&1 || ipset create blacklist hash:net

# ♻️ پاک‌سازی قبلی
ipset flush blacklist

# 📥 دانلود لیست آی‌پی
TMPFILE=$(mktemp)
curl -fsSL "$IP_LIST_SOURCE" -o "$TMPFILE" || exit 1

# ➕ افزودن IPها
while IFS= read -r IP; do
    [[ -z "$IP" || "$IP" =~ ^# ]] && continue
    ipset add blacklist "$IP" 2>/dev/null
done < "$TMPFILE"
rm -f "$TMPFILE"

# 💾 ذخیره ipset
mkdir -p /etc/ipset
ipset save > "$BLOCKLIST_CONF"

# 🔄 اجرای restore در بوت
grep -q "ipset restore < $BLOCKLIST_CONF" /etc/crontab || \
echo "@reboot root ipset restore < $BLOCKLIST_CONF" >> /etc/crontab

# ⏱ کران‌جاب آپدیت هر ۱۰ دقیقه
CRON_JOB="*/10 * * * * root bash /usr/local/bin/update-blacklist.sh > /dev/null 2>&1"
grep -Fxq "$CRON_JOB" /etc/crontab || echo "$CRON_JOB" >> /etc/crontab
