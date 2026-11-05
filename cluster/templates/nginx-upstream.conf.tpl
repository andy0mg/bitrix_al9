# Bitrix app servers (APP_SERVERS in cluster.env)
upstream bx_cluster {
    ip_hash;
@APP_SERVERS_BLOCK@
    keepalive 32;
}

# Push server: subscribe (websocket / long polling), PUSH_HOST in cluster.env
upstream bx_push_sub {
    ip_hash;
    server @PUSH_HOST@:8010;
    server @PUSH_HOST@:8011;
    server @PUSH_HOST@:8012;
    server @PUSH_HOST@:8013;
    server @PUSH_HOST@:8014;
    server @PUSH_HOST@:8015;
    keepalive 1024;
}
