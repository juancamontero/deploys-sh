#!/bin/bash

# Env Vars
DATABASE_URL=xx
OPENAI_API_KEY=xx
SERPER_API_KEY=xx
ENV_TYPE=prod
API_KEY=xx
DOMAIN_NAME="nextselfhost.dev" # replace with your own
# todo Certbot // EMAIL="your-email@example.com" # replace with your own

# Script Vars
REPO_URL="git@github.com:juancamontero/forecast-back-ns.git"
APP_DIR=~/myapp
SWAP_SIZE="1G"  # Swap size of 1GB

# Update package list and upgrade existing packages
sudo apt update && sudo apt upgrade -y

# Add Swap Space
echo "Adding swap space..."
sudo fallocate -l $SWAP_SIZE /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make swap permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Install Docker
sudo apt install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" -y
sudo apt update
sudo apt install docker-ce -y

# Install Docker Compose
sudo rm -f /usr/local/bin/docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Wait for the file to be fully downloaded before proceeding
if [ ! -f /usr/local/bin/docker-compose ]; then
  echo "Docker Compose download failed. Exiting."
  exit 1
fi

sudo chmod +x /usr/local/bin/docker-compose


# Ensure Docker Compose is executable and in path
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose installation
docker-compose --version
if [ $? -ne 0 ]; then
  echo "Docker Compose installation failed. Exiting."
  exit 1
fi

# Ensure Docker starts on boot and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Clone the Git repository
if [ -d "$APP_DIR" ]; then
  echo "Directory $APP_DIR already exists. Pulling latest changes..."
  cd $APP_DIR && git pull
else
  echo "Cloning repository from $REPO_URL..."
  git clone $REPO_URL $APP_DIR
  cd $APP_DIR
fi

# Create the .env file inside the app directory (~/myapp/.env)
echo "DATABASE_URL=$DATABASE_URL" > "$APP_DIR/src/.env"
echo "OPENAI_API_KEY=$OPENAI_API_KEY" > "$APP_DIR/src/.env"
echo "SERPER_API_KEY=$SERPER_API_KEY" > "$APP_DIR/src/.env"
echo "ENV_TYPE=$ENV_TYPE" > "$APP_DIR/src/.env"
echo "API_KEY=$API_KEY" > "$APP_DIR/src/.env"

# Install Nginx
sudo apt install nginx -y

# Remove old Nginx config (if it exists)
sudo rm -f /etc/nginx/sites-available/myapp
sudo rm -f /etc/nginx/sites-enabled/myapp

# Create a new config file
# Create Nginx config with reverse proxy, SSL support, rate limiting, and streaming support

#todo -> limit_req_zone \$binary_remote_addr zone=mylimit:20m rate=20r/s;

sudo cat > /etc/nginx/sites-available/myapp <<EOL

server {
    listen 8089;
    server_name $DOMAIN_NAME;

    location / {
           proxy_pass http://localhost:8089;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
}
EOL

# Create symbolic link if it doesn't already exist
sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/myapp

# Restart Nginx to apply the new configuration
sudo systemctl restart nginx

# Build and run the Docker containers from the app directory (~/myapp)
cd $APP_DIR/src
sudo docker-compose up --build -d

# Check if Docker Compose started correctly
if ! sudo docker-compose ps | grep "Up"; then
  echo "Docker containers failed to start. Check logs with 'docker-compose logs'."
  exit 1
fi
