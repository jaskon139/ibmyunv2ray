#!/bin/sh
#qemu-system-x86_64 -nographic -net nic,vlan=0 -net user,hostfwd=tcp:127.0.0.1:8888-:22 -m 512 -hda /app/ssh_and_ss/tc/tc.img < /dev/null &
#cd /opt/wetty/ && node app.js -p $PORT
#kcperserver server_linux_amd64 
cd /app/v2ray-v3.31-linux-64
ssss=$(hostname)
ssss1=$( more /etc/hosts | grep $ssss)
resultip=$(echo $ssss1 |cut -f 1 -d " ")
#resultip=$(ifconfig eth0 |grep "inet addr"| cut -f 2 -d ":"|cut -f 1 -d " ")
chmod +x kcptunserver && ./kcptunserver 10.241.62.73 9999 $resultip $resultip 3824  &
chmod +x server_linux_amd64 && ./server_linux_amd64 -t 127.0.0.1:10086 -l :3824 --mode fast2 &
tar xvf gotty_linux_amd64.tar.gz && chmod +x gotty && ./gotty --port 9980 -c user:pass --permit-write --reconnect /bin/sh > /dev/null &
#/app/v2ray-v3.31-linux-64/v2ray -config /app/v2ray-v3.31-linux-64/config.json  > /dev/null &
#node server.js http://127.0.0.1:10000
#/app/chisel_linux_amd64 server --port 8080  --socks5 > /dev/null
#cd /opt/wetty && /usr/bin/node app.js -p $PORT
