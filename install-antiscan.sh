#!/bin/bash

echo -e "\e[1;34m🔐 شروع نصب و پیکربندی امنیتی پیشرفته...\e[0m"

# بررسی دسترسی روت
if [[ $EUID -ne 0 ]]; then
  echo -e "\e[1;31mاین اسکریپت باید با دسترسی root اجرا شود!\e[0m"
  exit 1
fi

# دریافت اطلاعات از کاربر
echo -e "\e[1;33m🔑 لطفاً توکن تلگرام خود را وارد کنید:\e[0m"
read TELEGRAM_TOKEN
echo -e "\e[1;33m📨 لطفاً چت‌آیدی خود را وارد کنید:\e[0m"
read CHAT_ID
echo -e "\e[1;33m📡 لطفاً پورت‌های مجاز را وارد کنید (مثلاً: 22 443 9090):\e[0m"
read PORTS

# نصب ابزارهای مورد نیاز
echo -e "\e[1;33m📦 نصب ابزارهای امنیتی...\e[0m"
apt update -y && apt install -y iptables ipset iptables-persistent curl > /dev/null

# پاکسازی قوانین قبلی
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
ipset flush

# سیاست‌های پیش‌فرض
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# مجاز کردن ترافیک پاسخ و پینگ
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT  # اجازه پینگ

# باز کردن پورت‌های مجاز
for port in $PORTS; do
  iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  iptables -A INPUT -p udp --dport "$port" -j ACCEPT
done

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

# محدودسازی ترافیک خروجی کلاینت‌ها فقط به HTTP/HTTPS/DNS
iptables -A FORWARD -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -p udp --dport 443 -j ACCEPT
iptables -A FORWARD -j DROP

# لاگ‌گیری از تلاش‌های مسدودشده
iptables -A INPUT -j LOG --log-prefix "BLOCKED INPUT: " --log-level 4
iptables -A FORWARD -j LOG --log-prefix "BLOCKED FORWARD: " --log-level 4

# ذخیره قوانین فایروال
netfilter-persistent save > /dev/null

# ساخت cron job برای بررسی لاگ‌ها و بلاک آی‌پی‌های مشکوک
echo "*/2 * * * * root /usr/local/bin/firewall-log-watcher.sh" > /etc/cron.d/firewall-logger

# اسکریپت لاگ‌خوان و بلاک آی‌پی
cat << EOF > /usr/local/bin/firewall-log-watcher.sh
#!/bin/bash

LOG_FILE="/var/log/syslog"
BLOCKED_IPS="/var/log/firewall_blocked_ips.txt"

grep "scan" \$LOG_FILE | grep -oE 'SRC=[0-9\.]+' | cut -d= -f2 | sort | uniq | while read ip; do
    if ! grep -q \$ip \$BLOCKED_IPS; then
        iptables -A INPUT -s \$ip -j DROP
        echo \$ip >> \$BLOCKED_IPS
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d chat_id=$CHAT_ID -d text="🚨 آی‌پی مشکوک به اسکن: \$ip بلاک شد."
    fi
done
EOF

chmod +x /usr/local/bin/firewall-log-watcher.sh

# اطلاع به تلگرام
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
     -d chat_id=$CHAT_ID \
     -d text="🛡️ فایروال سخت‌گیرانه با لاگ‌گیری و بلاک خودکار آی‌پی‌های مشکوک راه‌اندازی شد."

echo -e "\e[1;32m✅ فایروال سخت‌گیرانه با موفقیت فعال شد. آماده دفاع در برابر حملات هستید!\e[0m"
