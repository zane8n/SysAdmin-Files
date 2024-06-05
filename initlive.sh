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
    apt-get install -y netplan.io openssh-server vim
}

install_packages_centos() {
    yum install -y epel-release
    yum install -y NetworkManager openssh-server vim
    systemctl enable NetworkManager
    systemctl start NetworkManager
}

install_packages_arch() {
    pacman -Sy --noconfirm netctl openssh vim
}

# Function to configure network settings based on the distribution
configure_network() {
    read -p "Enter the static IP address (e.g., 192.168.3.230/24): " static_ip
    read -p "Enter the gateway IP address (e.g., 192.168.3.1): " gateway_ip
    read -p "Enter the DNS IP address (e.g., 1.1.1.1): " dns_ip

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

# Function to create a new user
create_user() {
    read -p "Enter the username: " username
    read -sp "Enter the password: " password
    echo
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
}

# Main script execution
main() {
    check_root "$@"
    install_packages
    configure_network
    configure_ssh
    create_user
    echo "Setup completed successfully."
}

main "$@"
