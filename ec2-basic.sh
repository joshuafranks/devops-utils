#!/bin/bash
set -e 

function main() {
    read -rp $'Provide a username for the new sudo user:\n>' username
    promptForPassword

    # create user
    echo "Creating user..."
    sudo useradd -m -G sudo "${username}"
    echo "${username}:${password}" | sudo chpasswd
    echo "User created!"

    # add SSH key
    read -rp $'Paste in the public SSH key for the new user:\n>' sshKey

    echo "Adding SSH key..."
    execAsUser "${username}" "cd /home/${username}; mkdir .ssh; touch .ssh/authorized_keys;"
    echo "${sshKey}" | sudo tee -a /home/"${username}"/.ssh/authorized_keys
    sudo chmod 600 /home/"${username}"/.ssh/authorized_keys
    echo "SSH key added!"

    ### secure SSH
    echo "Securing SSH..."
    sudo sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin no/" /etc/ssh/sshd_config
    sudo sed -i "s/#PermitEmptyPasswords no/PermitEmptyPasswords no/" /etc/ssh/sshd_config
    sudo systemctl restart ssh
    echo "SSH secured!"

    ### fail2ban
    echo "Installing fail2ban..."
    sudo apt-get update && sudo apt-get install -y fail2ban
    echo "fail2ban installed!"

    ### firewall
    echo "Configuring firewall..."
    sudo iptables -A INPUT -i lo -j ACCEPT
    sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    sudo iptables -A INPUT -j DROP
    sudo apt-get update && sudo apt-get install -y iptables-persistent
    sudo iptables-save | sudo tee /etc/iptables/rules.v4
    sudo service iptables restart
    echo "Firewall configured!"

    ### install nginx & php-fpm
    echo "Installing Nginx & php-fpm..."
    sudo apt-get update && sudo apt-get install -y nginx
    sudo apt-get update && sudo apt-get install -y php-fpm
    sudo apt-get install -y php-json php-xml
    echo "Nginx & php-fpm installed!"

    ### install mysql
    echo "Installing MySQL..."
    sudo apt-get update && sudo apt-get install -y mysql-server
    sudo mysql_secure_installation
    sudo apt-get update && sudo apt-get install -y php-mysql
    sudo mysql -e "UPDATE mysql.user SET plugin = 'mysql_native_password' WHERE User = 'root'; FLUSH PRIVILEGES;";
    echo "Installed MySQL!"

    echo $'\n\n\nInitial configuration complete.'
}

function promptForPassword() {
  PASSWORDS_MATCH=0
  while [ "${PASSWORDS_MATCH}" -eq "0" ]; do
      read -s -rp "Enter new UNIX password:" password
      printf "\n"
      read -s -rp "Retype new UNIX password:" password_confirmation
      printf "\n"

  if [[ "${password}" != "${password_confirmation}" ]]; then
      echo "Passwords do not match! Please try again."
  else
      PASSWORDS_MATCH=1
  fi
  done
}

function execAsUser() {
    local username=${1}
    local exec_command=${2}

    sudo -u "${username}" -H bash -c "${exec_command}"
}

main
