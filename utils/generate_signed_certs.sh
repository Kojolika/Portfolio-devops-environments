# Run this script ON the ec2 instance to set up SSL certificate for HTTPS configuration
# This script generates and gets it's cert signed by Lets Encrypt CA, afterwords it restarts the nginx docker container

# IMPORTANT STEPS BEFORE RUNNING:
# 1. Have a $DOMAIN.crt and $DOMAIN.key file created in $SSL_CERT_DIRECTORY and $SSL_KEY_DIRECTORY
# (you can use this cmd to generate them: openssl req -nodes -new -x509 -subj "/CN=localhost" -keyout ${SSL_KEY_DIRECTORY}${DOMAIN}.key -out ${SSL_CERT_DIRECTORY}${DOMAIN}.crt)
# 2. After having the cert and key files, deploy using the deployment pipeline in Github actions (these cert and key file are REQUIRED for nginx to start)
# 3. Run this script with the variables below filled in
# 4. Store the cert and key in a secure location

# These cmds are specified for Amazon Linux 2023
# If git is not installed already run: 
#   sudo yum install git

# if yq is not installed run:
#   sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && sudo chmod +x /usr/bin/yq

# Required variables when running
# email to be registered for the ssl cert
DOMAIN_EMAIL=
# specify a folder name which is located in envs. Example: testing 
ENV_REPO_FOLDER=

# Preconfigured
REPO_NAME="Portfolio-devops-environments"
rm -rf $REPO_NAME
git clone https://github.com/Kojolika/$REPO_NAME

CURRENT_DIR=$(pwd)

# Settings shared across all environments
BASE_SETTINGS_FOLDER="$REPO_NAME/base"
SETTINGS_FILE="settings.yml"
cd $BASE_SETTINGS_FOLDER
SSL_CERT_DIRECTORY=$(yq '.deployment.ssl.directories.cert' $SETTINGS_FILE)
SSL_KEY_DIRECTORY=$(yq '.deployment.ssl.directories.key' $SETTINGS_FILE)
SSL_ACME_DIRECTORY=$(yq '.deployment.ssl.directories.acme-challenge' $SETTINGS_FILE)
BASE_DOMAIN=$(yq '.deployment.domain' $SETTINGS_FILE)

cd $CURRENT_DIR

# env specific settings
ENV_SPECIFIC_FOLDER="$REPO_NAME/envs/$ENV_REPO_FOLDER"
cd $ENV_SPECIFIC_FOLDER
ENVIRONMENT=$(yq '.specifics | load(.deployment) | .app.environment' $SETTINGS_FILE)
SUB_DOMAIN=$(yq '.specifics | load(.deployment) | .app.subdomain' $SETTINGS_FILE)
if [[ ! -z $SUB_DOMAIN ]]; then
    SUB_DOMAIN="$SUB_DOMAIN."
fi
DOMAIN=${SUB_DOMAIN}${BASE_DOMAIN}

cat <<'EOF' | docker exec -i app_nginx_1 /bin/bash
if true | openssl s_client -connect $DOMAIN:443 2>/dev/null | \
openssl x509 -noout -checkend 0 && openssl verify $SSL_CERT_DIRECTORY/$DOMAIN.crt; then
    echo "HTTPS is working correctly"
else
    rm $SSL_CERT_DIRECTORY/${DOMAIN}.crt
    apt-get update
    apt-get -y install dnsutils
    cd ~
    curl --silent https://raw.githubusercontent.com/srvrco/getssl/latest/getssl > getssl
    chmod 700 getssl
    ./getssl -c
    SSL_CONFIG=~/.getssl/getssl.cfg
    SSL_DOMAIN_SPECIFIC_CONFIG=~/.getssl/${DOMAIN}/getssl.cfg
    sed -i -E "s/#ACCOUNT_EMAIL=\"[^\"]*\"/ACCOUNT_EMAIL=\"$DOMAIN_EMAIL\"/" $SSL_CONFIG
    if [[ env.ENVIRONMENT = 'production' ]]; then
        sed -i 's/CA="https://acme-staging-v02.api.letsencrypt.org"/#CA="https://acme-staging-v02.api.letsencrypt.org"/' $SSL_CONFIG
        sed -i 's/#CA="https://acme-v02.api.letsencrypt.org"/CA="https://acme-v02.api.letsencrypt.org"/' $SSL_CONFIG
    fi
    sed -i -E "s/#USE_SINGLE_ACL=\"[^\"]*\"/USE_SINGLE_ACL=\"true\"/" $SSL_DOMAIN_SPECIFIC_CONFIG
    sed -i -E "s/SANS=\"[^\"]*\"/SANS=\"\"/" $SSL_DOMAIN_SPECIFIC_CONFIG
    sed -i -E "s/#RELOAD_CMD=\"[^\"]*\"/RELOAD_CMD=\"\/etc\/init.d\/nginx reload\"/" $SSL_DOMAIN_SPECIFIC_CONFIG
    sed -i -E "s/#ACL=\(.*/ACL=(\"${SSL_ACME_DIRECTORY//\//\\\/}\")/" $SSL_DOMAIN_SPECIFIC_CONFIG
    sed -i -E "s/#DOMAIN_CERT_LOCATION=\"[^\"]*\"/DOMAIN_CERT_LOCATION=\"${SSL_CERT_DIRECTORY//\//\\\/}\"/" $SSL_DOMAIN_SPECIFIC_CONFIG
    sed -i -E "s/#DOMAIN_KEY_LOCATION=\"[^\"]*\"/DOMAIN_KEY_LOCATION=\"${SSL_KEY_DIRECTORY//\//\\\/}\"/" $SSL_DOMAIN_SPECIFIC_CONFIG
    ./getssl
fi
EOF