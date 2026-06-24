server {
    listen 80;
    server_name @SERVER_NAME@;

    include /etc/nginx/bx/conf/bitrix.conf;

    location / {
        proxy_pass http://bx_cluster;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
