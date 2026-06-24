vrrp_script chk_nginx {
    script "/usr/bin/systemctl is-active nginx"
    interval 2
    weight -20
}

vrrp_instance VI_1 {
    state @STATE@
    interface @INTERFACE@
    virtual_router_id @ROUTER_ID@
    priority @PRIORITY@
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass bitrix9lb
    }

    virtual_ipaddress {
        @VIP@
    }

    track_script {
        chk_nginx
    }
}
