# App server behind the balancer: client IP from X-Forwarded-For.
# Trusted sources: BALANCER_IPS in cluster.env.
@REAL_IP_BLOCK@
real_ip_header X-Forwarded-For;
real_ip_recursive on;
