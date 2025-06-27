#!/bin/bash

# 創建 nginx 配置檔案
mkdir -p ./registry-ui/conf
cat <<EOF > ./registry-ui/conf/default.conf
server {
    listen 8082;
    
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        try_files \$uri \$uri/ /index.html =404;
    }
    
    location /v2/ {
        proxy_pass https://localhost:5003;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # CORS 設置
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, PUT, DELETE' always;
        add_header 'Access-Control-Allow-Headers' 'Authorization, Accept, Origin, Content-Type' always;
        add_header 'Access-Control-Allow-Credentials' 'true' always;
        add_header 'Access-Control-Max-Age' '1800' always;
        
        # 處理 OPTIONS 請求
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, PUT, DELETE';
            add_header 'Access-Control-Allow-Headers' 'Authorization, Accept, Origin, Content-Type';
            add_header 'Access-Control-Allow-Credentials' 'true';
            add_header 'Access-Control-Max-Age' '1800';
            add_header 'Content-Type' 'text/plain charset=UTF-8';
            add_header 'Content-Length' '0';
            return 204;
        }
        
        proxy_ssl_verify off;
    }
}
EOF

echo "Nginx 配置檔案已創建"

# 設置執行權限
chmod +x ./create-config.sh 