#!/bin/bash

set -e

function main() {
  read -rp $'Assign a friendly name to your project:\n' friendly_name

  read -rp $'Enter repository URL (e.g. joshuafranks/project.git); if the repository is private, you must configure a deploy key for this instance:\n' repository_url
  sudo chown $USER:$USER /var/www/
  git clone git@github.com:"${repository_url}" /var/www/"${friendly_name}"
  cd /var/www/"${friendly_name}"
  composer install --prefer-dist --no-scripts
  sudo chown -R $USER:www-data storage
  sudo chmod 775 storage && chmod 775 bootstrap/cache
  cp .env.example .env
  php artisan key:generate

  read -rp $'Specify the server_name to be used in the nginx configuration (no www):\n' server_name

  initialNginxConfiguration
  sudo rm -rf /etc/nginx/sites-available/default && sudo rm -rf /etc/nginx/sites-enabled/default
  sudo ln -s /etc/nginx/sites-available/${server_name} /etc/nginx/sites-enabled/${server_name}
  sudo systemctl restart nginx

  sudo apt update && sudo apt install snapd
  sudo snap install --classic certbot
  sudo certbot certonly --nginx

  sslNginxConfiguration

  sudo systemctl restart nginx

  echo $'\n\n\nDeployment complete!'
}

function initialNginxConfiguration () {
  echo "
    server {
      listen 80;
      listen [::]:80;
      server_name ${server_name} www.${server_name};
      root /var/www/${friendly_name}/public/;
      index index.php;

      location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
      }

      if (!-d \$request_filename) {
        rewrite     ^/(.+)/$ /$1 permanent;
      }

      location ~* \.php$ {
        fastcgi_pass                unix:/var/run/php/php7.4-fpm.sock;
        fastcgi_index               index.php;
        fastcgi_split_path_info     ^(.+\.php)(.*)$;
        include                     /etc/nginx/fastcgi_params;
        fastcgi_param               SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      }

      location ~ /\.ht {
        deny all;
      }
    }
  " | sudo tee /etc/nginx/sites-available/"${server_name}"
}

function sslNginxConfiguration() {
  echo "
    server {
      listen 80;
      listen [::]:80;
      server_name ${server_name} www.${server_name};
      root /var/www/${friendly_name}/public/;
      index index.php;

      listen 443 ssl;
		  listen [::]:443 ssl ipv6only=on;

      ssl_certificate /etc/letsencrypt/live/${server_name}/fullchain.pem;
      ssl_certificate_key /etc/letsencrypt/live/${server_name}/privkey.pem;
      include /etc/letsencrypt/options-ssl-nginx.conf;
      ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

      location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
      }

      if (!-d \$request_filename) {
        rewrite     ^/(.+)/$ /$1 permanent;
      }

      location ~* \.php$ {
        fastcgi_pass                unix:/var/run/php/php7.4-fpm.sock;
        fastcgi_index               index.php;
        fastcgi_split_path_info     ^(.+\.php)(.*)$;
        include                     /etc/nginx/fastcgi_params;
        fastcgi_param               SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      }

      location ~ /\.ht {
        deny all;
      }

      if (\$scheme != 'https') {
        return 301 https://\$host\$request_uri;
      }
    }
  " | sudo tee /etc/nginx/sites-available/"${server_name}"
}

main