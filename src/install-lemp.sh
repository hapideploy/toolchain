#!/usr/bin/env bash

# IO ===========================================================================

io_line() {
    if [ "$B_ANSI" = 'yes' ]; then
        B_IO_LINE=$(echo "$1" | \
            sed 's/<success>/\\e[32m/g' | \
            sed 's/<\/success>/\\e[0m/g' | \
            sed 's/<info>/\\e[34m/g' | \
            sed 's/<\/info>/\\e[0m/g' | \
            sed 's/<comment>/\\e[33m/g' | \
            sed 's/<\/comment>/\\e[0m/g' | \
            sed 's/<error>/\\e[31m/g' | \
            sed 's/<\/error>/\\e[0m/g'
        )
    else
        B_IO_LINE=$(echo "$1" | \
            sed 's/<success>//g' | \
            sed 's/<\/success>//g' | \
            sed 's/<info>//g' | \
            sed 's/<\/info>//g' | \
            sed 's/<comment>//g' | \
            sed 's/<\/comment>//g' | \
            sed 's/<error>//g' | \
            sed 's/<\/error>//g'
        )
    fi

    echo -e "$B_IO_LINE"
}

io_success() {
    io_line "<success>$1</success>"
}

io_info() {
    io_line "<info>$1</info>"
}

io_comment() {
    io_line "<comment>$1</comment>"
}

io_error() {
    io_line "<error>$1</error>"
}

io_print_success() {
    if [ "$B_ANSI" = 'yes' ]; then
        io_line "\n  \e[42m SUCCESS \e[0m $1\n"
    else
        io_line "\n [SUCCESS] $1\n"
    fi
}

io_print_info() {
    if [ "$B_ANSI" = 'yes' ]; then
        io_line "\n  \e[44m INFO \e[0m $1\n"
    else
        io_line "\n [INFO] $1\n"
    fi
}

io_print_warning() {
    if [ "$B_ANSI" = 'yes' ]; then
        io_line "\n  \e[43m WARNING \e[0m $1\n"
    else
        io_line "\n [WARNING] $1\n"
    fi
}

io_print_error() {
    if [ "$B_ANSI" = 'yes' ]; then
        io_line "\n  \e[41m ERROR \e[0m $1\n"
    else
        io_line "\n [ERROR] $1\n"
    fi
}

# Check ========================================================================

check_root_privileges() {
    L_USER=$(whoami)
    if [ "$L_USER" != 'root' ]; then
        io_print_error 'Please run this command/script as root.'
        exit 1
    fi
}

check_supported_os() {
    if [ "$H_DISABLE_OS_CHECK" = 'yes' ]; then
        return
    fi

    OS_DISTRO_NAME='unsupported'
    OS_RELEASE_NAME='unsupported'

    # If lsb_release exists, we'll it to determine OS_DISTRO_NAME and OS_RELEASE_NAME.
    if [ -f /usr/bin/lsb_release ]; then
        OS_DISTRO_NAME=${OS_DISTRO_NAME:-$(lsb_release -is)}
        OS_RELEASE_NAME=${OS_RELEASE_NAME:-$(lsb_release -cs)}
    # If /etc/os-release exists, we'll it to determine OS_DISTRO_NAME and OS_RELEASE_NAME.
    elif [ -f /etc/os-release ]; then
        if [ -n "$(cat /etc/os-release | grep ubuntu)" ]; then
            OS_DISTRO_NAME='ubuntu'
            OS_RELEASE_NAME=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d'=' -f2)
        fi
    fi

    case "${OS_DISTRO_NAME}" in
        "Ubuntu" | "ubuntu")
            DISTRO_NAME="ubuntu"
            case "${OS_RELEASE_NAME}" in
                "noble" | "jammy" | "focal")
                    RELEASE_NAME="${OS_RELEASE_NAME}"
                ;;
                *)
                    RELEASE_NAME="unsupported"
                ;;
            esac
        ;;
        *)
            DISTRO_NAME="unsupported"
        ;;
    esac

    if [[ "${DISTRO_NAME}" == "unsupported" || "${RELEASE_NAME}" == "unsupported" ]]; then
        io_comment "This Linux distribution isn't supported yet."
        io_comment "If you'd like it to be, let us know!"
        io_comment "👉🏻 https://github.com/hapideploy/hapideploy/issues"
        exit 1
    fi
}

# Manage =======================================================================

install_manage_user() {
    L_USER="$1"
    L_GROUP="$2"
    L_PASSWORD="$3"

    if id "$L_USER" >/dev/null 2>&1; then
        io_info "The user \"$L_USER\" already exists."
    else
        adduser --disabled-password --gecos "Using $L_USER instead of root" "${L_USER}"

        usermod --password $(echo "${L_PASSWORD}" | openssl passwd -1 -stdin) "${L_USER}"

        usermod -aG sudo "$L_USER"
    fi

    rm -rf /etc/ssh/sshd_config.d/*

    touch "/etc/ssh/sshd_config.d/default.conf"

    chmod 600 "/etc/ssh/sshd_config.d/default.conf"

    export SSHD_CONFIG="PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes"
    if ! echo "${SSHD_CONFIG}" | tee "/etc/ssh/sshd_config.d/default.conf"; then
        echo "butlersh.ERROR: Can NOT configure SSH!" && exit 1
    fi

    mkdir -p "/home/$L_USER/.ssh"

    touch "/home/$L_USER/.ssh/authorized_keys"

    chmod 660 "/home/$L_USER/.ssh/authorized_keys"

    # Because DigitalOcean, Hetzner Cloud,... allows to SSH using root, so I just copy these keys.
    # Thus, right after provision process, I can SSH using forge without adding additional SSH keys.
    if [ -f /root/.ssh/authorized_keys ]; then
        cat /root/.ssh/authorized_keys > "/home/$L_USER/.ssh/authorized_keys"
    fi

    chown -R "$L_USER":"$L_GROUP" "/home/$L_USER/.ssh"

    systemctl restart ssh

    apt-get update

    apt-get install -y software-properties-common curl git unzip zip fail2ban

    systemctl restart fail2ban

    apt-get upgrade -y

    apt-get autoremove -y

    apt-get autoclean -y

    mkdir -p /var/lib/hapideploy

    if [ ! -f /var/lib/hapideploy/security.txt ]; then
        touch /var/lib/hapideploy/security.txt
    fi

    echo "username:$L_USER" >> /var/lib/hapideploy/security.txt
    echo "password:$L_PASSWORD" >> /var/lib/hapideploy/security.txt
}

install_run_user() {
    L_USER="$1"
    L_GROUP="$2"
    L_PASSWORD="$3"

    if id "$L_USER" >/dev/null 2>&1; then
        io_info "The user \"$L_USER\" already exists."
    else
        adduser --disabled-password --gecos "This is a run user" "${L_USER}"

        usermod --password $(echo "${L_PASSWORD}" | openssl passwd -1 -stdin) "${L_USER}"

        usermod -g "$L_GROUP" "$L_USER"
    fi
}

# Nginx ========================================================================

install_nginx() {
    L_USER="$1"

    L_CONFIG_URL="https://raw.githubusercontent.com/hapideploy/toolchain/main/config"

    io_print_info "Start installing Nginx"

    apt-get install -y software-properties-common

    add-apt-repository -y ppa:ondrej/nginx

    # Install nginx with certbot to use free SSL via Letsencrypt.
    apt-get install -y nginx certbot python3-certbot-nginx

    if [ -d /etc/nginx ]; then
        rm -rf /etc/nginx.old

        mv /etc/nginx /etc/nginx.old
    fi

    git clone https://github.com/h5bp/server-configs-nginx.git /etc/nginx

    mkdir -p /etc/nginx/extra.d

    wget -O fastcgi.conf "$L_CONFIG_URL/fastcgi.conf" --quiet
    wget -O fastcgi-php.conf "$L_CONFIG_URL/fastcgi-php.conf" --quiet

    mv fastcgi.conf /etc/nginx/extra.d/fastcgi.conf
    mv fastcgi-php.conf /etc/nginx/extra.d/fastcgi-php.conf

    sed -i "s/www-data/${L_USER}/g" /etc/nginx/nginx.conf;

    systemctl restart nginx

    io_print_info "Finished installing Nginx"
}

# PHP ==========================================================================

function install_php() {
    L_USER="$1"
    L_GROUP="$2"
    L_PHP_VERSION="$3"

    SUPPORTED_PHP_VERSIONS=("8.0" "8.1" "8.2" "8.3" "8.4")

    if [ -z "$L_PHP_VERSION" ]; then
        io_print_error 'The PHP version is required. Use --help for more details.' && exit 1
    fi

    if [[ ${SUPPORTED_PHP_VERSIONS[@]} =~ $VALUE ]]; then
        io_print_info "Installing PHP $L_PHP_VERSION"
    else
        io_print_error "The PHP version <comment>$L_PHP_VERSION</comment> is invalid or unsupported." && exit 1
    fi

    apt-get update && apt-get install -y locales && locale-gen en_US.UTF-8

    locale-gen en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    apt-get install -y software-properties-common

    # TODO: Check if group exists.

    add-apt-repository -y ppa:ondrej/php

    apt-get update

    apt-get install -y \
        php"${L_PHP_VERSION}"-cli \
        php"${L_PHP_VERSION}"-curl \
        php"${L_PHP_VERSION}"-bcmath \
        php"${L_PHP_VERSION}"-fpm \
        php"${L_PHP_VERSION}"-gd \
        php"${L_PHP_VERSION}"-imap \
        php"${L_PHP_VERSION}"-intl \
        php"${L_PHP_VERSION}"-mbstring \
        php"${L_PHP_VERSION}"-mcrypt \
        php"${L_PHP_VERSION}"-mysql \
        php"${L_PHP_VERSION}"-pgsql \
        php"${L_PHP_VERSION}"-sqlite3 \
        php"${L_PHP_VERSION}"-xml \
        php"${L_PHP_VERSION}"-zip

    php -r "readfile('http://getcomposer.org/installer');" | php -- --install-dir=/usr/local/bin/ --filename=composer

    L_POOL_CONFIG_FILE="/etc/php/${L_PHP_VERSION}/fpm/pool.d/${L_USER}.conf"

    rm -f $L_POOL_CONFIG_FILE

    cp "/etc/php/${L_PHP_VERSION}/fpm/pool.d/www.conf" $L_POOL_CONFIG_FILE

    sed -i "s/\[www\]/\[${L_USER}\ PHP ${L_PHP_VERSION}]/g" $L_POOL_CONFIG_FILE;
    sed -i "s/user = www-data/user = ${L_USER}/g" $L_POOL_CONFIG_FILE;
    sed -i "s/group = www-data/group = ${L_GROUP}/g" $L_POOL_CONFIG_FILE;
    sed -i "s/php$L_PHP_VERSION-fpm.sock/$L_USER-php$L_PHP_VERSION-fpm.sock/g" $L_POOL_CONFIG_FILE;

    # Change the pool name
    sed -i "s/\[www\]/\[PHP $L_PHP_VERSION\]/g" "/etc/php/$L_PHP_VERSION/fpm/pool.d/www.conf";

    systemctl restart php"${L_PHP_VERSION}"-fpm

    # Allow to run "sudo systemctl [reload|restart|status] php*-fpm" without password prompt.
    export PHP_FPM_ACTIONS="
$L_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload php*-fpm
$L_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart php*-fpm
$L_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl status php*-fpm"
    if ! echo "${PHP_FPM_ACTIONS}" | tee "/etc/sudoers.d/$L_USER"; then
        io_print_warning "Can not configure /etc/sudoers.d/$L_USER file. You have to configure it by yourself."
    fi

    io_print_info "Installed PHP $L_PHP_VERSION"
}

# MySQL ========================================================================

install_mysql80() {
    L_MYSQL_ROOT_PASSWORD="$1"

    io_print_info "Start installing MySQL 8.0"

    debconf-set-selections <<< "mysql-server mysql-server/root_password password ${L_MYSQL_ROOT_PASSWORD}"
    debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${L_MYSQL_ROOT_PASSWORD}"

    apt-get -y install mysql-server

    io_print_info "Finished installing MySQL 8.0"
}


# BEGIN program

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Global variables start with H_
# Local variables start with L_

H_DISABLE_OS_CHECK='no'

H_MANAGE_USER="${H_MANAGE_USER:-manage}"
H_MANAGE_GROUP="${H_MANAGE_GROUP:-manage}"
H_MANAGE_PASSWORD="${H_MANAGE_PASSWORD:-secret}"

H_RUN_USER="${H_RUN_USER:-forge}"
H_RUN_GROUP="${H_RUN_GROUP:-www-data}"
H_RUN_PASSWORD="${H_RUN_PASSWORD:-secret}"

H_NGINX_USER="${H_NGINX_USER:-www-data}"

H_PHP_VERSION="${H_PHP_VERSION:-8.4}"

H_MYSQL_ROOT_PASSWORD="${H_MYSQL_ROOT_PASSWORD:-secret}"


# TODO: It does not work on a EC2 Ubuntu
# check_supported_os
check_root_privileges

install_manage_user "$H_MANAGE_USER" "$H_MANAGE_GROUP" "$H_MANAGE_PASSWORD"
install_run_user "$H_RUN_USER" "$H_RUN_GROUP" "$H_RUN_PASSWORD"

install_nginx "$H_NGINX_USER"

install_php "$H_RUN_USER" "$H_RUN_GROUP" "$H_PHP_VERSION"

install_mysql80 "$H_MYSQL_ROOT_PASSWORD"

# END program
