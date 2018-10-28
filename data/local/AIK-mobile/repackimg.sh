#!/system/bin/sh
# AIK-mobile/repackimg: repack ramdisk and build image
# osm0sis @ xda-developers

case $1 in
  --help) echo "usage: repackimg.sh [--original] [--level <0-9>] [--avbkey <name>] [--forceelf]"; return 1;
esac;

case $0 in
  *.sh) aik="$0";;
     *) aik="$(lsof -p $$ 2>/dev/null | grep -o '/.*repackimg.sh$')";;
esac;
aik="$(dirname "$(readlink -f "$aik")")";
bin="$aik/bin";
rel=bin;
cur="$(readlink -f "$PWD")";

abort() { cd "$aik"; echo "Error!"; }

cd "$aik";
bb=$bin/busybox;
chmod -R 755 $bin *.sh;
chmod 644 $bin/magic $bin/androidbootimg.magic $bin/BootSignature_Android.jar $bin/module.prop $bin/ramdisk.img $bin/avb/* $bin/chromeos/*;

if [ ! -f $bb ]; then
  bb=busybox;
fi;

test "$($bb ps | $bb grep zygote | $bb grep -v grep)" && su="su -mm" || su=sh;

if [ -z "$(ls split_img/* 2>/dev/null)" -o ! -e ramdisk ]; then
  echo "No files found to be packed/built.";
  abort;
  return 1;
fi;

if [ ! "$($bb mount | $bb grep " $aik/ramdisk ")" ]; then
  $su -c "$bb mount -t ext4 -o rw,noatime $aik/split_img/.aik-ramdisk.img $aik/ramdisk" 2>/dev/null;
  if [ $? != "0" ]; then
    for i in 0 1 2 3 4 5 6 7; do
      loop=/dev/block/loop$i;
      $bb mknod $loop b 7 $i 2>/dev/null;
      $bb losetup $loop $aik/split_img/.aik-ramdisk.img 2>/dev/null;
      test "$($bb losetup $loop | $bb grep $aik)" && break;
    done;
    $su -c "$bb mount -t ext4 -o loop,noatime $loop $aik/ramdisk" || return 1;
  fi;
fi;

ramdiskcomp=`cat split_img/*-ramdiskcomp`;
if [ -z "$(ls ramdisk/* 2>/dev/null)" -a ! "$ramdiskcomp" == "empty" ]; then
  echo "No files found to be packed/built.";
  abort;
  return 1;
fi;

case $0 in *.sh) clear;; esac;
echo "\nAndroid Image Kitchen - RepackImg Script";
echo "by osm0sis @ xda-developers\n";

if [ ! -z "$(ls *-new.* 2>/dev/null)" ]; then
  echo "Warning: Overwriting existing files!\n";
fi;

rm -f *-new.*;
while [ "$1" ]; do
  case $1 in
    --original) original=1;;
    --forceelf) repackelf=1;;
    --level)
      case $2 in
        ''|*[!0-9]*) ;;
        *) level="-$2"; lvltxt=" - Level: $2"; shift;;
      esac;
    ;;
    --avbkey)
      if [ "$2" ]; then
        for keytest in "$2" "$cur/$2" "$aik/$2"; do
          if [ -f "$keytest.pk8" -a -f "$keytest.x509."* ]; then
            avbkey="$keytest"; avbtxt=" - Key: $2"; shift; break;
          fi;
        done;
      fi;
    ;;
  esac;
  shift;
done;

if [ "$original" ]; then
  echo "Repacking with original ramdisk...";
elif [ "$ramdiskcomp" == "empty" ]; then
  echo "Warning: Using empty ramdisk for repack!";
  compext=empty;
  touch ramdisk-new.cpio.$compext;
else
  echo "Packing ramdisk...\n";
  test ! "$level" -a "$ramdiskcomp" == "xz" && level=-1;
  echo "Using compression: $ramdiskcomp$lvltxt";
  repackcmd="$bb $ramdiskcomp $level";
  compext=$ramdiskcomp;
  case $ramdiskcomp in
    gzip) compext=gz;;
    lzop) compext=lzo;;
    xz) repackcmd="$bin/xz $level -Ccrc32";;
    lzma) repackcmd="$bin/xz $level -Flzma";;
    bzip2) compext=bz2;;
    lz4) repackcmd="$bin/lz4 $level -l";;
  esac;
  cd ramdisk;
  $bb find . | $bb cpio -H newc -o 2>/dev/null | $repackcmd > ../ramdisk-new.cpio.$compext;
  if [ $? != "0" ]; then
    abort;
    return 1;
  fi;
  cd ..;
fi;

echo "\nGetting build information...";
cd split_img;
imgtype=`cat *-imgtype`;
if [ "$imgtype" != "KRNL" ]; then
  kernel=`ls *-zImage`;               echo "kernel = $kernel";
  kernel="split_img/$kernel";
fi;
if [ "$original" ]; then
  ramdisk=`ls *-ramdisk.cpio*`;       echo "ramdisk = $ramdisk";
  ramdisk="split_img/$ramdisk";
else
  ramdisk="ramdisk-new.cpio.$compext";
fi;
if [ "$imgtype" == "U-Boot" ]; then
  name=`cat *-name`;                  echo "name = $name";
  arch=`cat *-arch`;
  os=`cat *-os`;
  type=`cat *-type`;
  comp=`cat *-comp`;                  echo "type = $arch $os $type ($comp)";
  test "$comp" == "uncompressed" && comp=none;
  addr=`cat *-addr`;                  echo "load_addr = $addr";
  ep=`cat *-ep`;                      echo "entry_point = $ep";
elif [ "$imgtype" == "KRNL" ]; then
  rsz=$($bb wc -c < "$aik/$ramdisk"); echo "ramdisk_size = $rsz";
else
  if [ -f *-second ]; then
    second=`ls *-second`;             echo "second = $second";
    second=(--second "split_img/$second");
  fi;
  if [ -f *-recoverydtbo ]; then
    recoverydtbo=`ls *-recoverydtbo`; echo "recovery_dtbo = $recoverydtbo";
    recoverydtbo=(--recovery_dtbo "split_img/$recoverydtbo");
  fi;
  if [ -f *-cmdline ]; then
    cmdname=`ls *-cmdline`;
    cmdline=`cat *-cmdline`;          echo "cmdline = $cmdline";
    cmd=("split_img/$cmdname"@cmdline);
  fi;
  if [ -f *-board ]; then
    board=`cat *-board`;              echo "board = $board";
  fi;
  base=`cat *-base`;                  echo "base = $base";
  pagesize=`cat *-pagesize`;          echo "pagesize = $pagesize";
  kerneloff=`cat *-kerneloff`;        echo "kernel_offset = $kerneloff";
  ramdiskoff=`cat *-ramdiskoff`;      echo "ramdisk_offset = $ramdiskoff";
  if [ -f *-secondoff ]; then
    secondoff=`cat *-secondoff`;      echo "second_offset = $secondoff";
  fi;
  if [ -f *-tagsoff ]; then
    tagsoff=`cat *-tagsoff`;          echo "tags_offset = $tagsoff";
  fi;
  if [ -f *-osversion ]; then
    osver=`cat *-osversion`;          echo "os_version = $osver";
  fi;
  if [ -f *-oslevel ]; then
    oslvl=`cat *-oslevel`;            echo "os_patch_level = $oslvl";
  fi;
  if [ -f *-headerversion ]; then
    hdrver=`cat *-headerversion`;     echo "header_version = $hdrver";
  fi;
  if [ -f *-hash ]; then
    hash=`cat *-hash`;                echo "hash = $hash";
    hash="--hash $hash";
  fi;
  if [ -f *-dtb ]; then
    dtbtype=`cat *-dtbtype`;
    dtb=`ls *-dtb`;                   echo "dtb = $dtb";
    rpm=("split_img/$dtb",rpm);
    dtb=(--dt "split_img/$dtb");
  fi;
  if [ -f *-unknown ]; then
    unknown=`cat *-unknown`;          echo "unknown = $unknown";
  fi;
  if [ -f *-header ]; then
    header=`ls *-header`;
    header="split_img/$header";
  fi;
fi;
cd ..;

if [ -f split_img/*-mtktype ]; then
  mtktype=`cat split_img/*-mtktype`;
  echo "\nGenerating MTK headers...\n";
  echo "Using ramdisk type: $mtktype";
  $bin/mkmtkhdr --kernel "$kernel" --$mtktype "$ramdisk" >/dev/null;
  if [ $? != "0" ]; then
    abort;
    return 1;
  fi;
  $bb mv -f "$($bb basename "$kernel")-mtk" kernel-new.mtk;
  $bb mv -f "$($bb basename "$ramdisk")-mtk" $mtktype-new.mtk;
  kernel=kernel-new.mtk;
  ramdisk=$mtktype-new.mtk;
fi;

if [ -f split_img/*-sigtype ]; then
  outname=unsigned-new.img;
else
  outname=image-new.img;
fi;

test "$dtbtype" == "ELF" && repackelf=1;
if [ "$imgtype" == "ELF" ] && [ ! "$header" -o ! "$repackelf" ]; then
  imgtype=AOSP;
  echo "\nWarning: ELF format without RPM detected; will be repacked using AOSP format!";
fi;

echo "\nBuilding image...\n";
echo "Using format: $imgtype\n";
case $imgtype in
  AOSP) $bin/mkbootimg --kernel "$kernel" --ramdisk "$ramdisk" "${second[@]}" "${recoverydtbo[@]}" --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff --second_offset "$secondoff" --tags_offset "$tagsoff" --os_version "$osver" --os_patch_level "$oslvl" --header_version "$hdrver" $hash "${dtb[@]}" -o $outname;;
  AOSP-PXA) $bin/pxa-mkbootimg --kernel "$kernel" --ramdisk "$ramdisk" "${second[@]}" --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff --second_offset "$secondoff" --tags_offset "$tagsoff" --unknown $unknown "${dtb[@]}" -o $outname;;
  ELF) $bin/elftool pack -o $outname header="$header" "$kernel" "$ramdisk",ramdisk "${rpm[@]}" "${cmd[@]}" >/dev/null;;
  KRNL) $bin/rkcrc -k "$ramdisk" $outname;;
  U-Boot)
    test "$type" == "Multi" && uramdisk=(:"$ramdisk");
    $bin/mkimage -A $arch -O $os -T $type -C $comp -a $addr -e $ep -n "$name" -d "$kernel""${uramdisk[@]}" $outname >/dev/null;
  ;;
  *) echo "\nUnsupported format."; abort; return 1;;
esac;
if [ $? != "0" ]; then
  abort;
  return 1;
fi;

if [ -f split_img/*-sigtype ]; then
  sigtype=`cat split_img/*-sigtype`;
  if [ -f split_img/*-avbtype ]; then
    avbtype=`cat split_img/*-avbtype`;
  fi;
  if [ -f split_img/*-blobtype ]; then
    blobtype=`cat split_img/*-blobtype`;
  fi;
  echo "Signing new image...\n";
  echo "Using signature: $sigtype $avbtype$avbtxt$blobtype\n";
  test ! "$avbkey" && avbkey="$rel/avb/verity";
  case $sigtype in
    AVB) dalvikvm -Xbootclasspath:/system/framework/core-oj.jar:/system/framework/core-libart.jar:/system/framework/conscrypt.jar:/system/framework/bouncycastle.jar -Xnodex2oat -Xnoimage-dex2oat -cp $bin/BootSignature_Android.jar com.android.verity.BootSignature /$avbtype unsigned-new.img "$avbkey.pk8" "$avbkey.x509."* image-new.img 2>/dev/null;;
    BLOB)
      $bb printf '-SIGNED-BY-SIGNBLOB-\00\00\00\00\00\00\00\00' > image-new.img;
      $bin/blobpack tempblob $blobtype unsigned-new.img >/dev/null;
      cat tempblob >> image-new.img;
      rm -rf tempblob;
    ;;
    CHROMEOS) $bin/futility vbutil_kernel --pack image-new.img --keyblock $rel/chromeos/kernel.keyblock --signprivate $rel/chromeos/kernel_data_key.vbprivk --version 1 --vmlinuz unsigned-new.img --bootloader $rel/chromeos/empty --config $rel/chromeos/empty --arch arm --flags 0x1;;
    DHTB)
      $bin/dhtbsign -i unsigned-new.img -o image-new.img >/dev/null;
      rm -rf split_img/*-tailtype 2>/dev/null;
    ;;
    NOOK*) cat split_img/*-master_boot.key unsigned-new.img > image-new.img;;
  esac;
  if [ $? != "0" ]; then
    abort;
    return 1;
  fi;
fi;

if [ -f split_img/*-lokitype ]; then
  lokitype=`cat split_img/*-lokitype`;
  echo "Loki patching new image...\n";
  echo "Using type: $lokitype\n";
  $bb mv -f image-new.img unlokied-new.img;
  if [ -f aboot.img ]; then
    $bin/loki_tool patch $lokitype aboot.img unlokied-new.img image-new.img >/dev/null;
    if [ $? != "0" ]; then
      echo "Patching failed.";
      abort;
      return 1;
    fi;
  else
    echo "Device aboot.img required in script directory to find Loki patch offset.";
    abort;
    return 1;
  fi;
fi;

if [ -f split_img/*-tailtype ]; then
  tailtype=`cat split_img/*-tailtype`;
  echo "Appending footer...\n";
  echo "Using type: $tailtype\n";
  case $tailtype in
    Bump) $bb printf '\x41\xA9\xE4\x67\x74\x4D\x1D\x1B\xA4\x29\xF2\xEC\xEA\x65\x52\x79' >> image-new.img;;
    SEAndroid) $bb printf 'SEANDROIDENFORCE' >> image-new.img;;
  esac;
fi;

echo "Done!";
return 0;

