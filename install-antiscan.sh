#!/bin/bash

# پورت‌هایی که همیشه باز می‌مونن
ALLOWED_PORTS=(22 9090 9898 2053 8008 3389 995 8443 804 803 8080 801 3306 80)

# اطلاعات تلگرام
TG_BOT_TOKEN="7183494241:AAFlO6m8Q_y3zHfEKMaXnQgEa4Nn7ctDokk"
TG_CHAT_ID="210282946"

echo -e "\e[1;34m🔐 در حال نصب سیستم امنیتی کامل...\e[0m"

# بررسی دسترسی روت
if [[ $EUID -ne 0 ]]; then
  echo -e "\e[1;31mاین اسکریپت باید با دسترسی root اجرا شود!\e[0m"
  exit 1
fi

# نصب ابزارها
apt update -y
apt install -y iptables ipset psad iptables-persistent curl > /dev/null

# پاک‌سازی قوانین قبلی
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
ipset destroy blacklist &>/dev/null

# ایجاد لیست بلاک
ipset create blacklist hash:ip hashsize 4096

# سیاست‌های پیش‌فرض
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# مجوز اتصال‌های معتبر و جاری
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# باز گذاشتن پورت‌های مهم
for port in "${ALLOWED_PORTS[@]}"; do
  iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  iptables -A INPUT -p udp --dport "$port" -j ACCEPT
done

# جلوگیری از اسکن‌های معروف
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL FIN -j DROP
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP

# جلوگیری از اسکن داخلی در شبکه‌های خصوصی
iptables -A FORWARD -s 10.0.0.0/8 -d 10.0.0.0/8 -j DROP
iptables -A FORWARD -s 192.168.0.0/16 -d 192.168.0.0/16 -j DROP
iptables -A FORWARD -s 172.16.0.0/12 -d 172.16.0.0/12 -j DROP

# محدودسازی ترافیک خروجی به HTTP/HTTPS/DNS
iptables -A FORWARD -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -p udp --dport 443 -j ACCEPT
iptables -A FORWARD -j DROP

# بلاک آی‌پی‌های لیست سیاه
iptables -A INPUT -m set --match-set blacklist src -j DROP

# ذخیره قوانین
netfilter-persistent save

# پیکربندی psad برای شناسایی اسکن
sed -i "s/EMAIL_ADDRESSES.*/EMAIL_ADDRESSES             root@localhost;/g" /etc/psad/psad.conf
sed -i "s/ENABLE_AUTO_IDS.*/ENABLE_AUTO_IDS             Y/g" /etc/psad/psad.conf
sed -i "s/AUTO_IDS_EMAILS.*/AUTO_IDS_EMAILS             Y/g" /etc/psad/psad.conf
sed -i "s/IPT_SYSLOG_FILE.*/IPT_SYSLOG_FILE             \/var\/log\/syslog/g" /etc/psad/psad.conf
psad --sig-update
systemctl enable psad --now
systemctl restart psad

# اضافه کردن اسکریپت مانیتورینگ به کران
cat > /usr/local/bin/psad-telegram-block.sh <<EOF
#!/bin/bash

LOG="/var/log/psad-alerts.log"
TMP="/tmp/psad.tmp"
touch \$LOG

grep "Danger level" /var/log/syslog | grep "source IP" | grep -v -f \$LOG | while read -r line; do
  echo "\$line" >> \$LOG
  ip=\$(echo \$line | grep -oP 'source IP: \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
  if [[ ! -z "\$ip" ]]; then
    ipset add blacklist \$ip
    curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
      -d chat_id=$TG_CHAT_ID \
      -d text="🚨 حمله یا اسکن شناسایی شد\nبلاک آی‌پی: \$ip\nجزئیات:\n\$line"
  fi
done
EOF

chmod +x /usr/local/bin/psad-telegram-block.sh

# کران‌جاب برای اجرای هر 1 دقیقه
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/psad-telegram-block.sh") | crontab -

echo -e "\e[1;32m✅ نصب کامل شد! فایروال حرفه‌ای، شناسایی حملات، و گزارش به تلگرام فعال است.\e[0m"
