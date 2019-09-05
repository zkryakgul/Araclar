#!/bin/bash
COLOR_GREEN="\033[92m"
COLOR_RED="\033[31m"
COLOR_YELLOW="\033[93m"
COLOR_DEFAULT="\033[39m"


print_warn()
{
    echo -ne "$COLOR_YELLOW$1$COLOR_DEFAULT"
}

print_err()
{
    echo -ne "$COLOR_RED$1$COLOR_DEFAULT"
}

check_deps()
{
    deps="awk ip sed"

    for i in ${deps[@]}; do
        command -v $i >/dev/null 2>&1 || { echo >&2 "$i komutu gerekli fakat yüklü değil.  Çıkılıyor.."; exit 1; }
    done
}

change_hostname()
{
    unset old_hostname
    unset new_hostname
    echo -ne "\n"
    old_hostname=$(hostname)
    read -p "Yeni hostname giriniz (aktif: $old_hostname): " new_hostname

    if [ -z "$new_hostname" ]; then
        print_warn "\nBu bilgi boş bırakılamaz!\n"
        change_hostname
    return
    fi

    if [ "$old_hostname" == "$new_hostname" ]; then
        print_warn "\nGirilen hostname eskisi ile aynı!\n"
        change_hostname
    return
    fi;

    echo -ne "\nEski hostname $COLOR_YELLOW$old_hostname$COLOR_DEFAULT, $COLOR_GREEN$new_hostname$COLOR_DEFAULT ile değiştirilecek\n"

    while true; do
        read -p "Onaylıyor musunuz? (e/h) " yn
        case $yn in
            [Ee]* ) break;;
            [Hh]* ) exit; break;;
            * ) echo "Lütfen evet ya da hayır olarak cevaplayın.";;
        esac
    done

    sed -i "s/$old_hostname/$new_hostname/g" /etc/hostname
    if [ $? -ne 0 ]; then
        print_err "/etc/hostname dosyasını düzenlerken bir hata meydana geldi! Çıkılıyor..\n"
    exit
    fi;

    sed -i "s/$old_hostname/$new_hostname/g" /etc/hosts
    if [ $? -ne 0 ]; then
        print_err "/etc/hosts dosyasını düzenlerken bir hata meydana geldi! Çıkılıyor..\n"
    exit
    fi;

    echo -ne "$COLOR_GREEN"
    echo -ne "\nHostname başarıyla değiştirildi\n\n"
    echo -ne "$COLOR_DEFAULT"
}

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\/[0-9]{1,2}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

change_ip_adress()
{
    echo -ne "\n"
    unset ifaces
    unset iface
    unset status
    unset old_ip
    unset new_ip
    status=0
    iface=""
    for i in `ip a | awk 'BEGIN {FS=": "}{print $2}'`; do 
        if [ "$i" != 'lo' ]; then 
            ifaces=( "${ifaces[@]}" $i )
        fi;
    done

    PS3="Ip adresini değiştirmek istediğini interface numarasını listeden giriniz : "

    select s_iface in ${ifaces[@]}
    do
        iface=$s_iface
    break;
    done

    if [ -z "$iface" ]; then
        print_warn "\nLütfen gerçeli bir seçim yapın!\n"
        change_ip_adress
    return
    fi

    old_ip="$(/sbin/ip -o -4 addr list $iface | awk '{print $4}')"
    echo -ne "\n"
    read -p "Yeni ip adresini subnet ile birlikte giriniz (aktif: $old_ip): " new_ip

    if [ -z "$new_ip" ]; then
        print_warn "\nBu bilgi boş bırakılamaz!\n"
        change_ip_adress
    return
    fi

    if [ "$old_ip" == "$new_ip" ]; then
        print_warn "\nGirilen ip adresi eskisi ile aynı!\n"
        change_ip_adress
    return
    fi;
    
    if ! valid_ip $new_ip; then 
        print_warn "\nGirilen ip adres formatı hatalı!\n"
        change_ip_adress
    return
    fi

    echo -ne "\nEski ip adress $COLOR_YELLOW$old_ip$COLOR_DEFAULT, $COLOR_GREEN$new_ip$COLOR_DEFAULT ile $COLOR_YELLOW$iface$COLOR_DEFAULT arabirimi için değiştirilecek\n"

    while true; do
        read -p "Onaylıyor musunuz? (e/h) " yn
        case $yn in
            [Ee]* ) break;;
            [Hh]* ) exit; break;;
            * ) echo "Lütfen evet ya da hayır olarak cevaplayın.";;
        esac
    done

    # Remove subnets from ip for /etc/hosts file
    old_ip_without_subnet="$(echo $old_ip | cut -d/ -f1)"
    new_ip_without_subnet="$(echo $old_ip | cut -d/ -f1)"
    file="/etc/hosts"

    if ! grep -Fq "$old_ip_without_subnet" $file; then
        status=1
        print_warn "\n$file dosyası $COLOR_DEFAULT$iface$COLOR_YELLOW ara birimi ve $COLOR_DEFAULT$old_ip_without_subnet$COLOR_YELLOW ip adresi için daha önce yapılandırılmamış veya yapılandırma hatalı, lütfen elle yapılandırın!\n"
    else
        sed -i "s/$old_ip_without_subnet/$new_ip_without_subnet/g" $file
        if [ $? -ne 0 ]; then
            print_err "$file dosyasını düzenlerken bir hata meydana geldi! Çıkılıyor..\n"
            exit
        fi;
    fi

    # Fix escape chars for sed with backslash
    old_ip_escaped="$(echo $old_ip | sed 's/[\/&]/\\&/g')"
    new_ip_escaped="$(echo $new_ip | sed 's/[\/&]/\\&/g')"
    file="/etc/network/interfaces"

    if ! grep -Fq "$old_ip" $file; then
        status=1
        print_warn "\n$file dosyası $COLOR_DEFAULT$iface$COLOR_YELLOW ara birimi ve $COLOR_DEFAULT$old_ip$COLOR_YELLOW ip adresi için daha önce yapılandırılmamış veya yapılandırma hatalı, lütfen elle yapılandırın!\n"
    else
        sed -i "s/$old_ip_escaped/$new_ip_escaped/g" $file
        if [ $? -ne 0 ]; then
            print_err "$file dosyasını düzenlerken bir hata meydana geldi! Çıkılıyor..\n"
            exit
        fi;
    fi

    if [[ status -eq 0 ]]; then
        echo -ne "$COLOR_GREEN"
        echo -ne "\nIp Adresi başarılı bir şekilde değiştirildi\n"
        echo -ne "$COLOR_DEFAULT"
    else
        print_warn "\nDaha sonra ilgilenmeniz gereken bazı hatalar var!\n"
    fi

}

change_gateway()
{
    echo -ne "\n"

    unset status
    unset old_gateway
    unset new_gateway
    status=0

    old_gateway="$(ip route | grep default | awk 'BEGIN {FS=" "}{print $3}')"

    read -p "Yeni gateway giriniz (aktif: $old_gateway): " new_gateway

    if [ -z "$new_gateway" ]; then
        print_warn "\nBu bilgi boş bırakılamaz!\n"
        change_gateway
    return
    fi

    if [ "$old_gateway" == "$new_gateway" ]; then
        print_warn "\nGirilen gateway eskisi ile aynı!\n"
        change_gateway
    return
    fi;

    echo -ne "\nEski gateway $COLOR_YELLOW$old_gateway$COLOR_DEFAULT $COLOR_GREEN$new_gateway$COLOR_DEFAULT ile değiştirilecek\n"

    while true; do
        read -p "Onaylıyor musunuz? (e/h) " yn
        case $yn in
            [Ee]* ) break;;
            [Hh]* ) exit; break;;
            * ) echo "Lütfen evet ya da hayır olarak cevaplayın.";;
        esac
    done

    if ! grep -Fxq "$old_gateway" /etc/network/interfaces; then
        status=1
        print_warn "\n/etc/network/interfaces dosyası $COLOR_DEFAULT$old_gateway$COLOR_YELLOW gatewayi için daha önce yapılandırılmamış veya yapılandırma hatalı, lütfen elle yapılandırın!\n"
    else
        sed -i "s/$old_gateway/$new_gateway/g" $/etc/network/interfaces
        if [ $? -ne 0 ]; then
            print_err "/etc/network/interfaces dosyasını düzenlerken bir hata meydana geldi! Çıkılıyor..\n"
            exit
        fi;
    fi

    if [[ status -eq 0 ]]; then
        echo -ne "$COLOR_GREEN"
        echo -ne "\nGateway başarıyla değiştirildi\n"
        echo -ne "$COLOR_DEFAULT"
    else
        print_warn "\nDaha sonra ilgilenmeniz gereken bazı hatalar var!\n"
    fi
}


if [ "$EUID" -ne 0 ]; then 
    echo -ne "$COLOR_YELLOW"
    echo -ne "\n** Lütfen bu scripti sudo ile çalıştırınız **\n\n"
    echo -ne "$COLOR_DEFAULT"
    exit
fi

check_deps

echo -ne "\n"

while true; do
    read -p "Sunucu adınızı değiştirmek istiyor musunuz? (e/h) " yn
    case $yn in
        [Ee]* ) change_hostname; break;;
        [Hh]* ) break;;
        * ) echo "Lütfen evet ya da hayır olarak cevaplayın.";;
    esac
done

echo -ne "\n"

while true; do
    read -p "Sunucu ip adresini değiştirmek istiyor musunuz? (e/h) " yn
    case $yn in
        [Ee]* ) change_ip_adress; break;;
        [Hh]* ) break;;
        * ) echo "Lütfen evet ya da hayır olarak cevaplayın.";;
    esac
done

echo -ne "\n"

while true; do
    read -p "Sunucu gateway'ini değiştirmek istiyor musunuz? (e/h) " yn
    case $yn in
        [Ee]* ) change_gateway; break;;
        [Hh]* ) break;;
        * ) echo "Lütfen evet ya da hayır olarak cevaplayın.";;
    esac
done

echo -ne "\n"

while true; do
    read -p "Yeni ayarları uygulamak için yeniden başlatılsın mı? (e/h) " yn
    case $yn in
        [Ee]* ) reboot; break;;
        [Hh]* ) break;;
        * ) echo "Lütfen evet ya da hayır olarak cevaplayın.";;
    esac
done