# vm-deploy.sh
A provisioning tool for installing
Debian-based VMs from the command line.

## Requirements
- debootstrap

## How to use
Rename or copy the `vm-deploy.conf.example` file to `vm-deploy.conf`
and adjust it according your needs.

The following command demonstrates the deployment
of the host "test.example.com":

```
./vm-deploy.sh --hostname test.example.com --dist buster --ip 192.168.1.10 --bridge br0 --lvm vg0 --size 5G --memory 256M --vcpus 1
```

## Options
```
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
```

## License
This code is released under GPLv2. Please checkout the source code to
examine license headers.

