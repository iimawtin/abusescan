#!/bin/bash

echo -e "\e[1;34m🔐 Start installing and configuring advanced security...\e[0m"

# بررسی دسترسی روت
if [[ $EUID -ne 0 ]]; then
  echo -e "\e[1;31mاین اسکریپت باید با دسترسی root اجرا شود!\e[0m"
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

# DNS
echo -e "nameserver 8.8.8.8\nnameserver 4.2.2.4" > /etc/resolv.conf

# اطلاعات از کاربر
read -p "🔐 توکن تلگرام: " TELEGRAM_TOKEN
read -p "📨 چت آیدی: " CHAT_ID
read -p "📡 پورت‌های مجاز (مثلا: 22 443 9090): " PORTS
read -p "آیا می‌خواهی فایروال رو غیرفعال کنی؟ (yes/no): " DISABLE

if [[ $DISABLE == "yes" ]]; then
  iptables -F
  iptables -X
  iptables -t nat -F
  iptables -t nat -X
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
  exit 0
fi

apt-get install -y iptables ipset iptables-persistent curl > /dev/null

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
ipset flush

# دریافت لیست سیاه
if [[ ! -f /usr/local/bin/update-blacklist.sh ]]; then
  curl -fsSL https://raw.githubusercontent.com/iimawtin/abusescan/main/update-blacklist.sh -o /usr/local/bin/update-blacklist.sh
  chmod +x /usr/local/bin/update-blacklist.sh
fi
bash /usr/local/bin/update-blacklist.sh

# قوانین اصلی
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT

# باز کردن پورت‌ها
INTERNAL_ALLOWED_PORTS="22 62789 8443 8080 3306 80 53 5228 443 123 10085"
USER_PORTS="$PORTS"
ALL_PORTS=$(echo "$USER_PORTS $INTERNAL_ALLOWED_PORTS" | tr ' ' '\n' | sort -u | tr '\n' ' ')
for port in $ALL_PORTS; do
  iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  iptables -A INPUT -p udp --dport "$port" -j ACCEPT
done

iptables -A INPUT -m set --match-set blacklist src -j DROP
iptables -A INPUT -m set --match-set blacklist_subnet src -j DROP

iptables -A INPUT -p tcp --tcp-flags ALL NONE -j LOG --log-prefix "NULL scan: "
ip6tables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j LOG --log-prefix "XMAS scan: "
ip6tables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL FIN -j LOG --log-prefix "FIN scan: "
ip6tables -A INPUT -p tcp --tcp-flags ALL FIN -j DROP
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j LOG --log-prefix "SYN/FIN scan: "
ip6tables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP

iptables -A FORWARD -i eth0 -s 10.0.0.0/8 -d 10.0.0.0/8 -j DROP
iptables -A FORWARD -i eth0 -s 192.168.0.0/16 -d 192.168.0.0/16 -j DROP
iptables -A FORWARD -i eth0 -s 102.192.0.0/16 -d 102.192.0.0/16 -j DROP
iptables -A FORWARD -i eth0 -s 172.16.0.0/12 -d 172.16.0.0/12 -j DROP
iptables -A FORWARD -i eth0 -s 192.0.0.0/12 -d 192.0.0.0/12 -j DROP

iptables -A FORWARD -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -p udp --dport 443 -j ACCEPT
iptables -A FORWARD -j DROP

netfilter-persistent save > /dev/null

# Cronjob هر 10 دقیقه
rm -f /etc/cron.d/firewall-logger
cat << EOF > /etc/cron.d/firewall-logger
*/10 * * * * root /usr/local/bin/firewall-log-watcher.sh
EOF

# فایل اجراکننده مانیتور
cat << EOF > /usr/local/bin/firewall-log-watcher.sh
#!/bin/bash
/usr/local/bin/firewall-monitor.sh
EOF
chmod +x /usr/local/bin/firewall-log-watcher.sh

# ساخت اسکریپت مانیتورینگ
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
  if ! ipset test $IPSET_BLOCK $ip &>/dev/null; then
    ipset add $IPSET_BLOCK $ip
    subnet=$(echo $ip | awk -F. '{print $1"."$2"."$3".0/24"}')
    ipset add $IPSET_SUBNET_BLOCK $subnet
    echo "$(date) - Blocked IP: $ip from $HOSTNAME" >> /var/log/firewall.log
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID&text=🚨 آی‌پی $ip در سرور $HOSTNAME مادرش گاییده شد." > /dev/null
  fi
done
EOF

# جایگزینی مقادیر واقعی
sed -i "s|__TOKEN__|$TELEGRAM_TOKEN|g" /usr/local/bin/firewall-monitor.sh
sed -i "s|__CHATID__|$CHAT_ID|g" /usr/local/bin/firewall-monitor.sh
chmod +x /usr/local/bin/firewall-monitor.sh

# اطلاع‌رسانی نهایی
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
     -d chat_id=$CHAT_ID \
     -d text="🛡️  فایروال کیری قویه AidenGuard با لاگ‌گیری و بلاک خودکار آی‌پی‌های مشکوک راه‌اندازی شد. در سرور $HOSTNAME"

echo -e "\e[1;32m📄 اسکریپت فایروال با موفقیت اجرا شد.\e[0m"
