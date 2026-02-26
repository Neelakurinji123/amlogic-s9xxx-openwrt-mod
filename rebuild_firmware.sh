#!/bin/bash

openwrt_gz_file=$1
working_dir='.working_dir'
libreelec_gz_file=$(ls LibreELEC-AMLGX.aarch64*.gz)
openwrt_file="$(basename ${openwrt_gz_file%%.img.gz})_mod.img"
libreelec_file=$(basename ${libreelec_gz_file%%.gz})
comment=''

echo """
################################################################################

    Openwrt-Amlogic's firmware rebuilder for s905x and s912

################################################################################
"""

check () {
    if [ $? -eq 0 ]; then
        echo " OK"
    else
        echo " ! --- failed"
        exit 1
    fi
}

#check
#exit

extract () {
    echo " * Extracting from firmwares"

    mkdir -p $working_dir
    echo -e -n "\t - Extracting Openwrt: "
    gunzip -q -c $openwrt_gz_file > $working_dir/$openwrt_file
    check
    echo -e -n "\t - Extracting LibreELEC: "
    gunzip -q -c $libreelec_gz_file > $working_dir/$libreelec_file
    check
    echo -e -n "\t - Extracting a part of image from LIbreELEC: "
    dd if=$working_dir/$libreelec_file of=$working_dir/libreelec_part.img bs=512 count=8192 2>/dev/null
    check
    echo -e -n "\t - Analyzing partition: "
    partitions_json=$(parted -j $working_dir/$openwrt_file unit s print)
    openwrt_sector_size=$(echo $partitions_json | jq -r .disk'.["logical-sector-size"]') &&
    _openwrt_boot_start=$(echo $partitions_json | jq -r .disk.partitions[0].start) && openwrt_boot_start=${_openwrt_boot_start%s} &&
    _openwrt_boot_end=$(echo $partitions_json | jq -r .disk.partitions[0].end) && openwrt_boot_end=${_openwrt_boot_end%s} &&
    _openwrt_boot_sectors=$(echo $partitions_json | jq -r .disk.partitions[0].size) && openwrt_boot_sectors=${_openwrt_boot_sectors%s} &&
    _openwrt_rootfs_start=$(echo $partitions_json | jq -r .disk.partitions[1].start) && openwrt_rootfs_start=${_openwrt_rootfs_start%s} &&
    _openwrt_rootfs_end=$(echo $partitions_json | jq -r .disk.partitions[1].end) && openwrt_rootfs_end=${_openwrt_rootfs_end%s} &&
    _openwrt_rootfs_sectors=$(echo $partitions_json | jq -r .disk.partitions[1].size) && openwrt_rootfs_sectors=${_openwrt_rootfs_sectors%s}
    check

#    dd if=$working_dir/libreelec_part.img of=$working_dir/$openwrt_file bs=512 count=8192 2>/dev/null
#    echo "$openwrt_sector_size $openwrt_boot_start $openwrt_boot_end $openwrt_boot_sectors $openwrt_rootfs_start $openwrt_rootfs_end $openwrt_rootfs_sectors"

    echo -e -n "\t - Extracting boot partition of Openwrt: "
    dd if=$working_dir/$openwrt_file of=$working_dir/openwrt_boot.img bs=$openwrt_sector_size skip=$openwrt_boot_start count=$openwrt_boot_sectors 2>/dev/null
    check
    echo -e -n "\t - Extracting rootfs partition of Openwrt: "
    dd if=$working_dir/$openwrt_file of=$working_dir/openwrt_rootfs.img bs=$openwrt_sector_size skip=$openwrt_rootfs_start count=$openwrt_rootfs_sectors 2>/dev/null
    check
}

build () {
    echo
    echo " * Building firmwares"

    loop=$(losetup -f)
    if [ $loop == '/dev/loop0' ]; then
        loop='/dev/loop1'
    fi

    losetup $loop $working_dir/$openwrt_file
    echo -e -n "\t - Inserting a part of LibreELEC's firmware into Openwrt's firmware: "
    dd if=$working_dir/libreelec_part.img of=$loop bs=512 count=8192 2>/dev/null
    check
    echo -e -n "\t - Adjusting partitions of Openwrt: "
    parted --script $loop rm 1 rm 2 unit s mkpart primary fat32 ${openwrt_boot_start}s \
        ${openwrt_boot_end}s mkpart primary btrfs ${openwrt_rootfs_start}s ${openwrt_rootfs_end}s \
        set 1 lba on quit
    check
    echo -e -n "\t - Restoring boot partition of Openwrt: "
    dd if=$working_dir/openwrt_boot.img of=${loop}p1 bs=512 2>/dev/null
    check
    echo -e -n "\t - Restoring rootfs paertition of Openwrt: "
    dd if=$working_dir/openwrt_rootfs.img of=${loop}p2 bs=512 2>/dev/null
    check
    sync
    losetup -d $loop
}

extract
build
mv $working_dir/$openwrt_file .

echo
echo " Operation has finished successfully. "
echo " New filename is $openwrt_file. "
