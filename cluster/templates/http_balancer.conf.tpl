# Reverse proxy in front of Bitrix app servers + push server websocket.
# Upstreams bx_cluster / bx_push_sub: upstream.conf (nginx-upstream.conf.tpl).
# Map names are prefixed bx_lb_ so they don't clash with bx-nginx maps (im_settings.conf).

map $http_upgrade $bx_lb_connection_upgrade {
    default upgrade;
    ''      close;
}

map $http_upgrade $bx_lb_replace_upgrade {
    default $http_upgrade;
    ''      websocket;
}

server {
    listen 80;
    server_name @SERVER_NAME@;

    # ACME (certbot --webroot -w /var/www/letsencrypt)
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name @SERVER_NAME@;

    ssl_certificate     @SSL_CERT@;
    ssl_certificate_key @SSL_KEY@;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:bx_lb_ssl:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    client_max_body_size 1024m;
    client_body_buffer_size 1m;

    # proxy_set_header in a location drops inherited ones, so the
    # Host / X-Forwarded-* set is repeated in every location below.

    # Push server: websocket subscribe
    location ~* ^/bitrix/subws/ {
        access_log off;
        proxy_pass http://bx_push_sub;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header Upgrade $bx_lb_replace_upgrade;
        proxy_set_header Connection $bx_lb_connection_upgrade;
        proxy_buffering off;
        proxy_max_temp_file_size 0;
        # 12h + 0.5
        proxy_read_timeout 43800;
        proxy_send_timeout 43800;
    }

    # Push server: long polling fallback
    location ~* ^/bitrix/sub/ {
        access_log off;
        rewrite ^/bitrix/sub/(.*)$ /bitrix/subws/$1 break;
        proxy_pass http://bx_push_sub;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_max_temp_file_size 0;
        proxy_read_timeout 43800;
    }

    # Publishing (/bitrix/pub/, /bitrix/rest/) is not exposed: app servers
    # publish directly to http://PUSH_HOST:9010/bitrix/pub/.
    location ~* ^/bitrix/(pub|rest)/ {
        return 404;
    }

    location / {
        proxy_pass http://bx_cluster;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header Connection "";
        proxy_connect_timeout 10s;
        proxy_send_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_buffer_size 128k;
        proxy_buffers 64 16k;
        proxy_busy_buffers_size 256k;
        proxy_request_buffering off;
    }
}
