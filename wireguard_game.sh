#!/bin/bash

#wg+udpspeeder+udp2raw，fec:游戏场景

if [ ! -e '/etc/redhat-release' ]; then
echo -e "\033[37;41m仅支持centos7\033[0m"
exit
fi
if  [ -n "$(grep ' 6\.' /etc/redhat-release)" ] ;then
echo -e "\033[37;41m仅支持centos7\033[0m"
exit
fi



#更新内核
update_kernel(){

    yum -y install epel-release
    sed -i "0,/enabled=0/s//enabled=1/" /etc/yum.repos.d/epel.repo
    yum remove -y kernel-devel
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
    yum --disablerepo="*" --enablerepo="elrepo-kernel" list available
    yum -y --enablerepo=elrepo-kernel install kernel-ml
    sed -i "s/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/" /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    wget https://elrepo.org/linux/kernel/el7/x86_64/RPMS/kernel-ml-devel-4.19.1-1.el7.elrepo.x86_64.rpm
    rpm -ivh kernel-ml-devel-4.19.1-1.el7.elrepo.x86_64.rpm
    yum -y --enablerepo=elrepo-kernel install kernel-ml-devel
    read -p "需要重启VPS，再次执行脚本选择安装wireguard，是否现在重启 ? [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
		echo -e "\033[37;41mVPS 重启中...\033[0m"
		reboot
	fi
}

#生成随机端口
rand(){
    min=$1
    max=$(($2-$min+1))
    num=$(cat /dev/urandom | head -n 10 | cksum | awk -F ' ' '{print $1}')
    echo $(($num%$max+$min))  
}

wireguard_update(){
    yum update -y wireguard-dkms wireguard-tools
    echo -e "\033[37;41m更新完成\033[0m"
}

wireguard_remove(){
    yum remove -y wireguard-dkms wireguard-tools
    rm -rf /etc/wireguard/
    echo -e "\033[37;41m卸载完成\033[0m"
}

config_client(){
cat > /etc/wireguard/client.conf <<-EOF
[Interface]
PrivateKey = $c1
Address = 10.0.0.2/24 
DNS = 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $s2
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF

}

udp_install(){
    
#下载客户端脚本
    curl -o /etc/wireguard/client/start.bat https://raw.githubusercontent.com/atrandys/onekeyopenvpn/master/client_pre.bat
    curl -o /etc/wireguard/client/stop.bat https://raw.githubusercontent.com/atrandys/onekeyopenvpn/master/client_down.bat
    
    #下载udpspeeder和udp2raw （amd64版）
    mkdir /usr/src/udp
    cd /usr/src/udp
    curl -o speederv2 https://raw.githubusercontent.com/atrandys/onekeyopenvpn/master/speederv2
    curl -o udp2raw https://raw.githubusercontent.com/atrandys/onekeyopenvpn/master/udp2raw
    chmod +x speederv2 udp2raw
    
    #启动udpspeeder和udp2raw
    nohup ./speederv2 -s -l0.0.0.0:9999 -r127.0.0.1:1194 -f2:4 --mode 0 --timeout 0 >speeder.log 2>&1 &
    nohup ./udp2raw -s -l0.0.0.0:9898 -r 127.0.0.1:9999  --raw-mode faketcp  -a -k passwd >udp2raw.log 2>&1 &
    
#增加自启动脚本
cat > /etc/rc.d/init.d/autoudp<<-EOF
#!/bin/sh
#chkconfig: 2345 80 90
#description:autoudp
cd /usr/src/udp
nohup ./speederv2 -s -l0.0.0.0:9999 -r127.0.0.1:1194 -f2:4 --mode 0 --timeout 0 >speeder.log 2>&1 &
nohup ./udp2raw -s -l0.0.0.0:9898 -r 127.0.0.1:9999  --raw-mode faketcp  -a -k passwd >udp2raw.log 2>&1 &
EOF

#设置脚本权限
    chmod +x /etc/rc.d/init.d/autoudp
    chkconfig --add autoudp
    chkconfig autoudp on
}

#centos7安装wireguard
wireguard_install(){
    curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
    yum install -y dkms gcc-c++ gcc-gfortran glibc-headers glibc-devel libquadmath-devel libtool systemtap systemtap-devel
    yum -y install wireguard-dkms wireguard-tools
    yum -y install qrencode
    mkdir /etc/wireguard
    mkdir /etc/wireguard/client
    cd /etc/wireguard
    wg genkey | tee sprivatekey | wg pubkey > spublickey
    wg genkey | tee cprivatekey | wg pubkey > cpublickey
    s1=$(cat sprivatekey)
    s2=$(cat spublickey)
    c1=$(cat cprivatekey)
    c2=$(cat cpublickey)
    serverip=$(curl ipv4.icanhazip.com)
    port=$(rand 10000 60000)
    chmod 777 -R /etc/wireguard
    systemctl stop firewalld
    systemctl disable firewalld
    yum install -y iptables-services 
    systemctl enable iptables 
    systemctl start iptables 
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -F
    service iptables save
    service iptables restart
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.conf	
cat > /etc/wireguard/wg0.conf <<-EOF
[Interface]
PrivateKey = $s1
Address = 10.0.0.1/24 
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ListenPort = $port
DNS = 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $c2
AllowedIPs = 10.0.0.2/32
EOF

    config_client
    wg-quick up wg0
    systemctl enable wg-quick@wg0
    content=$(cat /etc/wireguard/client.conf)
    echo -e "\033[37;41m电脑端请下载client.conf，手机端可直接使用软件扫码\033[0m"
    echo "${content}" | qrencode -o - -t UTF8
}

#开始菜单
start_menu(){
    clear
    echo -e "\033[43;42m ====================================\033[0m"
    echo -e "\033[43;42m 介绍：wireguard+udpspeeder+udp2raw  \033[0m"
    echo -e "\033[43;42m 系统：CentOS7                       \033[0m"
    echo -e "\033[43;42m 作者：atrandys                      \033[0m"
    echo -e "\033[43;42m 网站：www.atrandys.com              \033[0m"
    echo -e "\033[43;42m Youtube：atrandys                   \033[0m"
    echo -e "\033[43;42m ====================================\033[0m"
    echo
    echo -e "\033[0;33m 1. 升级系统内核(必需)\033[0m"
    echo -e "\033[0;33m 2. 安装wireguard+udpspeeder+udp2raw\033[0m"
    echo " 3. 升级wireguard"
    echo " 4. 卸载wireguard"
    echo " 5. 显示客户端二维码"
    echo " 0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    update_kernel
    ;;
    2)
    wireguard_install
    ;;
    3)
    wireguard_update
    ;;
    4)
    wireguard_remove
    ;;
    5)
    content=$(cat /etc/wireguard/client.conf)
    echo "${content}" | qrencode -o - -t UTF8
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    echo -e "请输入正确数字"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu



