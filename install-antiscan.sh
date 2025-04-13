#!/bin/bash

echo -e "\e[1;34m🔐 شروع نصب و پیکربندی امنیتی...\e[0m"

# بررسی دسترسی روت
if [[ $EUID -ne 0 ]]; then
  echo -e "\e[1;31mاین اسکریپت باید با دسترسی root اجرا شود!\e[0m"
  exit 1
fi

# دریافت اطلاعات از کاربر (پورت‌ها، توکن، چت‌آیدی)
echo -e "\e[1;33mلطفاً توکن تلگرام خود را وارد کنید:\e[0m"
read TELEGRAM_TOKEN

echo -e "\e[1;33mلطفاً چت‌آیدی خود را وارد کنید:\e[0m"
read CHAT_ID

echo -e "\e[1;33mلطفاً پورت‌های مورد نظر را وارد کنید (مثلاً 22 9090 9898):\e[0m"
read PORTS

# نصب ابزارها
echo -e "\e[1;33m📦 نصب ابزارهای مورد نیاز...\e[0m"
apt update -y && apt install -y iptables ipset curl fail2ban iptables-persistent > /dev/null

# پاکسازی قوانین قبلی
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# سیاست‌های پیش‌فرض
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# اجازه به ترافیک مجاز (Established, SSH fail safe)
iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# باز کردن پورت‌های داده‌شده توسط کاربر
echo -e "\e[1;36m🔓 باز کردن پورت‌های: $PORTS\e[0m"
for port in $PORTS; do
  iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
  iptables -A INPUT -p udp --dport "$port" -j ACCEPT
done

# جلوگیری از اسکن‌های معروف
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL FIN -j DROP
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP

# جلوگیری از اسکن داخلی بین کلاینت‌ها
iptables -A FORWARD -i eth0 -s 10.0.0.0/8 -d 10.0.0.0/8 -j DROP
iptables -A FORWARD -i eth0 -s 192.168.0.0/16 -d 192.168.0.0/16 -j DROP
iptables -A FORWARD -i eth0 -s 172.16.0.0/12 -d 172.16.0.0/12 -j DROP

# محدودسازی ترافیک خروجی کلاینت‌ها فقط به HTTP/HTTPS/DNS
iptables -A FORWARD -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -p udp --dport 443 -j ACCEPT
iptables -A FORWARD -j DROP

# ذخیره قوانین فایروال
netfilter-persistent save > /dev/null

# نصب و پیکربندی Fail2Ban
echo -e "\e[1;33m⚙️ نصب و پیکربندی Fail2Ban...\e[0m"
apt install -y fail2ban > /dev/null

# پیکربندی Fail2Ban برای جلوگیری از اسکن پورت‌ها
echo -e "[sshd]
enabled  = true
port     = ssh
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 600

[iptables]
enabled = true
filter  = f2b-iptables
action  = iptables[name=SSH, port=ssh, protocol=tcp]
logpath = /var/log/auth.log
maxretry = 3
bantime  = 600
" > /etc/fail2ban/jail.local

# فعال‌سازی Fail2Ban
systemctl enable fail2ban --now > /dev/null
systemctl restart fail2ban

# ارسال پیام به تلگرام که نصب موفقیت‌آمیز بوده
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d chat_id=$CHAT_ID -d text="🔐 فایروال به‌طور کامل پیکربندی شد. پورت‌های مورد نظر باز شدند و اسکن‌ها مسدود شدند."

echo -e "\e[1;32m✅ همه چیز انجام شد! پورت‌های مورد نظر باز، بقیه بسته و محافظت در برابر پورت‌اسکن فعال است.\e[0m"

# پاسخ به /start
echo -e "\e[1;36m🤖 منتظر پیام‌های تلگرام هستم...\e[0m"
while :; do
  # بررسی پیام‌ها
  response=$(curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/getUpdates?offset=-1")
  if [[ $response == *"/start"* ]]; then
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d chat_id=$CHAT_ID -d text="🚀 ربات تلگرام شما به‌طور کامل راه‌اندازی شد!"
  fi
  sleep 2
done
