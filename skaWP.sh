#!/bin/bash
apt update
apt install apache2 -y
apt install awscli -y

systemctl start apache2
systemctl enable apache2

$rdsEndPoint=$(aws rds describe-db-instances --query "DBInstances[*].Endpoint.Address" --output text)

$wppwd=$(aws resolve-alias --alias-id "WordpressDBAuth")

apt install mysql-server -y
mysql -u root <<_EOF_
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
_EOF_

mysql -u root <<_EOF_

CREATE DATABASE skawordpress;
GRANT ALL PRIVILEGES ON skawordpress.* TO 'skawordpress'@$rdsEndPoint IDENTIFIED BY "$wppwd";
FLUSH PRIVILEGES;
_EOF_

apt install php libapache2-mod-php php-mysql -y
apt install php-curl php-gd php-xml php-mbstring php-xmlrpc php-zip php-soap php-intl -y

cd /var/www/html

wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* /var/www/html/
rm -rf wordpress
chmod -R 755 wp-content
chown -R apache:apache wp-content
cp wp-config-sample.php wp-config.php
sed -i 's/database_name_here/skawordpress/g' wp-config.php
sed -i 's/username_here/skawordpress/g' wp-config.php
sed -i "s/password_here/$wppwd/g" wp-config.php

HOST=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)

sudo touch /etc/apache2/sites-available/$HOST.conf

sudo sh -c "cat << EOF > /etc/apache2/sites-available/$HOST.conf
<VirtualHost *:80>

ServerAdmin admin@$HOST
ServerName $HOST
ServerAlias www.$HOST
DocumentRoot /var/www/html/wordpress

<Directory /var/www/html/wordpress>
     Options Indexes FollowSymLinks
     AllowOverride All
     Require all granted
</Directory>

ErrorLog ${APACHE_LOG_DIR}/$HOST_error.log 
CustomLog ${APACHE_LOG_DIR}/$HOST_access.log combined 
</VirtualHost>
EOF"

sudo ln -s /etc/apache2/sites-available/$HOST.conf /etc/apache2/sites-enabled/$HOST.conf

rm /var/www/html/index.html
echo "healthy" > /var/www/html/healthy.html

sudo service apache2 reload
