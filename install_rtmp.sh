#!/bin/bash
# Simple RTMP streaming server installer for Ubuntu 20.04/22.04

set -e

echo "Updating system..."
sudo apt update && sudo apt upgrade -y

echo "Installing prerequisites..."
sudo apt install -y build-essential libpcre3 libpcre3-dev libssl-dev zlib1g-dev \
git wget ffmpeg unzip curl

# Variables
NGINX_VERSION=1.24.0
NGINX_DIR=/usr/local/nginx

echo "Downloading nginx and RTMP module..."
wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
tar -zxvf nginx-${NGINX_VERSION}.tar.gz
git clone https://github.com/arut/nginx-rtmp-module.git

echo "Building nginx with RTMP module..."
cd nginx-${NGINX_VERSION}
./configure --prefix=$NGINX_DIR --with-http_ssl_module --add-module=../nginx-rtmp-module
make
sudo make install

echo "Creating nginx config..."
sudo tee $NGINX_DIR/conf/nginx.conf > /dev/null <<'EOF'
worker_processes  auto;
events {
    worker_connections  1024;
}

rtmp {
    server {
        listen 1935;
        chunk_size 4096;

        application live {
            live on;
            record off;
        }
    }
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    server {
        listen 8080;

        location /stat {
            rtmp_stat all;
            rtmp_stat_stylesheet stat.xsl;
        }

        location /stat.xsl {
            root $NGINX_DIR/html;
        }
    }
}
EOF

echo "Copying RTMP stats stylesheet..."
sudo cp ../nginx-rtmp-module/stat.xsl $NGINX_DIR/html/

echo "Starting nginx..."
sudo $NGINX_DIR/sbin/nginx

echo "Done!"
echo "RTMP URL: rtmp://YOUR_SERVER_IP/live/streamkey"
echo "Stats page: http://YOUR_SERVER_IP:8080/stat"
