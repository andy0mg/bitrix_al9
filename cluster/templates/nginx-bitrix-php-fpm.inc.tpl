# FastCGI backend for Bitrix (php-fpm). Included from site configs when BITRIX_PHP_HANDLER=fpm.
# Socket: @PHP_FPM_SOCKET@

location ~* ^/upload/.+\.(php|php3|php4|php5|php6|phtml|pl|asp|aspx|cgi|dll|exe|shtm|shtml|fcg|fcgi|fpl|asmx|pht|py|psp|rb|var)$ {
    types {
        text/plain text/plain php php3 php4 php5 php6 phtml pl asp aspx cgi dll exe ico shtm shtml fcg fcgi fpl asmx pht py psp rb var;
    }
}

location ~ \.php$ {
    try_files $uri @bitrix_php_fpm;
    include fastcgi_params;
    fastcgi_pass @PHP_FPM_SOCKET@;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_read_timeout 3600;
    fastcgi_buffers 256 16k;
    fastcgi_buffer_size 128k;
}

location @bitrix_php_fpm {
    include fastcgi_params;
    fastcgi_pass @PHP_FPM_SOCKET@;
    fastcgi_param SCRIPT_FILENAME $document_root/bitrix/urlrewrite.php;
    fastcgi_read_timeout 3600;
}

location ~* /bitrix/admin.+\.php$ {
    try_files $uri @bitrixadm_php_fpm;
    include fastcgi_params;
    fastcgi_pass @PHP_FPM_SOCKET@;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_read_timeout 3600;
}

location @bitrixadm_php_fpm {
    include fastcgi_params;
    fastcgi_pass @PHP_FPM_SOCKET@;
    fastcgi_param SCRIPT_FILENAME $document_root/bitrix/admin/404.php;
    fastcgi_read_timeout 3600;
}
