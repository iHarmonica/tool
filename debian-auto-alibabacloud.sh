sudo apt update && sudo apt install -y kexec-tools wget \
  && wget -P /tmp/ \
    https://mirror.xtom.com.hk/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux \
    https://mirror.xtom.com.hk/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz \
  && sudo /sbin/kexec -l /tmp/linux --initrd=/tmp/initrd.gz --append="\
    auto=true \
    priority=critical \
    netcfg/choose_interface=auto \
    preseed/url=https://raw.githubusercontent.com/iHarmonica/tool/main/debian-auto-alibabacloud.cfg \
    DEBIAN_FRONTEND=text" \
  && sudo systemctl kexec
