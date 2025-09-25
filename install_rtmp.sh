#!/bin/bash
# RTMP + HLS streaming server installer for Ubuntu 20.04/22.04

set -e

echo "=== Updating system ==="
sudo apt update && sudo apt upgrade -y

echo "=== Installing prerequisites ==="
sudo apt install -y build-essential libpcre3 libpcre3-dev libssl-dev zlib1g-dev \
git wget ffmpeg unzip curl

# Variables
NGINX_VERSION=1.24.0
NGINX_DIR=/usr/local/nginx

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
sudo mkdir -p /var/www/hls
sudo chmod -R 755 /var/www/hls

echo "=== Creating nginx config with HLS support ==="
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

            # HLS settings
            hls on;
            hls_path /var/www/hls;
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

    server {
        listen 8080;

        # RTMP stats
        location /stat {
            rtmp_stat all;
            rtmp_stat_stylesheet stat.xsl;
        }

        location /stat.xsl {
            # must use actual path, not shell variable
            root /usr/local/nginx/html;
        }

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
    }
}
EOF

echo "=== Copying RTMP stats stylesheet ==="
sudo cp ../nginx-rtmp-module/stat.xsl $NGINX_DIR/html/

echo "=== Starting nginx ==="
sudo $NGINX_DIR/sbin/nginx || sudo $NGINX_DIR/sbin/nginx -s reload

echo "=== Done! ==="
echo "Push RTMP: rtmp://116.202.221.83/live/streamkey"
echo "Play HLS:  http://116.202.221.83:8080/hls/streamkey.m3u8"
echo "Stats page: http://116.202.221.83:8080/stat"
