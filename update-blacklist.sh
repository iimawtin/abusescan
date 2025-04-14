#!/bin/bash

# 📌 مسیر ذخیره لیست بلاک‌شده
BLOCKLIST_CONF="/etc/abuse-blocklist.conf"

# 🛑 ساخت مجموعه ipset (در صورت نبود)
ipset list blacklist >/dev/null 2>&1 || ipset create blacklist hash:net
ipset list blacklist_subnet >/dev/null 2>&1 || ipset create blacklist_subnet hash:net

# 🚮 پاک‌سازی لیست فعلی برای جلوگیری از تکرار
ipset flush blacklist

# 🧩 لیست IPها و رنج‌های بلاک‌شده
BLOCKED_RANGES=(
    "10.0.0.0/8"
    "100.64.0.0/10"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.0.0.0/24"
    "192.0.2.0/24"
    "192.88.99.0/24"
    "192.168.0.0/16"
    "198.18.0.0/15"
    "198.51.100.0/24"
    "203.0.113.0/24"
    "240.0.0.0/24"
    "224.0.0.0/4"
    "233.252.0.0/24"
    "102.0.0.0/8"
    "185.235.86.0/24"
    "185.235.87.0/24"
    "114.208.187.0/24"
    "216.218.185.0/24"
    "206.191.152.0/24"
    "45.14.174.0/24"
    "195.137.167.0/24"
    "103.58.50.1/24"
    "25.0.0.0/19"
    "25.29.155.0/24"
    "103.29.38.0/24"
    "103.49.99.0/24"
    "1.174.0.0/24"
    "14.136.0.0/24"
    "1.34.0.0/24"
    "213.195.0.0/24"
    "220.133.0.0/24"
)

# ➕ افزودن به ipset
echo -e "\e[1;33m➕ افزودن رنج‌های جدید به ipset...\e[0m"
for IP in "${BLOCKED_RANGES[@]}"; do
    ipset add blacklist "$IP" 2>/dev/null
done

# 💾 ذخیره در فایل کانفیگ
echo -e "\e[1;34m💾 ذخیره تنظیمات در $BLOCKLIST_CONF\e[0m"
ipset save > "$BLOCKLIST_CONF"

# 🔄 اطمینان از اجرای ipset restore در هنگام بوت
grep -q "ipset restore < $BLOCKLIST_CONF" /etc/crontab || \
echo "@reboot root ipset restore < $BLOCKLIST_CONF" >> /etc/crontab

echo -e "\e[1;32m✅ لیست IPهای بلاک‌شده با موفقیت به‌روزرسانی شد.\e[0m"
