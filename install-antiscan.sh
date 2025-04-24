#!/bin/bash

echo -e "\e[1;34m🔐 Start installing and configuring advanced security...\e[0m"

# بررسی دسترسی روت
if [[ $EUID -ne 0 ]]; then
  echo -e "\e[1;31mThis script must be run with root access!\e[0m"
  exit 1
fi

HOSTNAME=$(hostname)

# نصب iptables-persistent
apt-get update -y >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null 2>&1

# تنظیم logrotate
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

# ساخت فایل لاگ و دسترسی مناسب
touch /var/log/firewall.log
chmod 640 /var/log/firewall.log
chown root:adm /var/log/firewall.log

# تنظیم DNS
echo -e "nameserver 8.8.8.8\nnameserver 4.2.2.4" > /etc/resolv.conf

# دریافت اطلاعات از کاربر
read -p "🔐 Telegram Token: " TELEGRAM_TOKEN
read -p "📨 Chat ID: " CHAT_ID
read -p "📡 Allowed ports (example: 22 443 9090): " PORTS

# نصب ابزارها
apt-get install -y iptables ipset curl >/dev/null 2>&1

# پاکسازی قوانین قبلی
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
ipset flush

# دریافت و اجرای به‌روز‌رسانی لیست سیاه
curl -fsSL https://raw.githubusercontent.com/iimawtin/abusescan/main/update-blacklist.sh \
  -o /usr/local/bin/update-blacklist.sh >/dev/null 2>&1
chmod +x /usr/local/bin/update-blacklist.sh >/dev/null 2>&1
bash /usr/local/bin/update-blacklist.sh

# قوانین پیش‌فرض
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# اجازه به اتصال‌های موجود و ICMP
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT

# اجازه به ترافیک پروتکل SIT (proto 41)
iptables -A INPUT -p 41 -j ACCEPT
iptables -A OUTPUT -p 41 -j ACCEPT
iptables -A FORWARD -p 41 -j ACCEPT

# باز کردن پورت‌ها روی INPUT
INTERNAL_ALLOWED_PORTS="22 62789 8443 8080 3306 80 53 5228 443 123 10085"
ALL_PORTS=$(echo "$PORTS $INTERNAL_ALLOWED_PORTS" | tr ' ' '\n' | sort -u | tr '\n' ' ')
for port in $ALL_PORTS; do
  iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  iptables -A INPUT -p udp --dport "$port" -j ACCEPT
  iptables -A OUTPUT -p tcp --dport "$port" -j ACCEPT
  iptables -A OUTPUT -p udp --dport "$port" -j ACCEPT

  # hashlimit برای پورت‌های بالای 10000 فقط
  if [[ "$port" -ge 10000 ]]; then
    iptables -A OUTPUT -p udp --dport "$port" -m hashlimit \
      --hashlimit-name abuse \
      --hashlimit-above 20/minute \
      --hashlimit-burst 10 \
      --hashlimit-mode srcip \
      --hashlimit-htable-expire 60000 \
      -j LOG --log-prefix "⚠️ UDP FLOOD: "
    iptables -A OUTPUT -p udp --dport "$port" -m hashlimit \
      --hashlimit-name abuse \
      --hashlimit-above 20/minute \
      --hashlimit-burst 10 \
      --hashlimit-mode srcip \
      --hashlimit-htable-expire 60000 \
      -j DROP
  fi

done

# ✅ پورت‌های مجاز UDP برای سرویس‌های خاص
iptables -A OUTPUT -p tcp --dport 5222 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p udp --dport 443 -j ACCEPT
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT
iptables -A OUTPUT -p udp --dport 5228 -j ACCEPT
iptables -A OUTPUT -p udp --dport 10085 -j ACCEPT
iptables -A OUTPUT -p udp --dport 3478:3481 -j ACCEPT
iptables -A OUTPUT -p udp --dport 9300:9400 -j ACCEPT

# مجاز با محدودیت برای تست UDPهای ناشناس
iptables -A OUTPUT -p udp --dport 10000:65535 -m hashlimit \
  --hashlimit-name softsafe \
  --hashlimit-above 30/minute \
  --hashlimit-burst 15 \
  --hashlimit-mode srcip \
  --hashlimit-htable-expire 60000 \
  -j ACCEPT

iptables -A OUTPUT -p udp --dport 10000:65535 -m hashlimit \
  --hashlimit-name abuse_highports \
  --hashlimit-above 30/minute \
  --hashlimit-burst 15 \
  --hashlimit-mode srcip \
  --hashlimit-htable-expire 60000 \
  -j LOG --log-prefix "❌ ABUSE-UDP: "

iptables -A OUTPUT -p udp --dport 10000:65535 -m hashlimit \
  --hashlimit-name abuse \
  --hashlimit-above 30/minute \
  --hashlimit-burst 15 \
  --hashlimit-mode srcip \
  --hashlimit-htable-expire 60000 \
  -j DROP

# 2. بستن باقی UDPهای مشکوک خارج از whitelist
iptables -A OUTPUT -p udp --dport 5564 -j DROP
iptables -A OUTPUT -p udp --dport 16658 -j DROP

# بلاک لیست IP و Subnet
iptables -A INPUT -m set --match-set blacklist src -j DROP
iptables -A INPUT -m set --match-set blacklist_subnet src -j DROP

# قوانین ضد اسکن
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j LOG --log-prefix "NULL scan: "
iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j LOG --log-prefix "XMAS scan: "
iptables -A INPUT -p tcp --tcp-flags ALL FIN -j LOG --log-prefix "FIN scan: "
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j LOG --log-prefix "SYN/FIN scan: "

# محدودسازی ترافیک داخلی در FORWARD
iptables -A FORWARD -i eth0 -s 10.0.0.0/8 -d 10.0.0.0/8 -j DROP
iptables -A FORWARD -i eth0 -s 192.168.0.0/16 -d 192.168.0.0/16 -j DROP
iptables -A FORWARD -i eth0 -s 102.192.0.0/16 -d 102.192.0.0/16 -j DROP
iptables -A FORWARD -i eth0 -s 172.16.0.0/12 -d 172.16.0.0/12 -j DROP
iptables -A FORWARD -i eth0 -s 192.0.0.0/12 -d 192.0.0.0/12 -j DROP

# محدودسازی مجاز FORWARD (خروجی)
iptables -A FORWARD -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -p udp --dport 443 -j ACCEPT
iptables -A FORWARD -j DROP

# Anti-scan با recent
iptables -A INPUT -p udp -m recent --name UDPSCAN --rcheck --seconds 10 --hitcount 3 -j DROP
iptables -A INPUT -p udp -m recent --name UDPSCAN --set -j ACCEPT

# سپس محدودسازی سرعت
iptables -A INPUT -p udp -m limit --limit 10/second --limit-burst 20 -j ACCEPT

# باقی UDPها بلاک
iptables -A INPUT -p udp -j DROP
iptables -A INPUT -p udp --dport 16658 -j DROP
iptables -A INPUT -p udp --dport 5564 -j DROP

# ذخیره قوانین
netfilter-persistent save >/dev/null 2>&1

# Cronjob هر 10 دقیقه
cat <<EOF >/etc/cron.d/firewall-logger
*/10 * * * * root /usr/local/bin/firewall-log-watcher.sh
EOF

# فایل مانیتور
cat << 'EOF' >/usr/local/bin/firewall-log-watcher.sh
#!/bin/bash
/usr/local/bin/firewall-monitor.sh
EOF
chmod +x /usr/local/bin/firewall-log-watcher.sh

# اسکریپت مانیتورینگ
cat << 'EOF' > /usr/local/bin/firewall-monitor.sh
#!/bin/bash

LOGFILE="/var/log/syslog"
TMPFILE="/tmp/firewall-scan.tmp"
IPSET_BLOCK="blacklist"
IPSET_SUBNET_BLOCK="blacklist_subnet"
HOSTNAME=$(hostname)
TOKEN="__TOKEN__"
CHAT_ID="__CHATID__"

# استخراج آی‌پی‌هایی که دارای الگوی SRC= هستند یا لاگ‌های SSH فیل شده یا UDP ABUSE
grep -E "Failed password|scan|BLOCKED-UDP-OUT|ABUSE-UDP" $LOGFILE \
  | grep -oE 'SRC=([0-9]{1,3}\.){3}[0-9]{1,3}' \
  | cut -d= -f2 > $TMPFILE

for ip in $(sort $TMPFILE | uniq); do
  if ! ipset test $IPSET_BLOCK $ip &>/dev/null; then
    ipset add $IPSET_BLOCK $ip
    subnet=$(echo $ip | awk -F. '{print $1"."$2"."$3".0/24"}')
    ipset add $IPSET_SUBNET_BLOCK $subnet
    echo "$(date) - Blocked IP: $ip from $HOSTNAME" >> /var/log/firewall.log
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
      -d "chat_id=$CHAT_ID&text=🚨 آی‌پی $ip در سرور $HOSTNAME بلاک شد." > /dev/null 2>&1
  fi

done
EOF

chmod +x /usr/local/bin/firewall-monitor.sh

# جایگزینی مقادیر واقعی
sed -i "s|__TOKEN__|$TELEGRAM_TOKEN|g" /usr/local/bin/firewall-monitor.sh
sed -i "s|__CHATID__|$CHAT_ID|g" /usr/local/bin/firewall-monitor.sh

# اطلاع‌رسانی نهایی
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
     -d chat_id=$CHAT_ID \
     -d text="🛡️  فایروال کیری قویه AidenGuard با لاگ‌گیری و بلاک خودکار آی‌پی‌های مشکوک راه‌اندازی شد. در سرور $HOSTNAME" >/dev/null 2>&1

echo -e "\e[1;32m📄 The firewall script ran successfully.\e[0m"
