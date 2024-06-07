#!/bin/bash

# Function to check if the script is run as root, otherwise prompt for sudo
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root. Trying to use sudo..."
        if sudo -v; then
            sudo "$0" "$@"
            exit $?
        else
            echo "Failed to gain root privileges. Exiting."
            exit 1
        fi
    fi
}

# Function to detect the package manager and install necessary packages
install_packages() {
    if [ -x "$(command -v apt-get)" ]; then
        install_packages_ubuntu
    elif [ -x "$(command -v yum)" ]; then
        install_packages_centos
    elif [ -x "$(command -v pacman)" ]; then
        install_packages_arch
    else
        echo "Unsupported package manager. Exiting."
        exit 1
    fi
}

install_packages_ubuntu() {
    apt-get update
    apt-get install -y netplan.io openssh-server vim ufw
}

install_packages_centos() {
    yum install -y epel-release
    yum install -y NetworkManager openssh-server vim firewalld
    systemctl enable NetworkManager
    systemctl start NetworkManager
    systemctl enable firewalld
    systemctl start firewalld
}

install_packages_arch() {
    pacman -Sy --noconfirm netctl openssh vim ufw
}

# Function to get network configuration from the user
get_network_config() {
    read -p "Enter the static IP address (e.g., 192.168.3.230/24): " static_ip
    read -p "Enter the gateway IP address (e.g., 192.168.3.1): " gateway_ip
    read -p "Enter the DNS IP address (e.g., 1.1.1.1): " dns_ip
}

# Function to configure network settings based on the distribution
configure_network() {
    if [ -x "$(command -v netplan)" ]; then
        configure_network_ubuntu "$static_ip" "$gateway_ip" "$dns_ip"
    elif [ -x "$(command -v nmcli)" ]; then
        configure_network_centos "$static_ip" "$gateway_ip" "$dns_ip"
    elif [ -x "$(command -v netctl)" ]; then
        configure_network_arch "$static_ip" "$gateway_ip" "$dns_ip"
    else
        echo "Unsupported network configuration tool. Exiting."
        exit 1
    fi
}

configure_network_ubuntu() {
    local static_ip=$1
    local gateway_ip=$2
    local dns_ip=$3

    cat <<EOF >/etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - $static_ip
      gateway4: $gateway_ip
      nameservers:
        addresses:
          - $dns_ip
EOF
    netplan apply
}

configure_network_centos() {
    local static_ip=$1
    local gateway_ip=$2
    local dns_ip=$3

    nmcli con add type ethernet ifname eth0 ip4 $static_ip gw4 $gateway_ip
    nmcli con mod eth0 ipv4.dns $dns_ip
    nmcli con up eth0
}

configure_network_arch() {
    local static_ip=$1
    local gateway_ip=$2
    local dns_ip=$3

    cat <<EOF >/etc/netctl/eth0
Description='A basic static ethernet connection'
Interface=eth0
Connection=ethernet
IP=static
Address=('$static_ip')
Gateway='$gateway_ip'
DNS=('$dns_ip')
EOF
    netctl enable eth0
    netctl start eth0
}

# Function to configure SSH
configure_ssh() {
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl enable sshd
    systemctl start sshd
}

# Function to get new user configuration from the user
get_user_config() {
    read -p "Enter the username: " username
    read -sp "Enter the password: " password
    echo
}

# Function to create a new user
create_user() {
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
}

# Function to get firewall configuration from the user
get_firewall_config() {
    read -p "Enter the subnet (e.g., 192.168.3.0/24) to allow SSH access: " ssh_subnet
}

# Function to configure firewall rules
configure_firewall() {
    if [ -x "$(command -v ufw)" ]; then
        configure_firewall_ubuntu_arch "$ssh_subnet"
    elif [ -x "$(command -v firewall-cmd)" ]; then
        configure_firewall_centos "$ssh_subnet"
    else
        echo "Unsupported firewall tool. Exiting."
        exit 1
    fi
}

configure_firewall_ubuntu_arch() {
    local ssh_subnet=$1

    ufw allow from "$ssh_subnet" to any port 22
    ufw default deny incoming
    ufw default allow outgoing
    ufw enable
}

configure_firewall_centos() {
    local ssh_subnet=$1

    firewall-cmd --permanent --zone=public --add-rich-rule="rule family='ipv4' source address='$ssh_subnet' port port=22 protocol=tcp accept"
    firewall-cmd --permanent --zone=public --add-service=ssh
    firewall-cmd --permanent --zone=public --add-service=dns
    firewall-cmd --reload
}

# Function to ensure telnet is disabled
disable_telnet() {
    if [ -x "$(command -v systemctl)" ]; then
        systemctl disable telnet.socket
        systemctl stop telnet.socket
    elif [ -x "$(command -v chkconfig)" ]; then
        chkconfig telnet off
        service telnet stop
    fi
}

# Main script execution
main() {
    check_root "$@"
    
    read -p "Do you want to install necessary packages? (y/n): " install_choice
    if [[ "$install_choice" == "y" || "$install_choice" == "Y" ]]; then
        install_packages
    fi
    
    read -p "Do you want to configure the network settings? (y/n): " network_choice
    if [[ "$network_choice" == "y" || "$network_choice" == "Y" ]]; then
        get_network_config
        configure_network
    fi
    
    read -p "Do you want to configure SSH? (y/n): " ssh_choice
    if [[ "$ssh_choice" == "y" || "$ssh_choice" == "Y" ]]; then
        configure_ssh
    fi
    
    read -p "Do you want to create a new user? (y/n): " user_choice
    if [[ "$user_choice" == "y" || "$user_choice" == "Y" ]]; then
        get_user_config
        create_user
    fi
    
    read -p "Do you want to configure firewall rules? (y/n): " firewall_choice
    if [[ "$firewall_choice" == "y" || "$firewall_choice" == "Y" ]]; then
        get_firewall_config
        configure_firewall
    fi

    disable_telnet

    echo "Setup completed successfully."
}

main "$@"
