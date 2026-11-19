Временный proxy со СТАРОГО сервера (10.21.62.180) на НОВЫЙ (10.254.61.6),
пока заказчик не перепишет маршрутизацию/DNS.

1) На старом сервере создайте файл:
   /etc/nginx/bx/site_enabled/zz-proxy-to-new.conf

   Скопируйте содержимое из zz-proxy-to-new.conf (рядом с этим README).

2) В /etc/nginx/bx/site_enabled/petrovich.tech.conf закомментируйте
   старые upstream pt_app / server { ... } ИЛИ оставьте файл, но убедитесь,
   что zz-proxy-to-new.conf загружается позже и перекрывает server_name
   (в BitrixEnv include идёт по имени файла — префикс zz- даёт приоритет
   только для одинаковых map; для server{} важен первый подходящий server_name).

   Надёжный вариант: заменить содержимое petrovich.tech.conf на блок
   из zz-proxy-to-new.conf (секция petrovich.tech) и в s1.conf / ssl.s1.conf
   поменять $proxyserver на http://10.254.61.6.

3) Проверка и reload:
   nginx -t && systemctl reload nginx

4) После смены DNS/маршрутизации на новый IP — удалите zz-proxy-to-new.conf
   и верните/отключите старый сервер.
