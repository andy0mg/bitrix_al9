upstream bx_cluster {
    ip_hash;
@APP_SERVERS_BLOCK@
    keepalive 10;
}
