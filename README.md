HapiDeploy Toolchain

## Usage

Install the LEMP stack on a Ubuntu server.

```bash
# Download the install-lemp.sh file and make it executable.
wget -O install-lemp.sh "https://raw.githubusercontent.com/hapideploy/toolchain/main/src/install-lemp.sh" --quiet

chmod +x install-lemp.sh

# Customize environment variables due to your need
H_MANAGE_USER="jack-jack"
H_MANAGE_GROUP="jack-jack"
H_MANAGE_PASSWORD="fDvgYEdb"

H_RUN_USER="deployer"
H_RUN_GROUP="www-data"
H_RUN_PASSWORD="fDvgYEdb"

H_NGINX_USER="www-data"

H_PHP_VERSION="8.4"

H_MYSQL_ROOT_PASSWORD="fDvgYEdb"

# Run the install-lemp.sh and wait until it's done.
./install-lemp.sh
```
