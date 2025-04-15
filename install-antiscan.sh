#!/bin/bash

echo -e "\e[1;34m🔐 شروع نصب و پیکربندی امنیتی پیشرفته...\e[0m"

# بررسی دسترسی روت
if [[ $EUID -ne 0 ]]; then
  echo -e "\e[1;31mاین اسکریپت باید با دسترسی root اجرا شود!\e[0m"
  exit 1
fi

#دریافت هاست نیم
HOSTNAME=$(hostname)

# نصب iptables-persistent برای حفظ قوانین بعد از ریبوت
echo -e "\e[1;33m📦 نصب iptables-persistent...\e[0m"
apt-get update -y >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null 2>&1
echo -e "\e[1;32m✅ iptables-persistent نصب شد.\e[0m"

# تنظیم logrotate برای مدیریت لاگ‌ها
echo -e "\e[1;33m🌀 تنظیم logrotate برای /var/log/firewall.log...\e[0m"
cat <<EOF > /etc/logrotate.d/firewall
/var/log/firewall.log {
    daily
    rotate 1
    missingok
    notifempty
    nocompress
    create 640 root adm
    dateext
    maxage 3
}
EOF
echo -e "\e[1;32m✅ logrotate تنظیم شد (هر 3 روز حذف نسخه قدیمی).\e[0m"

# تغییر DNS سرور
echo -e "\e[1;33m🌐 تغییر DNS سرور به 8.8.8.8 و 4.2.2.4...\e[0m"
echo -e "nameserver 8.8.8.8" > /etc/resolv.conf
echo -e "nameserver 4.2.2.4" >> /etc/resolv.conf

# دریافت اطلاعات از کاربر
echo -e "\e[1;33m🔑 لطفاً توکن تلگرام خود را وارد کنید:\e[0m"
read TELEGRAM_TOKEN
echo -e "\e[1;33m📨 لطفاً چت‌آیدی خود را وارد کنید:\e[0m"
read CHAT_ID
echo -e "\e[1;33m📡 لطفاً پورت‌های مجاز را وارد کنید (مثلاً: 22 443 9090):\e[0m"
read PORTS
echo -e "\e[1;33m❓ آیا می‌خواهید فایروال رو غیرفعال کنید؟ (yes/no):\e[0m"
read DISABLE

# اگر گزینه disable انتخاب شد، فایروال غیرفعال بشه
if [[ $DISABLE == "yes" ]]; then
  echo -e "\e[1;33m💥 فایروال غیرفعال شد.\e[0m"
  iptables -F
  iptables -X
  iptables -t nat -F
  iptables -t nat -X
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
  exit 0
fi

# نصب ابزارهای مورد نیاز
echo -e "\e[1;33m📦 نصب ابزارهای امنیتی...\e[0m"
apt-get update -y && apt-get install -y iptables ipset iptables-persistent curl > /dev/null

# پاکسازی قوانین قبلی
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
ipset flush

# 📥 دانلود اسکریپت update-blacklist.sh اگر وجود نداشت
if [[ ! -f /usr/local/bin/update-blacklist.sh ]]; then
  echo -e "\e[1;36m📥 در حال دانلود update-blacklist.sh از GitHub...\e[0m"
  curl -fsSL https://raw.githubusercontent.com/iimawtin/abusescan/main/update-blacklist.sh -o /usr/local/bin/update-blacklist.sh
  chmod +x /usr/local/bin/update-blacklist.sh
  echo -e "\e[1;32m✅ فایل update-blacklist.sh با موفقیت دانلود شد.\e[0m"
fi

# ▶️ اجرای اسکریپت لیست ipset بلاک‌شده‌ها
bash /usr/local/bin/update-blacklist.sh


# سیاست‌های پیش‌فرض
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# مجاز کردن ترافیک پاسخ و پینگ
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT  # اجازه پینگ

# پورت‌هایی که همیشه باید باز بمونن
INTERNAL_ALLOWED_PORTS="22 62789 8443 8080 3306 80 53 5228 443 123 10085"

# پورت‌هایی که کاربر وارد کرده
USER_PORTS="$PORTS"

# ادغام همه پورت‌ها بدون تکرار
ALL_PORTS=$(echo "$USER_PORTS $INTERNAL_ALLOWED_PORTS" | tr ' ' '\n' | sort -u | tr '\n' ' ')

# باز کردن همه پورت‌ها
for port in $ALL_PORTS; do
  iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  iptables -A INPUT -p udp --dport "$port" -j ACCEPT
done

# مسدود کردن IP‌های موجود در مجموعه ipset
iptables -A INPUT -m set --match-set blacklist src -j DROP
iptables -A INPUT -m set --match-set blacklist_subnet src -j DROP

# جلوگیری از اسکن‌های شناخته‌شده
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j LOG --log-prefix "NULL scan: "
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP

iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j LOG --log-prefix "XMAS scan: "
iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP

iptables -A INPUT -p tcp --tcp-flags ALL FIN -j LOG --log-prefix "FIN scan: "
iptables -A INPUT -p tcp --tcp-flags ALL FIN -j DROP

iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j LOG --log-prefix "SYN/FIN scan: "
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP

# جلوگیری از اسکن داخلی بین کلاینت‌ها
iptables -A FORWARD -i eth0 -s 10.0.0.0/8 -d 10.0.0.0/8 -j DROP
iptables -A FORWARD -i eth0 -s 192.168.0.0/16 -d 192.168.0.0/16 -j DROP
iptables -A FORWARD -i eth0 -s 102.192.0.0/16 -d 102.192.0.0/16 -j DROP
iptables -A FORWARD -i eth0 -s 172.16.0.0/12 -d 172.16.0.0/12 -j DROP
iptables -A FORWARD -i eth0 -s 192.0.0.0/12 -d 192.0.0.0/12 -j DROP

# محدودسازی ترافیک خروجی کلاینت‌ها فقط به HTTP/HTTPS/DNS
iptables -A FORWARD -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -p udp --dport 443 -j ACCEPT
iptables -A FORWARD -j DROP

# لاگ‌گیری از تلاش‌های مسدودشده
#iptables -A INPUT -j LOG --log-prefix "BLOCKED INPUT: " --log-level 4
#iptables -A FORWARD -j LOG --log-prefix "BLOCKED FORWARD: " --log-level 4
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j LOG --log-prefix "NULL scan: "
iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j LOG --log-prefix "XMAS scan: "
iptables -A INPUT -p tcp --tcp-flags ALL FIN -j LOG --log-prefix "FIN scan: "
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j LOG --log-prefix "SYN/FIN scan: "

# ذخیره قوانین فایروال
netfilter-persistent save > /dev/null

# ساخت cron job برای بررسی لاگ‌ها و بلاک آی‌پی‌های مشکوک
rm -f /etc/cron.d/firewall-logger
echo "*/10 * * * * root /usr/local/bin/firewall-log-watcher.sh" > /etc/cron.d/firewall-logger

# ساخت اسکریپت مانیتورینگ و شناسایی حملات
cat << 'EOF' > /usr/local/bin/firewall-monitor.sh
#!/bin/bash

LOGFILE="/var/log/syslog"
TMPFILE="/tmp/firewall-scan.tmp"
IPSET_BLOCK="blacklist"
IPSET_SUBNET_BLOCK="blacklist_subnet"
HOSTNAME=$(hostname)
TOKEN="__TOKEN__"
CHAT_ID="__CHATID__"

grep -E "Failed password|Invalid user|Did not receive identification|connection attempt|scan" $LOGFILE | awk '{print $(NF-3)}' | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' > $TMPFILE

for ip in $(sort $TMPFILE | uniq); do
  # اگر قبلاً بلاک نشده
  if ! ipset test $IPSET_BLOCK $ip &>/dev/null; then
    ipset add $IPSET_BLOCK $ip
    subnet=$(echo $ip | awk -F. '{print $1"."$2"."$3".0/24"}')
    ipset add $IPSET_SUBNET_BLOCK $subnet
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
 -d "chat_id=$CHAT_ID&text=🚨 آی‌پی مشکوک به اسکن: $IP در سرور $HOSTNAME مادرش گاییده شد." > /dev/null
  fi
done
EOF

chmod +x /usr/local/bin/firewall-log-watcher.sh

# اطلاع به تلگرام
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
     -d chat_id=$CHAT_ID \
     -d text="🛡️ فایروال کیری قویه AidenGuard با لاگ‌گیری و بلاک خودکار آی‌پی‌های مشکوک راه‌اندازی شد. \ در سرور $HOSTNAME"

echo -e "\e[1;32m✅ فایروال سخت‌گیرانه با موفقیت فعال شد. آماده دفاع در برابر حملات هستید!\e[0m"
