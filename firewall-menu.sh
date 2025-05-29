#!/bin/bash

clear
banner() {
cat <<'EOF'
/**
* >>==================================================================================<<
* ||                                                                                  ||
* ||                                                                                  ||
* ||   __   __  .___  ___.      ___   ____    __    ____ .___________. __  .__   __.  ||
* ||  |  | |  | |   \/   |     /   \  \   \  /  \  /   / |           ||  | |  \ |  |  ||
* ||  |  | |  | |  \  /  |    /  ^  \  \   \/    \/   /  `---|  |----`|  | |   \|  |  ||
* ||  |  | |  | |  |\/|  |   /  /_\  \  \            /       |  |     |  | |  . `  |  ||
* ||  |  | |  | |  |  |  |  /  _____  \  \    /\    /        |  |     |  | |  |\   |  ||
* ||  |__| |__| |__|  |__| /__/     \__\  \__/  \__/         |__|     |__| |__| \__|  ||
* ||                                                                                  ||
* ||                                                                                  ||
* >>==================================================================================<<
*/
EOF

  # Decorative footer with colors via printf
  printf "\n\033[1;34m    →→→→→→→→→→→→→→→→→\033[0m\n"
  printf "\033[1;34m    → \033[1;32m🌐 iimawtin Security 🌐  \033[1;34m←\033[0m\n"
  printf "\033[1;34m    → \033[1;33m⚔️ AidenGuard Firewall Manager ⚔️ \033[1;34m←\033[0m\n"
  printf "\033[1;34m    ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←\033[0m\n\n"

  # Telegram channel line
  printf "\033[1;36m🌐 Our Telegram Channel:\033[0m https://t.me/iimawtin\n\n"
}

# نمایش بنر
banner

# نمایش منو
echo -e "\e[1;33m1) Install Firewall\e[0m"
echo -e "\e[1;33m2) Add New Port\e[0m"
echo -e "\e[1;33m3) Remove Port\e[0m"
echo -e "\e[1;33m4) Disable Firewall\e[0m"
echo -e "\e[1;33m5) Update IP Blacklist Range\e[0m"
echo -e "\e[1;33m6) Optimize Kernel\e[0m"
echo -e "\e[1;33m7) Restore Kernel Settings\e[0m"
echo -e "\e[1;33m8) Show IP Blacklist\e[0m"
echo -e "\e[1;33m9) Show Firewall Rules\e[0m"
echo -e "\e[1;33m10) Show Open Ports\e[0m"
echo -e "\e[1;33m11) Our Telegram Channel\e[0m"
echo -e "\e[1;33m12) Exit\e[0m"
echo "==============================================="
read -p "🔢 Select an option: " option

case $option in
  1)
    bash <(curl -fsSL https://raw.githubusercontent.com/iimawtin/abusescan/main/install-antiscan.sh)
    ;;
  2)
    read -p "🔧 Enter port to add (e.g., 12345): " port
    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    iptables -A INPUT -p udp --dport "$port" -j ACCEPT
    netfilter-persistent save > /dev/null
    echo -e "\e[1;32m✅ Port $port added.\e[0m"
    ;;
  3)
    read -p "🧹 Enter port to remove (e.g., 12345): " port
    iptables -D INPUT -p tcp --dport "$port" -j ACCEPT
    iptables -D INPUT -p udp --dport "$port" -j ACCEPT
    netfilter-persistent save > /dev/null
    echo -e "\e[1;31m❌ Port $port removed.\e[0m"
    ;;
  4)
    iptables -F; iptables -X; iptables -t nat -F; iptables -t nat -X
    iptables -P INPUT ACCEPT; iptables -P FORWARD ACCEPT; iptables -P OUTPUT ACCEPT
    echo -e "\e[1;31m🚫 Firewall disabled.\e[0m"
    ;;
  5)
    echo -e "\e[1;36m📥 Updating IP blacklist from GitHub...\e[0m"
    curl -o /usr/local/bin/update-blacklist.sh \
         https://raw.githubusercontent.com/iimawtin/abusescan/main/update-blacklist.sh \
      && chmod +x /usr/local/bin/update-blacklist.sh \
      && bash /usr/local/bin/update-blacklist.sh
    echo -e "\e[1;32m✅ IP blacklist updated.\e[0m"
    ;;
  6)
    echo -e "\e[1;36m🚀 Running Kernel Optimizer...\e[0m"
    bash <(curl -sL https://raw.githubusercontent.com/iimawtin/optimizer/main/optimize.sh) --optimize
    ;;
  7)
    echo -e "\e[1;36m🔁 Restoring Default Kernel Settings...\e[0m"
    bash <(curl -sL https://raw.githubusercontent.com/iimawtin/optimizer/main/optimize.sh) --restore
    ;;
  8)
    echo -e "\n\e[1;36m📄 Current IP Blacklist Ranges:\e[0m"
    ipset list blacklist
    echo -e "\n\e[1;36m📄 Current Subnet Blacklist Ranges:\e[0m"
    ipset list blacklist_subnet
    ;;
  9)
    echo -e "\n\e[1;36m📋 Firewall Rules:\e[0m"
    iptables -L -n --line-numbers
    ;;
 10)
    echo -e "\n\e[1;36m🔎 Open Listening Ports:\e[0m"
    ss -tulpn
    echo -e "\n\e[1;36m🔑 User-defined open ports:\e[0m"
    iptables -L INPUT -n | grep 'ACCEPT' | grep 'dpt:' | awk -F 'dpt:' '{print $2}' | awk '{print $1}' | sort -n | uniq | xargs echo
    echo
    ;;
 11)
    echo -e "\n\e[1;36m🌐 Our Telegram Channel:\e[0m https://t.me/iimawtin"
    ;;
 12)
    echo -e "\e[1;36m👋 Bye!\e[0m"
    exit 0
    ;;
  *)
    echo -e "\e[1;31m❌ Invalid option.\e[0m"
    ;;
esac
