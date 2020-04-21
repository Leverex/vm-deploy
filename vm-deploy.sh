#!/usr/bin/env sh

# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2019-present Leverex (leverex@liser.tv)

set -a

VERSION=0.1.1

# Get source directory of our script
BASE_DIR="$( cd "$( dirname "$(readlink -f "$0")" )" >/dev/null && pwd )"

# Path to config file
CONFIG_FILE="${BASE_DIR}/vm-deploy.conf"

# Path to hook directory
HOOK_DIR="${BASE_DIR}/hooks"

# Source our common functions
. "${HOOK_DIR}/common.sh"

# Source configuration file
if [ ! -f "${CONFIG_FILE}" ]; then
    log_msg err "You need to create a vm-deploy.conf file." \
                "See vm-deploy.conf.example for reference."
    exit 1
fi

. "${CONFIG_FILE}"

print_usage() {
    printf "vm-deploy.sh %s

Provisioning tool for installing Debian-based VMs from the command line.

Options:
    --hostname       Set the fully-qualified hostname of the guest

    --arch           [i386|amd64]
    --dist           [buster|oldstable|stable|unstable]

    --mirror         Set the mirror to use when installing via
                     debootstrap [http://ftp.us.debian.org]

    --lvm            Set the volume group to save images within
    --image-dev      Set a physical/logical volume for the disk image

    --vcpus          Set the amount of vcpus allocated to the guest

    --memory         Set the amount of memory allocated to the guest (M, G)

    --size           Set the root disk size (M, G)

    --dhcp           Configure dynamic networking

    --ip             Configure a static IP address
    --netmask        Set the netmask address
    --gateway        Set the gateway address
    --broadcast      Set the broadcast address
    --ptp            Set the pointopoint address

    --nameserver     Set the nameserver address

    --mac            Set a custom mac address

    --bridge         Set the network bridge

    -v, --verbose    Verbose mode (show info messages)
    -h, --help       Show this help text and exit

" "${VERSION}"
}

while [ "$1" ]; do
    case $1 in
        --hostname)
            hostname="$2"
            shift
            ;;
        --arch)
            arch="$2"
            shift
            ;;
        --dist)
            dist="$2"
            shift
            ;;
        --mirror)
            mirror="$2"
            shift
            ;;
        --vcpus)
            vcpus="$2"
            shift
            ;;
        --memory)
            memory="$2"
            shift
            ;;
        --size)
            size="$2"
            shift
            ;;
        --dhcp)
            dhcp=1
            ;;
        --ip)
            ip="$2"
            shift
            ;;
        --netmask)
            netmask="$2"
            shift
            ;;
        --gateway)
            gateway="$2"
            shift
            ;;
        --broadcast)
            broadcast="$2"
            shift
            ;;
        --ptp)
            ptp="$2"
            shift
            ;;
        --nameserver)
            nameserver="$2"
            shift
            ;;
        --mac)
            mac="$2"
            shift
            ;;
        --bridge)
            bridge="$2"
            shift
            ;;
         --lvm)
            lvm="$2"
            shift
            ;;
        --image-dev)
            image_dev="$2"
            shift
            ;;
        -v|--verbose)
            verbose=1
            ;;
        -h|--help|--usage)
            print_usage
            exit 0
            ;;
        *)
            print_usage
            printf "Unknown parameter: %s\\n" "$1"
            exit 1
            ;;
    esac
    shift
done

# Get the non-fqdn hostname of the guest
guest_name="$( printf "%s" "${hostname}" | awk -F'.' '{print $1}' )"

# Generate the mac address if none given
mac="${mac:=$( generate_mac_addr "${hostname}" )}"

# Convert memory to MB and remove the suffix
case "${memory}" in
    *G|*GB)
        memory=$(( ${memory%G*} * 1024 ))
        ;;
    *M|*MB)
        memory="${memory%M*}"
        ;;
esac

printf "%s" "vm-deploy.sh ${VERSION}

  --hostname ${hostname:?}
  --arch ${arch:-(unset)}
  --dist ${dist:?}
  --mirror ${mirror:?}
  --vcpus ${vcpus:?}
  --memory ${memory:?}
  --size ${size:?}
  --dhcp ${dhcp:-(unset)}
  --ip ${ip:-(unset)}
  --netmask ${netmask:-(unset)}
  --gateway ${gateway:-(unset)}
  --broadcast ${broadcast:-(unset)}
  --ptp ${ptp:-(unset)}
  --nameserver ${nameserver:-(unset)}
  --mac ${mac:-(unset)}
  --bridge ${bridge:-(unset)}
  --install-method ${install_method:?}
  --lvm ${lvm:-(unset)}
  --image-dev ${image_dev:-(unset)}

"
printf "%s\\n" "Please check these options carefully." \
       "Existing physical/logical volumes will be overwritten !!"

ask_yn "Do you want to continue? [y/N] " || exit 1

set -e

# Create the logical volume
if [ -n "${lvm}" ]; then
    image_dev="/dev/${lvm}/${guest_name}-vol0"
    if [ -e "${image_dev}" ]; then
        log_msg err "The logical volume '${image_dev}' already exists."
        exit 1
    else
        lvcreate -L "${size}" -n "${guest_name}-vol0" "${lvm}"
    fi
fi

if [ ! -e "${image_dev}" ]; then
    log_msg err "The physical/logical volume '${image_dev}' doesn't exist."
    exit 1
fi

# Set a cleanup trap
trap 'cleanup; trap - EXIT; exit' EXIT INT HUP

# Create the loop device
loop_dev="$(losetup --find --show --partscan "${image_dev}")"

# Partition target device
printf "start=2048,type=83,bootable" | sfdisk "${loop_dev}"

# Format target partition
"mkfs.${fs:-ext4}" "${loop_dev}p1"

# Create temporary mountpoint
mount_point="$(mktemp -d -t vm-XXXXXXXXXX)"

if [ ! -d "${mount_point}" ]; then
    log_msg err "Couldn't create temporary mountpoint '${mount_point}'."
    exit 1
fi

# Mount target partition
mount "${loop_dev}p1" "${mount_point}"

# Assemble the debootstrap command
if [ -z "${debootstrap_cmd}" ]; then
    debootstrap_cmd="/usr/sbin/debootstrap"
fi

if [ -n "${verbose}" ]; then
    flags="--verbose"
fi

if [ -n "${arch}" ]; then
    flags="${flags} --arch ${arch}"
fi

if [ -n "${add_packages}" ]; then
    flags="${flags} --include ${add_packages}"
fi

# Install the base system via debootstrap
# shellcheck disable=SC2086
${debootstrap_cmd} ${flags} ${dist} "${mount_point}" "${mirror}"

set +e

# Run hooks on the target
if [ -d "${HOOK_DIR}/${dist}.d" ]; then
    printf "Hooks for %s present.\\n" "${dist}"

    for hook in "${HOOK_DIR}/${dist}.d/"*; do
      if [ -x "${hook}" ]; then
          "${hook}" "${mount_point}"
      fi
    done
fi

# Finalize guest image
mv "${mount_point}/etc/resolv.conf.old" "${mount_point}/etc/resolv.conf"

printf "Setting up root password:\\n"
until chroot "${mount_point}" /usr/bin/passwd; do
    sleep 2
done

# Deploy xl / libvirt guest config
if [ "${virt_type}" = "kvm" ]; then

    virt-install \
      --import \
      --name ${guest_name} \
      --memory ${memory} \
      --vcpus ${vcpus} \
      --cpu host \
      --disk path=${image_dev},bus=virtio \
      --network bridge=${bridge},mac=${mac},model=virtio \
      --os-type linux \
      --os-variant generic \
      --graphics vnc,listen=0.0.0.0 \
      --console pty,target_type=serial \
      --noautoconsole

elif [ "${virt_type}" = "xen-pv" ] || \
     [ "${virt_type}" = "xen-pvh" ]; then

    xen_guest_config_file="/etc/xen/${guest_name}.cfg"
    . "${BASE_DIR}/xen.tmpl"

fi

exit 0
