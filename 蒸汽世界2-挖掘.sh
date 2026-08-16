#!/bin/bash

# PortMaster preamble
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi
source $controlfolder/control.txt 
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls
# Swap management
is_swap_active() {
    grep -q -E "zram0|swapfile" /proc/swaps 2>/dev/null
}

setup_swap() {
    local size_mb=\$1
    if sudo modprobe zram 2>/dev/null; then
        # lz4 not supported on this device
        echo \${size_mb}M > /sys/block/zram0/disksize
        sudo mkswap /dev/zram0 2>/dev/null
        sudo swapon /dev/zram0 -p 100 2>/dev/null
        if grep -q zram0 /proc/swaps 2>/dev/null; then
            return 0
        fi
    fi
    sudo fallocate -l \${size_mb}M /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=\${size_mb} status=none
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile 2>/dev/null
    sudo swapon /swapfile 2>/dev/null
}

teardown_swap() {
    sudo swapoff /swapfile 2>/dev/null; sudo rm -f /swapfile 2>/dev/null
    sudo swapoff /dev/zram0 2>/dev/null; echo 1 > /sys/block/zram0/reset 2>/dev/null || true
}

SWAP_WAS_ACTIVE=false
if is_swap_active; then
    SWAP_WAS_ACTIVE=true
else
    setup_swap 1024
fi




GAMEDIR="/$directory/ports/steamworlddig2/"
SAVEDIR="$GAMEDIR/savedata/"
CONFDIR="$GAMEDIR/savedata/"
mkdir -p "$GAMEDIR/savedata/"
# Audio fix for ArkOS
if [ -f "/usr/local/bin/console_detect" ] && [ -f "/opt/system/Tools/PortMaster/libs/asound.conf" ]; then
  cp "/opt/system/Tools/PortMaster/libs/asound.conf" "${HOME}/.asoundrc"
fi
cd "$GAMEDIR/"

# Figure out of the User OS has working XBOX controls on GPTOKEY2 or not
if [[ "$CFW_NAME" = "AmberELEC" ]]; then
    badgptokey_mode=1
elif [[ "$CFW_NAME" = "ArkOS AeUX" ]]; then
    badgptokey_mode=1
else
    badgptokey_mode=0
fi

# Warn about Panfrost incompatability on ROCKNIX
if [[ "$CFW_NAME" = "ROCKNIX" ]]; then
    if glxinfo | grep "OpenGL version string"; then
    pm_message "This Port only supports the libMali graphics driver. Switch to from Panfrost to libMali to continue."
    sleep 5
    exit 1
    fi
fi


# Seizure Warning on ROCKNIX
if [[ "$CFW_NAME" = "ROCKNIX" ]]; then
    pm_message "SEIZURE WARNING. When playing on ROCKNIX, you may potentially experience screen flashing. Only some devices have this happen. Either way proceed with caution"
    sleep 5
fi

# Unpack GOG Files
$ESUDO chmod 777 "$GAMEDIR/unzip"
LD_LIBRARY_PATH="$GAMEDIR/tools/libs.aarch64"
if ls $GAMEDIR/installer/*.sh 1> /dev/null 2>&1; then
  pm_message "Unpacking GOG installer. This will take a minute or two...."
  sleep 5
  # extract
  LD_LIBRARY_PATH=$GAMEDIR/libs.${DEVICE_ARCH} "$GAMEDIR/unzip" "$GAMEDIR/installer/*.sh" "data/noarch/game/*" -d "$GAMEDIR"
  rm -rf "$GAMEDIR/installer/" 
  mv "$GAMEDIR/data/noarch/game/"* "$GAMEDIR/"
  rm -rf "$GAMEDIR/data/" 
fi

# Set the XDG environment variables for config & savefiles
export XDG_DATA_HOME="$GAMEDIR/savedata/"

# Logging
> "${GAMEDIR}/log.txt" && exec > >(tee "${GAMEDIR}/log.txt") 2>&1

#Delete install.sh from the gog game files
if ls $GAMEDIR/install.sh 1> /dev/null 2>&1; then
 rm -rf "$GAMEDIR/install.sh"
fi

# Mount Weston runtime
weston_dir=/tmp/weston
$ESUDO mkdir -p "${weston_dir}"
weston_runtime="weston_pkg_0.2"
if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${weston_runtime}.squashfs"
fi
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "${weston_dir}"
fi
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"


# Seperate the Controller/Keyboard inputs for GPTOKEY2, since its broken on arkos/amberelec
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$GAMEDIR/lib_dep
if [ "$badgptokey_mode" -eq 0 ]; then 
	$GPTOKEYB "Dig2" -x &
else
	$GPTOKEYB "Dig2" -c "$GAMEDIR/Dig2.gptk" &
fi
unset XDG_DATA_HOME
# pm_platform_helper "$GAMEDIR/box64"

$ESUDO env WRAPPED_PRELOAD="$GAMEDIR/x11sdllib.aarch64/libSDL2-2.0.so.0" WRAPPED_LIBRARY_PATH="$GAMEDIR/steamworld/libs.${DEVICE_ARCH}/":"$GAMEDIR/libs.aarch64":"/usr/lib":"/usr/lib64":"$GAMEDIR/x11sdllib.aarch64/":"$GAMEDIR/libs.x64/" $weston_dir/westonwrap.sh drm gl kiosk crusty_glx_gl4es \
BOX64_LD_LIBRARY_PATH="$GAMEDIR/box64/lib:/usr/lib64/:./:lib/:lib64/:x86/" \
LIBGL_NOBANNER=1 BOX64_DYNAREC=1 BOX64_DLSYM_ERROR=1 BOX64_SHOWSEGV=1 BOX64_SHOWBT=1 \
XDG_DATA_HOME=$CONFDIR "$GAMEDIR/box64" "$GAMEDIR/Dig2"


#Clean up after ourselves
$ESUDO $weston_dir/westonwrap.sh cleanup
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "${weston_dir}"
fi
# pm_finish
# Cleanup swap
if [ "$SWAP_WAS_ACTIVE" = false ]; then teardown_swap; fi

                                           