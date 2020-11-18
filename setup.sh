#!/bin/bash

# Enter the username
username=""
while [[ $username = "" ]]; do
    echo "Enter the proxy username"
    read -p "username: " username
    if [ -z "$username" ]; then
      echo "The username cannot be empty"
    else
        # Check if user already exists.
        grep -wq "$username" /etc/passwd
        if [ $? -eq 0 ]
            then
            echo "User $username already exists"
            username=
        fi
    fi
done

# Enter the proxy user password
password=""
while [[ $password = "" ]]; do
    echo "Enter the proxy password"
    read -p "password: " password
    if [ -z "$password" ]; then
        echo "Password cannot be empty"
    fi
done

# Install squid3, dante-server, wget and apache2-utils for htpasswd
apt-get install squid3 wget dante-server apache2-utils -y

# determine default int
default_int="$(ip route list |grep default |grep -o -P '\b[a-z]+\d+\b')" #Because net-tools in debian, ubuntu are obsolete already
# determine external ip
external_ip="$(wget ipinfo.io/ip -q -O -)"

# create system user for dante
useradd --shell /usr/sbin/nologin $username && echo "$username:$password" | chpasswd

# add user for squid
# avoid rewrite users
touch /etc/squid/passwords
# Set user and pass
htpasswd -ib /etc/squid/passwords $username $password

# Squid configuration
cat <<EOT > /etc/squid/squid.conf
#Auth
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
acl ncsa_users proxy_auth REQUIRED

#Recommended minimum configuration:
dns_v4_first on
acl manager proto cache_object
acl localhost src 127.0.0.1/32
acl to_localhost dst 127.0.0.0/8 # systemctl status squid.service after installation squid and danted by this script
                                 # WARNING: because of this '127.0.0.0/8' is ignored to keep splay tree searching predictable
                                 # WARNING: You should probably remove '127.0.0.0/8' from the ACL named 'to_localhost'
acl localnet src 0.0.0.0/8 192.168.100.0/24 192.168.101.0/24
acl SSL_ports port 443
acl Safe_ports port 80      # http
acl Safe_ports port 21        # ftp
acl Safe_ports port 443        # https
acl Safe_ports port 70        # gopher
acl Safe_ports port 210        # wais
acl Safe_ports port 1025-65535    # unregistered ports
acl Safe_ports port 280        # http-mgmt
acl Safe_ports port 488        # gss-http
acl Safe_ports port 591        # filemaker
acl Safe_ports port 777        # multiling http

acl CONNECT method CONNECT

http_access allow manager localhost
http_access deny manager
http_access deny !Safe_ports

http_access deny to_localhost
icp_access deny all
htcp_access deny all

http_port 9099
hierarchy_stoplist cgi-bin ? # systemctl status squid.service after installation squid and danted by this script
                             # ERROR: Directive 'hierarchy_stoplist' is obsolete.
access_log /var/log/squid/access.log squid


#Suggested default:
refresh_pattern ^ftp:        1440    20%    10080
refresh_pattern ^gopher:    1440    0%    1440
refresh_pattern -i (/cgi-bin/|\?) 0 0% 0
refresh_pattern .        0    20%    4320
# Leave coredumps in the first cache dir
coredump_dir /var/spool/squid

# Allow all machines to all sites
http_access allow ncsa_users
#http_access allow all

#Headers
via off
forwarded_for off
follow_x_forwarded_for deny all
request_header_access X-Forwarded-For deny all
header_access X_Forwarded_For deny all          # systemctl status squid.service after installation squid and danted by this script
                                                # ERROR: Directive 'header_access' is obsolete.
EOT
systemctl restart squid.service

# dante conf
cat <<EOT > /etc/danted.conf
logoutput: /var/log/socks.log
internal: 0.0.0.0 port = 9098
external: $default_int
socksmethod: username
clientmethod: none
user.privileged: root
user.notprivileged: nobody
user.libwrap: nobody
client pass {
        from: 0.0.0.0/0 port 1-65535 to: 0.0.0.0/0
        log: connect disconnect error
}
socks pass {
        from: 0.0.0.0/0 to: 0.0.0.0/0
        protocol: tcp udp
}
EOT
# And we have a little bit problem with this message from `systemctl status danted.service`
#               danted.service: Failed to read PID from file /var/run/danted.pid: Invalid argument
systemctl restart danted.service

#information
echo "--------------------------------------------------------------------------------------------------"
echo "--------------------------------------------------------------------------------------------------"
echo "--------------------------------------------------------------------------------------------------"
echo "Proxy IP: $external_ip"
echo "HTTP port: 9099"
echo "SOCKS5 port: 9098"
echo "Username: $username"
echo "Password: $password"
