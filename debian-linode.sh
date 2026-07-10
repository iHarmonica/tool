sudo apt update && sudo apt install -y kexec-tools wget \
  && wget -P /tmp/ \
    https://mirror.xtom.com.hk/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux \
    https://mirror.xtom.com.hk/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz \
  && sudo /sbin/kexec -l /tmp/linux --initrd=/tmp/initrd.gz --append="\
    auto=true \
    priority=critical \
    netcfg/disable_dhcp=true \
    netcfg/disable_autoconfig=true \
    netcfg/get_ipaddress=139.162.40.145 \
    netcfg/get_netmask=255.255.255.0 \
    netcfg/get_gateway=139.162.40.1 \
    netcfg/get_nameservers=\"1.1.1.1 8.8.8.8\" \
    netcfg/confirm_static=true \
    preseed/url=https://us.mcdull.me/debian-linode.cfg \
    DEBIAN_FRONTEND=text" \
  && sudo systemctl kexec
