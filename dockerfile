FROM debian:12

RUN apt-get update && apt-get install -y
RUN apt -y install default-libmysqlclient-dev htop sngrep lame ffmpeg expect
RUN apt-get install -y cron fail2ban openssh-server apache2 mariadb-server mariadb-client bison flex \
    php8.2 php8.2-curl php8.2-cli php8.2-common php8.2-mysql php8.2-gd php8.2-mbstring php8.2-intl \
    php8.2-xml php-pear curl sox libncurses5-dev libssl-dev mpg123 libxml2-dev libnewt-dev sqlite3 \
    libsqlite3-dev pkg-config automake libtool autoconf git unixodbc-dev uuid uuid-dev libasound2-dev \ 
    libogg-dev libvorbis-dev libicu-dev libcurl4-openssl-dev odbc-mariadb libical-dev libneon27-dev \
    libsrtp2-dev libspandsp-dev sudo subversion libtool-bin python-dev-is-python3 unixodbc vim wget \
    libjansson-dev software-properties-common nodejs npm ipset iptables fail2ban php-soap

WORKDIR /usr/src
RUN wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-22.1.0.tar.gz 
RUN tar xvf asterisk-22.1.0.tar.gz
RUN rm -rf asterisk-22.1.0.tar.gz

WORKDIR /usr/src/asterisk-22.1.0
RUN pwd
RUN ./contrib/scripts/get_mp3_source.sh
RUN ./contrib/scripts/install_prereq install
RUN ./configure  --libdir=/usr/lib64 --with-pjproject-bundled --with-jansson-bundled
RUN make menuselect
RUN make
RUN make install
RUN make samples
RUN make config
RUN ldconfig


RUN groupadd asterisk
RUN useradd -r -d /var/lib/asterisk -g asterisk asterisk
RUN usermod -aG audio,dialout asterisk
RUN chown -R asterisk:asterisk /etc/asterisk
RUN chown -R asterisk:asterisk /var/lib/asterisk
RUN chown -R asterisk:asterisk /var/log/asterisk
RUN chown -R asterisk:asterisk /var/spool/asterisk
RUN chown -R asterisk:asterisk /usr/lib64/asterisk

RUN sed -i 's|#AST_USER|AST_USER|' /etc/default/asterisk
RUN sed -i 's|#AST_GROUP|AST_GROUP|' /etc/default/asterisk
RUN sed -i 's|;runuser|runuser|' /etc/asterisk/asterisk.conf
RUN sed -i 's|;rungroup|rungroup|' /etc/asterisk/asterisk.conf
RUN echo "/usr/lib64" >> /etc/ld.so.conf.d/x86_64-linux-gnu.conf
RUN ldconfig

# Configure apache
RUN sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/8.2/apache2/php.ini \
    && sed -i 's/\(^memory_limit = \).*/\1256M/' /etc/php/8.2/apache2/php.ini \
    && sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf \
    && sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
    && sed -i 's/VirtualHost \*:80/VirtualHost \*:8082/' /etc/apache2/sites-available/000-default.conf \
    && sed -i 's/Listen 80/Listen 8082/' /etc/apache2/ports.conf



RUN a2enmod rewrite
RUN service apache2 restart
RUN rm /var/www/html/index.html


RUN cat <<EOF > /etc/odbcinst.ini
[MySQL]
Description = ODBC for MySQL (MariaDB)
Driver = /usr/lib/x86_64-linux-gnu/odbc/libmaodbc.so
FileUsage = 1
EOF

RUN cat <<EOF > /etc/odbc.ini
[MySQL-asteriskcdrdb]
Description = MySQL connection to 'asteriskcdrdb' database
Driver = MySQL
Server = localhost
Database = asteriskcdrdb
Port = 3306
Socket = /var/run/mysqld/mysqld.sock
Option = 3
EOF

WORKDIR /usr/local/src
RUN wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest-EDGE.tgz
RUN tar zxvf freepbx-17.0-latest-EDGE.tgz
RUN rm -rf freepbx-17.0-latest-EDGE.tgz



WORKDIR /usr/local/src/freepbx/


RUN systemctl enable mariadb.service

COPY ./init_install.sh .
RUN chmod +x ./init_install.sh 
RUN ./init_install.sh

RUN cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

RUN cat <<EOF > /etc/fail2ban/jail.local
[sshd]
enabled  = false

[asterisk]
enabled  = true
backend=systemd
port     = 5060,5061
filter   = asterisk
logpath  = /var/log/asterisk/full
maxretry = 3
findtime = 600
bantime  = 3600
EOF

RUN chmod 644 /var/log/asterisk/full

##################
# Cleanup
##################
RUN apt-get remove -y --purge autoconf \
    automake \
    bison \
    flex \
    git \
    libcurl4-openssl-dev \
    openssh-server \
    subversion \
    libmysqlclient-dev \
    libncurses5-dev \
    libssl-dev \
    libxml2-dev \
    libnewt-dev \
    libsqlite3-dev \
    unixodbc-dev \
    uuid-dev \
    libasound2-dev \
    libogg-dev \
    libvorbis-dev \
    libicu-dev \
    libical-dev \
    libneon27-dev \
    libsrtp2-dev \
    libspandsp-dev \
    python-dev \
    libjansson-dev

RUN apt-get clean && rm -rf /var/lib/apt/lists/\* /tmp/\* /var/tmp/*

EXPOSE 80
EXPOSE 5060/udp
EXPOSE 10000-20000/udp
VOLUME ["/etc/asterisk","/etc/apache2","/var/www/html","/var/lib/mysql","/var/spool/asterisk","/var/lib/asterisk"]


CMD service apache2 start && service mariadb start && service fail2ban start && fwconsole start -q & tail -f /dev/null