# Bitrix Environment 9 — Redis tuning (push server / Bitrix cache & sessions).
# Rendered to <redis-conf-dir>/redis-bitrix.conf and pulled in from the main
# redis.conf via an `include` line. Placeholders come from cluster.env.
bind @REDIS_BIND@
protected-mode @REDIS_PROTECTED_MODE@
port @REDIS_PORT@
tcp-backlog 511
timeout 0
tcp-keepalive 300
maxmemory @REDIS_MAXMEMORY@
maxmemory-policy @REDIS_MAXMEMORY_POLICY@
appendonly @REDIS_APPENDONLY@
save ""
