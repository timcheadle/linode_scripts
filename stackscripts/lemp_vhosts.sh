#!/bin/bash
#
# Basic Linode setup
# Author: Tim Cheadle (tim@fourspace.com)
#
# Does the following:
# - Installs and changes default editor to vim
# - Sets timezone to US/Eastern
# - Adds a user account
# - Adds the user to sudoers
# - Adds the user's public SSH key to ~/.ssh/authorized_keys
# - Secures SSHd config (passwordless, no root)
# - Edits hostname
# - Sets up iptables
# - Installs the following:
#	- LEMP stack
#   - Virtual Host for primary domain
#
# Includes and user-defined fields
#
# <udf name="system_hostname" label="Hostname for system" default="" />
# <udf name="primary_domain" label="Primary domain, used for virtual host setup" default="" />
#
# - User Security
#   http://www.linode.com/stackscripts/view/?StackScriptID=165
#
# <udf name="user_name" label="Unprivileged User Account" />
# <udf name="user_password" label="Unprivileged User Password" /># <udf name="user_sshkey" label="Public Key for User" default="" />
# <udf name="sshd_port" label="SSH Port" default="22" />
# <udf name="sshd_protocol" label="SSH Protocol" oneOf="1,2,1 and 2" default="2" />
# <udf name="sshd_permitroot" label="SSH Permit Root Login" oneof="No,Yes" default="No" />
# <udf name="sshd_passwordauth" label="SSH Password Authentication" oneOf="No,Yes" default="No" />
# <udf name="sshd_group" label="SSH Allowed Groups" default="sshusers" example="List of groups seperated by spaces" />
# <udf name="sudo_usergroup" label="Usergroup to use for Admin Accounts" default="wheel" />
# <udf name="sudo_passwordless" label="Passwordless Sudo" oneof="Require Password,Do Not Require Password", default="Require Password" />
#
# - LEMP Stack
#   http://www.linode.com/stackscripts/view/?StackScriptID=41
#
# <udf name="DB_PASSWORD" Label="MySQL root password" />
#

# Set up user security
source <ssinclude StackScriptID="1">
source <ssinclude StackScriptID="165">


# Set up LEM stack (PHP is later)
source <ssinclude StackScriptID="41"> 
lemp_system_update_aptitude
lemp_mysql_install


# Install nginx
aptitude -y install python-software-properties
add-apt-repository ppa:nginx/stable
aptitude update
aptitude -y install nginx nginx-light
/etc/init.d/nginx start



# Set timezone
echo 'US/Eastern' > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata


# Edit hostname
echo "$SYSTEM_HOSTNAME" > /etc/hostname
sed -e "s/127.0.0.1 localhost/127.0.0.1 localhost $SYSTEM_HOSTNAME/" < /etc/hosts > /etc/hosts.tmp
mv /etc/hosts.tmp /etc/hosts
/etc/init.d/hostname restart


# Set up iptables config
cat > /etc/iptables.test.rules <<EOF
*filter

#  Allows all loopback (lo0) traffic and drop all traffic to 127/8 that doesn't use lo0
-A INPUT -i lo -j ACCEPT
-A INPUT ! -i lo -d 127.0.0.0/8 -j REJECT

#  Accepts all established inbound connections
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

#  Allows all outbound traffic
#  You can modify this to only allow certain traffic
-A OUTPUT -j ACCEPT

# Allows HTTP and HTTPS connections from anywhere (the normal ports for websites)
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT
#-A INPUT -p tcp -m tcp --dport 20:21 -j ACCEPT

#  Allows SSH connections
#
# THE -dport NUMBER IS THE SAME ONE YOU SET UP IN THE SSHD_CONFIG FILE
#
-A INPUT -p tcp -m state --state NEW --dport 22 -j ACCEPT

# Allow ping
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT

# log iptables denied calls
-A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables denied: " --log-level 7

# Reject all other inbound - default deny unless explicitly allowed policy
-A INPUT -j REJECT
-A FORWARD -j REJECT

COMMIT
EOF

# Set up iptables rules
/sbin/iptables -F
/sbin/iptables-restore < /etc/iptables.test.rules
/sbin/iptables-save > /etc/iptables.up.rules

# Set up iptables boot script
cat > /etc/network/if-pre-up.d/iptables.sh <<EOF
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.up.rules
EOF

chmod +x /etc/network/if-pre-up.d/iptables.sh


# Set up PHP package depot
cat >> /etc/apt/sources.list <<EOF

# PHP package depot
deb http://php53.dotdeb.org stable all
deb-src http://php53.dotdeb.org stable all
EOF

# Add the PHP depot's GPG key
cd /tmp
wget http://www.dotdeb.org/dotdeb.gpg
cat dotdeb.gpg | apt-key add -
rm dotdeb.gpg
aptitude -y update


# Install PHP packages
wget http://us.archive.ubuntu.com/ubuntu/pool/main/k/krb5/libkrb53_1.6.dfsg.4~beta1-5ubuntu2_i386.deb
wget http://us.archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu38_3.8-6ubuntu0.2_i386.deb
dpkg -i *.deb
aptitude -y install php5-cli php5-common php5-suhosin
aptitude -y install php5-fpm php5-cgi php5-mysql

# Fix PHP-fpm config
#
# sockets > ports. Using the 127.0.0.1:9000 stuff needlessly introduces TCP/IP overhead.
sed -i 's/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/' /etc/php5/fpm/php5-fpm.conf
#
# nice strict permissions
sed -i 's/;listen.owner = www-data/listen.owner = www-data/' /etc/php5/fpm/php5-fpm.conf
sed -i 's/;listen.group = www-data/listen.group = www-data/' /etc/php5/fpm/php5-fpm.conf
sed -i 's/;listen.mode = 0666/listen.mode = 0600/' /etc/php5/fpm/php5-fpm.conf
#
# these settings are fairly conservative and can probably be increased without things melting
sed -i 's/pm.max_children = 50/pm.max_children = 12/' /etc/php5/fpm/php5-fpm.conf
sed -i 's/pm.start_servers = 20/pm.start_servers = 4/' /etc/php5/fpm/php5-fpm.conf
sed -i 's/pm.min_spare_servers = 5/pm.min_spare_servers = 2/' /etc/php5/fpm/php5-fpm.conf
sed -i 's/pm.max_spare_servers = 35/pm.max_spare_servers = 4/' /etc/php5/fpm/php5-fpm.conf
sed -i 's/pm.max_requests = 0/pm.max_requests = 500/' /etc/php5/fpm/php5-fpm.conf

# Restart everything
/etc/init.d/nginx restart



# Set up nginx virtual host
mkdir -p /srv/www/$PRIMARY_DOMAIN/public_html
mkdir -p /srv/www/$PRIMARY_DOMAIN/logs

chgrp -R www-data /srv/www
chown -R $USER_NAME /srv/www/$PRIMARY_DOMAIN
chmod 770 /srv/www/$PRIMARY_DOMAIN/logs

cat > /etc/nginx/sites-available/$PRIMARY_DOMAIN << EOF
server {
    listen 80;
    server_name www.$PRIMARY_DOMAIN $PRIMARY_DOMAIN;
    access_log /srv/www/$PRIMARY_DOMAIN/logs/access.log;
    error_log /srv/www/$PRIMARY_DOMAIN/logs/error.log;

    location / {
        root  /srv/www/$PRIMARY_DOMAIN/public_html;
        index index.html index.htm index.php;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass   unix:/var/run/php-fpm.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  /srv/www/$PRIMARY_DOMAIN/public_html\$fastcgi_script_name;
    }
}
EOF

ln -s /etc/nginx/sites-available/$PRIMARY_DOMAIN /etc/nginx/sites-enabled/ 
/etc/init.d/nginx restart


# Set up virtualhost log rotation
sed -i 's/^\/var\/log\/nginx\/\*\.log {$/\/var\/log\/nginx\/\*\.log \/srv\/www\/\*\/logs\/\*\.log {/' /etc/logrotate.d/nginx
