#!/bin/bash

clear
echo -e "\e[1;36m🛡️ Advanced Firewall Manager - by iimawtin\e[0m"

MENU() {
  echo "-------------------------------"
  echo "1) Install Firewall"
  echo "2) Add New Port"
  echo "3) Remove Port"
  echo "4) Disable Firewall"
  echo "5) Exit"
  echo "-------------------------------"
  read -p "Select an option [1-5]: " CHOICE
}

ADD_PORT() {
  read -p "Enter port to allow (e.g. 8081): " P
  iptables -A INPUT -p tcp --dport $P -j ACCEPT
  iptables -A INPUT -p udp --dport $P -j ACCEPT
  netfilter-persistent save
  echo "✅ Port $P added."
}

REMOVE_PORT() {
  read -p "Enter port to remove (e.g. 8081): " P
  iptables -D INPUT -p tcp --dport $P -j ACCEPT 2>/dev/null
  iptables -D INPUT -p udp --dport $P -j ACCEPT 2>/dev/null
  netfilter-persistent save
  echo "❌ Port $P removed."
}

DISABLE_FW() {
  iptables -F && iptables -X
  iptables -t nat -F && iptables -t nat -X
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
  netfilter-persistent save
  echo "🚫 Firewall disabled."
}

while true; do
  MENU
  case $CHOICE in
    1)
      bash <(curl -fsSL https://raw.githubusercontent.com/iimawtin/abusescan/main/install-antiscan.sh)
      ;;
    2) ADD_PORT ;;
    3) REMOVE_PORT ;;
    4) DISABLE_FW ;;
    5) echo "👋 Bye"; exit 0 ;;
    *) echo "❌ Invalid option";;
  esac
done
