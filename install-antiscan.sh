#!/bin/bash

echo -e "\e[1;34m🔐 شروع نصب و پیکربندی امنیتی پیشرفته...\e[0m"

# بررسی دسترسی روت
if [[ $EUID -ne 0 ]]; then
  echo -e "\e[1;31mاین اسکریپت باید با دسترسی root اجرا شود!\e[0m"
  exit 1
fi

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

# دانلود blacklist.txt از مخزن GitHub
echo -e "\e[1;36m📥 دانلود blacklist.txt از GitHub...\e[0m"
curl -s https://github.com/iimawtin/abusescan/raw/main/blacklist.txt -o ./blacklist.txt

# تعریف ipset برای لیست بلاک‌شده‌ها
ipset create blacklist hash:net -exist
ipset create blacklist_subnet hash:net -exist  # اضافه شود

# بارگذاری IPهای بلاک‌شده از فایل blacklist.txt
if [ -f ./blacklist.txt ]; then
  echo -e "\e[1;36m📥 بارگذاری IPهای بلاک‌شده از blacklist.txt...\e[0m"
  while read ip; do
    ipset add blacklist "$ip" -exist
  done < ./blacklist.txt
else
  echo -e "\e[1;31m⚠️ فایل blacklist.txt یافت نشد. لیست اولیه بارگذاری نشد.\e[0m"
fi

# پاکسازی قوانین قبلی
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
ipset flush

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

# اجازه به ترافیک‌های مربوط به کانکشن‌های معتبر و لوکال
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# اجازه به پینگ (ICMP)
iptables -A INPUT -p icmp -j ACCEPT

# اجازه به پورت‌های مجاز وارد شده توسط کاربر
for port in $PORTS; do
  iptables -A INPUT -p tcp --dport $port -j ACCEPT
  iptables -A INPUT -p udp --dport $port -j ACCEPT
done

# بلاک کردن IPهایی که در ipset هستند
iptables -A INPUT -m set --match-set blacklist src -j DROP
iptables -A INPUT -m set --match-set blacklist_subnet src -j DROP

# بلاک بقیه ورودی‌ها
iptables -A INPUT -j DROP

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

# ذخیره قوانین فایروال
netfilter-persistent save > /dev/null

# ذخیره قوانین
iptables-save > /etc/iptables/rules.v4

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
    curl -s "https://api.telegram.org/bot$TOKEN/sendMessage" \
      -d chat_id="$CHAT_ID" \
      -d text="🚨 حمله شناسایی شد در سرور: $HOSTNAME%0A📍 IP: $ip%0A📦 Subnet: $subnet بلاک شد." > /dev/null
  fi
done
EOF

# جایگزینی توکن و چت‌آیدی در اسکریپت مانیتورینگ
sed -i "s|__TOKEN__|$TELEGRAM_TOKEN|g" /usr/local/bin/firewall-monitor.sh
sed -i "s|__CHATID__|$CHAT_ID|g" /usr/local/bin/firewall-monitor.sh

chmod +x /usr/local/bin/firewall-monitor.sh

# افزودن به کران‌جاب برای اجرای هر 1 دقیقه
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/firewall-monitor.sh") | crontab -

echo -e "\e[1;32m✅ پیکربندی با موفقیت انجام شد و فایروال فعال است.\e[0m"
