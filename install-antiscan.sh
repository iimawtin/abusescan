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

# ساخت ipset‌ها در صورت نبود
ipset list blacklist &>/dev/null || ipset create blacklist hash:ip
ipset list blacklist_subnet &>/dev/null || ipset create blacklist_subnet hash:net

# اجازه به loopback و Docker
iptables -I INPUT  -i lo -j ACCEPT
iptables -I OUTPUT -o lo -j ACCEPT

# باز کردن پورت‌های اصلی
iptables -I INPUT -p tcp -m multiport --dports 22,80,443,3306,2053,8080,8443,8010 -j ACCEPT

# تنظیم قوانین Docker
iptables -N DOCKER-USER 2>/dev/null || true
iptables -I DOCKER-USER -i br+ -j ACCEPT
iptables -I DOCKER-USER -o br+ -j ACCEPT
iptables -I FORWARD     -i br+ -j ACCEPT
iptables -I FORWARD     -o br+ -j ACCEPT

iptables -I DOCKER-USER -s 172.16.0.0/12 -p udp --dport 53 -j ACCEPT
iptables -I DOCKER-USER -s 172.16.0.0/12 -p tcp --dport 53 -j ACCEPT

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
iptables -I INPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -I OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -I INPUT  -p icmp -j ACCEPT
iptables -I OUTPUT -p icmp -j ACCEPT

# اجازه به ترافیک پروتکل SIT (proto 41)
iptables -A INPUT -p 41 -j ACCEPT
iptables -A OUTPUT -p 41 -j ACCEPT
iptables -A FORWARD -p 41 -j ACCEPT

# باز کردن پورت‌های ضروری روی INPUT و OUTPUT
INTERNAL_ALLOWED_PORTS="22 62789 8443 8080 3306 80 53 5228 443 123 10085"
ALL_PORTS=$(echo "$PORTS $INTERNAL_ALLOWED_PORTS" | tr ' ' '\n' | sort -u | tr '\n' ' ')
for port in $ALL_PORTS; do
  iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  iptables -A INPUT -p udp --dport "$port" -j ACCEPT
  iptables -A OUTPUT -p tcp --dport "$port" -j ACCEPT
  iptables -A OUTPUT -p udp --dport "$port" -j ACCEPT
done

# باز کردن پورت‌های خاص TCP و UDP
iptables -A OUTPUT -p tcp --dport 5222 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p udp --dport 443 -j ACCEPT
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT
iptables -A OUTPUT -p udp --dport 5228 -j ACCEPT
iptables -A OUTPUT -p udp --dport 10085 -j ACCEPT
iptables -A OUTPUT -p udp --dport 3478:3481 -j ACCEPT

iptables -A INPUT -p tcp --dport 9300:9400 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 9300:9400 -j ACCEPT
iptables -A INPUT -p udp --dport 9300:9400 -j ACCEPT
iptables -A OUTPUT -p udp --dport 9300:9400 -j ACCEPT

# باز کردن پورت‌های TCP Mobile Legend
iptables -A INPUT -p tcp -m multiport --dports 5000:5221,5224:5227,5229:5241,5243:5508 -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 5551:5559,5601:5700,9001,9443,10003 -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 30000:30300 -j ACCEPT
iptables -A OUTPUT -p tcp -m multiport --dports 5000:5221,5224:5227,5229:5241,5243:5508 -j ACCEPT
iptables -A OUTPUT -p tcp -m multiport --dports 5551:5559,5601:5700,9001,9443,10003 -j ACCEPT
iptables -A OUTPUT -p tcp -m multiport --dports 30000:30300 -j ACCEPT

# باز کردن پورت‌های UDP مربوط به گیم
iptables -A INPUT -p udp -m multiport --dports 4001:4009,5000:5221,5224:5241,5243:5508 -j ACCEPT
iptables -A INPUT -p udp -m multiport --dports 5551:5559,5601:5700,2702,3702,8001 -j ACCEPT
iptables -A INPUT -p udp -m multiport --dports 9000:9010,9992,10003,30190,30000:30300 -j ACCEPT
iptables -A OUTPUT -p udp -m multiport --dports 4001:4009,5000:5221,5224:5241,5243:5508 -j ACCEPT
iptables -A OUTPUT -p udp -m multiport --dports 5551:5559,5601:5700,2702,3702,8001 -j ACCEPT
iptables -A OUTPUT -p udp -m multiport --dports 9000:9010,9992,10003,30190,30000:30300 -j ACCEPT

# ✅ اینجا تعریف کنترل UDP پورت‌های بالا (HIGHPORTS)
iptables -N HIGHPORTS
iptables -A OUTPUT -p udp --dport 10000:65535 -j HIGHPORTS

iptables -A HIGHPORTS -m hashlimit \
  --hashlimit-name abuse \
  --hashlimit-above 30/minute \
  --hashlimit-burst 15 \
  --hashlimit-mode srcip \
  --hashlimit-htable-expire 60000 \
  -j ACCEPT

iptables -A HIGHPORTS -j LOG --log-prefix "❌ ABUSE-UDP: "
iptables -A HIGHPORTS -j DROP

# بستن بعضی UDPهای خطرناک خاص
iptables -A OUTPUT -p udp --dport 5564 -j DROP
iptables -A OUTPUT -p udp --dport 16658 -j DROP
iptables -A OUTPUT -p udp --dport 166 -j DROP

# بلاک لیست IP و Subnet روی INPUT
iptables -A INPUT -m set --match-set blacklist src -j DROP
iptables -A INPUT -m set --match-set blacklist_subnet src -j DROP

# جلوگیری از ارتباط خروجی به IPهای بلاک‌شده
if ! iptables -C OUTPUT -m set --match-set blacklist dst -j DROP 2>/dev/null; then
  iptables -A OUTPUT -m set --match-set blacklist dst -j DROP
fi

if ! iptables -C OUTPUT -m set --match-set blacklist_subnet dst -j DROP 2>/dev/null; then
  iptables -A OUTPUT -m set --match-set blacklist_subnet dst -j DROP
fi

# قوانین ضد اسکن TCP
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j LOG --log-prefix "NULL scan: " --log-level 4
iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j LOG --log-prefix "XMAS scan: " --log-level 4
iptables -A INPUT -p tcp --tcp-flags ALL FIN -j LOG --log-prefix "FIN scan: " --log-level 4
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j LOG --log-prefix "SYN/FIN scan: " --log-level 4

# محدودسازی ترافیک داخلی روی FORWARD
iptables -A FORWARD -i eth0 -s 10.0.0.0/8 -d 10.0.0.0/8 -j DROP
iptables -A FORWARD -i eth0 -s 192.168.0.0/16 -d 192.168.0.0/16 -j DROP
iptables -A FORWARD -i eth0 -s 102.192.0.0/16 -d 102.192.0.0/16 -j DROP
iptables -A FORWARD -i eth0 -s 172.16.0.0/12 -d 172.16.0.0/12 -j DROP
iptables -A FORWARD -i eth0 -s 192.0.0.0/12 -d 192.0.0.0/12 -j DROP

# مجوز FORWARD روی پورت‌های ضروری
iptables -A FORWARD -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -p udp --dport 443 -j ACCEPT

# بستن بقیه FORWARD
iptables -A FORWARD -j DROP

# Anti-scan با recent روی UDP
iptables -A INPUT -p udp -m recent --name UDPSCAN --rcheck --seconds 10 --hitcount 3 -j DROP
iptables -A INPUT -p udp -m recent --name UDPSCAN --set -j ACCEPT

# محدودسازی سرعت UDP ورودی
iptables -A INPUT -p udp -m limit --limit 10/second --limit-burst 20 -j ACCEPT

# بلاک کامل بقیه UDP
iptables -A INPUT -p udp -j DROP
iptables -A INPUT -p udp --dport 16658 -j DROP
iptables -A INPUT -p udp --dport 5564 -j DROP
iptables -A INPUT -p udp --dport 166 -j DROP

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
NOTIFIED_FILE="/tmp/notified-ips.txt"
IPSET_BLOCK="blacklist"
IPSET_SUBNET_BLOCK="blacklist_subnet"
HOSTNAME=$(hostname)
TOKEN="__TOKEN__"
CHAT_ID="__CHATID__"

# ساخت ipset‌ها در صورت نبود
ipset list $IPSET_BLOCK &>/dev/null || ipset create $IPSET_BLOCK hash:ip
ipset list $IPSET_SUBNET_BLOCK &>/dev/null || ipset create $IPSET_SUBNET_BLOCK hash:net

# لیست سفید اولیه
WHITELIST=(
  "127.0.0.1"
  "127.0.0.53"
  "4.2.2.4"
  "8.8.8.8"
)

# افزودن آی‌پی‌های لوکال و تونل‌ها به لیست سفید
LOCAL_IPS=$(hostname -I | tr ' ' '\n')
TUNNEL_IPS=$(ip -o -f inet addr show | grep -E 'tun|wg' | awk '{print $4}' | cut -d/ -f1)
for ip in $LOCAL_IPS $TUNNEL_IPS; do
  WHITELIST+=("$ip")
done

# ساخت فایل اگر وجود نداشت
touch "$NOTIFIED_FILE"

# استخراج آی‌پی‌های مشکوک از لاگ اخیر
tail -n 500 "$LOGFILE" | grep -E "Failed password|scan|BLOCKED-UDP-OUT|ABUSE-UDP" \
  | grep -oE 'SRC=([0-9]{1,3}\.){3}[0-9]{1,3}' \
  | cut -d= -f2 > "$TMPFILE"

for ip in $(sort "$TMPFILE" | uniq); do
  is_whitelisted=0
  for whitelist_ip in "${WHITELIST[@]}"; do
    if [[ "$ip" == "$whitelist_ip" ]]; then
      is_whitelisted=1
      break
    fi
  done

  if (( is_whitelisted )); then
    echo "[WHITELISTED] $ip → رد شد." >> /var/log/firewall.log
    continue
  fi

  # فقط اگر آی‌پی بلاک نشده و پیام هم قبلاً نرفته
  if ! ipset test $IPSET_BLOCK $ip &>/dev/null && ! grep -Fxq "$ip" "$NOTIFIED_FILE"; then
    ipset add -exist $IPSET_BLOCK $ip
    subnet=$(echo $ip | awk -F. '{print $1"."$2"."$3".0/24"}')
    ipset add -exist $IPSET_SUBNET_BLOCK $subnet
    echo "$(date) - Blocked IP: $ip from $HOSTNAME" >> /var/log/firewall.log
    echo "$ip" >> "$NOTIFIED_FILE"
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
      -d "chat_id=$CHAT_ID" \
      -d "text=🚨 آی‌پی $ip در سرور $HOSTNAME بلاک شد." > /dev/null 2>&1
  fi
done

rm -f "$TMPFILE"
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
