#!/bin/bash
# RTMP + HLS + HTTPS streaming server installer for Ubuntu 20.04/22.04
# with automatic certificate renewal

set -e

DOMAIN="live.srikaraonlineservices.com"
NGINX_VERSION=1.24.0
NGINX_DIR=/usr/local/nginx
HLS_DIR=/var/www/hls

echo "=== Updating system ==="
sudo apt update && sudo apt upgrade -y

echo "=== Installing prerequisites ==="
sudo apt install -y build-essential libpcre3 libpcre3-dev libssl-dev zlib1g-dev \
git wget ffmpeg unzip curl certbot

echo "=== Downloading nginx and RTMP module ==="
wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
tar -zxvf nginx-${NGINX_VERSION}.tar.gz
git clone https://github.com/arut/nginx-rtmp-module.git

echo "=== Building nginx with RTMP module ==="
cd nginx-${NGINX_VERSION}
./configure --prefix=$NGINX_DIR --with-http_ssl_module --add-module=../nginx-rtmp-module
make
sudo make install

echo "=== Creating HLS directories ==="
sudo mkdir -p $HLS_DIR
sudo chmod -R 755 $HLS_DIR

echo "=== Obtaining SSL certificate for $DOMAIN ==="
sudo certbot certonly --webroot -w /var/www -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN || true

echo "=== Creating nginx config with HLS + HTTPS support ==="
sudo tee $NGINX_DIR/conf/nginx.conf > /dev/null <<EOF
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

            # HLS settings
            hls on;
            hls_path $HLS_DIR;
            hls_fragment 3;
            hls_playlist_length 60;
        }
    }
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;

    # Redirect HTTP -> HTTPS
    server {
        listen 80;
        server_name $DOMAIN;
        location /.well-known/acme-challenge/ {
            root /var/www;
        }
        return 301 https://\$host\$request_uri;
    }

    # HTTPS server
    server {
        listen 443 ssl;
        server_name $DOMAIN;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        # HLS playback
        location /hls {
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }
            root /var/www;
            add_header Cache-Control no-cache;
            add_header Access-Control-Allow-Origin *;
        }

        # RTMP stats page
        location /stat {
            rtmp_stat all;
            rtmp_stat_stylesheet stat.xsl;
        }

        location /stat.xsl {
            root /usr/local/nginx/html;
        }
    }
}
EOF

echo "=== Copying RTMP stats stylesheet ==="
sudo cp ../nginx-rtmp-module/stat.xsl $NGINX_DIR/html/

echo "=== Starting nginx ==="
sudo $NGINX_DIR/sbin/nginx || sudo $NGINX_DIR/sbin/nginx -s reload

echo "=== Opening firewall ports ==="
sudo ufw allow 1935/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

echo "=== Setting up automatic certificate renewal ==="
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook \"/usr/local/nginx/sbin/nginx -s reload\"") | crontab -

echo "=== Done! ==="
echo "Push RTMP: rtmp://116.202.221.83/live/streamkey"
echo "Play HLS (HTTPS): https://$DOMAIN/hls/streamkey.m3u8"
echo "Stats page: https://$DOMAIN/stat"
