# Cisco AIR-CT2504-K9 (2504 Wireless LAN Controller)

## Hardware

| Item          | Details |
|---------------|---------|
| SoC           | Cavium OCTEON CN5230C (pass 2.0), 4 cores, 750 MHz, PRID `0x000d0708` ("Octeon+", CN52xx family) |
| RAM           | 1 GiB DDR2 (330 MHz clock, 660 MT/s) |
| Flash         | 32 MiB parallel NOR (Intel, manufacturer `0x89`, device `0x891f`, CFI command set 1) on boot bus CS0 (`0x1dc00000`), holds the boot loader and its environment |
| Storage       | 1 GB CompactFlash card, true-IDE mode with DMA on boot bus CS2/CS3 (`0x12000000`/`0x13000000`), 16 bit, `pata_octeon_cf` |
| Ethernet      | 4 x 1000BASE-T on SGMII interface 0 of the SoC (GMX0), four Marvell PHYs (PHY ID `0x0141:0x0dc0`) on MDIO bus 0 at addresses 4 to 7 |
| Console       | RJ-45 serial console (Cisco rollover cable 72-3383-01), 9600 8N1, SoC UART0 |
| Other         | I2C controller, GPIO controller, USB controller, hardware watchdog (`octeon_wdt`), RTC battery (CR2032) |
| Boot loader   | Cisco "WLCNG Boot Loader 1.0.20" (Cavium U-Boot derivative, menu driven, no shell) |
| Vendor kernel | MontaVista 2.6.21 `mips64_octeon_v2_be`, no device tree |
| Board type    | `24584` (`WLCNG_SZABLA_CP`) in boot descriptor version 1.2 |

The two other SoC interfaces which show up in the kernel log are internal and
not connected: interface 2 (NPI, `npi0`-`npi3`) and interface 3 (LOOP,
`loop0`-`loop3`).

The SoC's MAC address block comes from the boot loader (`e0:ac:f1:...`),
`eth0` to `eth3` use consecutive addresses.

## Serial console

9600 baud, 8N1, no flow control. The boot loader, its menu and Linux use the
same port. The boot loader flags the console as UART1 in the boot descriptor
although the connector is wired to UART0; the image therefore passes
`console=ttyS0,9600n8` on the kernel command line.

## Boot loader and CF layout

Pressing `ESC` after `Press <ESC> now to access the Boot Menu...` shows the
menu (there is no way to a boot loader shell):

```
 1. Run primary image (7.6.130.0)
 2. Run backup image (...) - Active
 3. Change active boot image
 4. Clear configuration
 5. Format FLASH Drive
 6. Manually update images
```

Without a key press the *active* image is started. OpenWrt lives in the
**backup** slot and is made the active image, the stock software stays in the
primary slot and can be started at any time by selecting 1.

Option 6 starts a small Linux (BusyBox) from the CF card which downloads
images over TFTP and stores them in the image partition (`linux.{pri,bak}.img`,
`cavium_main.{pri,bak}` and the access point images).

The CF card is partitioned like this by the vendor (`format-disk` in the
vendor recovery image):

| Partition   | Size    | Content |
|-------------|---------|---------|
| `/dev/sda1` | 256 MiB | vendor log partition (ext3). **Unused by OpenWrt**, see below |
| `/dev/sda2` | 650 MiB | vendor image partition (ext3): `linux.pri.img`, `linux.bak.img`, `cavium_main.pri`, `cavium_main.bak`, `ap.pri`, `ap.bak` |
| `/dev/sda3` | 64 MiB  | vendor configuration (ext3) |
| `/dev/sda4` | 16 MiB  | "raw", unused by the vendor software. **OpenWrt's squashfs root file system and its (ext4) overlay** |

OpenWrt's kernel is `linux.bak.img` on `/dev/sda2`; this file is replaced as a
whole by `sysupgrade`, as is the root file system on `/dev/sda4`. Do not
put it on `/dev/sda1`: when the stock firmware is started it fails to mount
that partition, and its "repair" destroys whatever is stored there.
Starting the stock firmware and OpenWrt alternately does not damage either,
the root file system and the settings of OpenWrt on `/dev/sda4` were found
unchanged after a stock boot. (The stock software's own settings are on
`/dev/sda3`.)

The boot loader starts two programs for the selected slot:

1. `cavium_main.{pri,bak}`, the vendor's data plane ("Fastpath") application,
   on cores 0 and 1 (`bootoct ... coremask=0x3`), and
2. `linux.{pri,bak}.img`, the kernel, on cores 2 and 3 (`bootoctlinux`,
   `core_mask = 0xc`).

### Image formats

The boot loader is picky:

* `linux.*.img` must be a legacy `uImage` of type **8** (`flat_dt`), OS Linux,
  arch MIPS, compression gzip, load address and entry point 0. Its payload is
  a gzip stream with the original file name **`bzImage`** (the vendor update
  tool checks for the string at file offset 74) and contains the 64 bit big
  endian `vmlinux` ELF with the device tree appended. Other image types, for
  example `kernel` (type 2), are started but never run. `mkimage` can't create
  type 8 for payloads which are not device trees, `image/cisco-rtos-image.py`
  writes the header instead.
* `cavium_main.*` must be a complete 32 bit ELF file including its section
  headers, with the memory layout of the vendor application (code at
  `0x10000018`, data at `0x12226458` and a large zero-filled segment at
  `0x14000000`). A truncated file or a file with just a small code segment
  makes the boot loader reset the board right after `Launching images...`.
  Without `cavium_main.bak` the boot loader starts the stock firmware in the
  primary slot instead.

### Data plane application

The vendor data plane application drives the same packet I/O hardware blocks
(FPA, PKO, IPD) as the OpenWrt Ethernet driver and must not run. OpenWrt
therefore installs its own `cavium_main.bak`, built from
`image/cisco-ct2504-fp.S` and `image/cisco-ct2504-fp.ld` with the toolchain
(`openwrt-octeon-generic-cisco_ct2504-squashfs-cavium_main.elf`, also part of
the sysupgrade file). The boot loader starts it on cores 0 and 1 and hands
only cores 2 and 3 to Linux (`bootoctlinux`, `core_mask = 0xc`, which Linux
reads from the boot information), so:

* the stub parks its core and sets bit 31 in the core's CIU mailbox, which
  tells Linux that the core is available. Linux (see
  `patches-*/160-mips-octeon-use-cores-parked-by-cisco-wlcng-bootloader.patch`)
  adds these cores to its CPU map and writes the physical address of
  `kernel_entry` to the mailbox when it brings the CPU up, upon which the stub
  jumps there and the core becomes a normal secondary CPU. All four cores are
  available.
* the primary slot (stock firmware and its data plane) is not touched.

The boot loader has no CPU hotplug support (`LABI` structure at physical
address `0x700` is missing), hence this scheme.

## Installation

Requirements: serial console, a TFTP server, a network connection to the
first Ethernet port (the one the vendor update tool uses). Keep the stock
firmware in the primary slot.

1. Copy `openwrt-octeon-generic-cisco_ct2504-initramfs-kernel.bin` and
   `openwrt-octeon-generic-cisco_ct2504-squashfs-cavium_main.elf` to the TFTP
   server directory.
2. Power on and press `ESC` when asked. Select **6** (Manually update images).
3. Answer `Y` to DHCP (or enter an address), enter the TFTP server address,
   answer `y` to *update RTOS*, `s` for the *Secondary* image and enter the file
   name of the initramfs image and the name of the `cavium_main.elf` file at
   *Enter filename for FP update*. Answer `N` to the AP image question. The
   unit restarts and shows the menu again.
4. Select **3** (*Change active boot image*) so that `OpenWrt` is the active
   image, then **2** to start it. OpenWrt starts with four CPUs and DHCP on the
   first port (all four ports are bridged as `br-lan`).
5. Copy `openwrt-octeon-generic-cisco_ct2504-squashfs-sysupgrade.tar` to the unit
   (for example with `ssh root@<ip> 'cat > /tmp/fw.tar' < file`) and run
   `sysupgrade -n /tmp/fw.tar`. It writes the kernel to `linux.bak.img`, the
   data plane replacement to `cavium_main.bak` and the root file system to
   `/dev/sda4`, and the unit reboots into the installed system.

From now on OpenWrt starts without a key press or a TFTP server. Later
upgrades are done with `sysupgrade` alone, the settings are kept (they are
saved to `/dev/sda2` and restored at the next boot).

Settings are stored with the usual file system semantics: `sync` after a change
if power is going to be cut straight away (the overlay is ext4 on a CF card).

### Going back to the stock firmware

Select **1** in the boot menu, or make the primary image active again with
**3**. OpenWrt stays installed in the backup slot.

## Board management FPGA

The vendor recovery tools (`fpga_upgrade`, `mcu_upgrade`, `usb_upgrade`) and the
vendor kernel module `wlcng_fpga.ko` show that the board has a management
FPGA ("PIC") on the boot bus, mapped at physical address `0x16000000` (the
tools `mmap` `0xb6000000`) which provides the hardware watchdog, fan, voltage,
temperature and power supply alarms, the reset reason and a keep-alive for a
separate microcontroller (MCU). The FPGA image shipped by Cisco (revision 01.07,
inside the 2.0.0.0 field upgrade bundle) is raw configuration data without a
vendor header; the part number is not known.

* the boot loader leaves chip select 1 (`MIO_BOOT_REG_CFG1`) disabled, only
  CS0 (NOR), CS2 and CS3 (CF) are set up when Linux starts. Reading the FPGA
  window without programming CS1 hangs the board (hard reset needed).
* with CS1 enabled (8 or 16 bit, CS2's timing) the first 64 bytes of the window
  read as zero, the bus width and timing the vendor kernel uses are not known.

## Power over Ethernet

The two PoE capable ports are powered by a Texas Instruments **TPS23861** PSE
controller on the second I2C controller of the SoC (bus 1, address `0x20`).
Only channels 1 and 2 are connected (the detection/classification enable bits
of channels 3 and 4 stay zero). Which front panel ports they are is
unverified: it needs a powered device (the owner expects the two last ports).

The vendor software (`switchdrvr`, `wlcngPoeNotify()`) controls it with plain
register accesses to `0x20` on `/dev/i2c-1`:

* at the first use it writes interrupt mask `0xe4`, operating mode `0xff`
  (auto mode on all channels), disconnect enable `0xf0` and detect/class
  enable `0xff`. The controller comes out of reset with all ports off, so
  something has to select a mode.
* enable of port *n* writes `1 << n` to the power enable register `0x19` and
  sets bits *n* and *n + 4* in the detect/class enable register `0x14`,
  disable writes `1 << (n + 4)` to `0x19`.
* port power status is bit *n + 4* of register `0x10`.

OpenWrt uses the mainline `tps23861` hwmon driver (`kmod-hwmon-tps23861`).
The device tree sets `ti,operating-mode = "auto"`, a property added by
`patches-*/161-hwmon-tps23861-add-operating-mode-property.patch`, so that the
ports are not left in shutdown. Use it with:

```
cd /sys/class/hwmon/hwmon0              # name: tps23861
cat in0_input curr1_input temp1_input   # port 1 voltage (mV), current (mA), die temp
echo 0 > in0_enable                     # power port 1 off
echo 1 > in0_enable                     # restart detection, powers a connected device
cat /sys/kernel/debug/i2c/i2c-1/1-0020/port_status   # detection, class, mode per port
```

`in0`/`in1` and `curr1`/`curr2` are the connected channels, `in4` is the PoE
input voltage (about 59 V on the test unit).

Other devices found on the I2C buses: bus 0 has `0x51` and a DS1337 RTC at
`0x68` (the vendor kernel registers `ds1307` there), bus 1 has `0x0c`, `0x2e`,
`0x30`, `0x50` and `0x51` besides the PSE. The vendor kernel registers
EEPROMs at `0x50` and `0x51` on bus 1; the rest is not identified.

## Notes for developers

* There is no device tree in the stock kernel. The description was derived
  from the boot loader's boot descriptor and the `MIO_BOOT_REG_CFGx`
  registers (CS0 NOR, CS2/CS3 CF), the PHY addresses were found by scanning
  the MDIO bus.
* An appended device tree is not pruned by the kernel; everything the board
  needs is described in the DTS.
* `sysupgrade` runs in the initramfs image as well.

## Known issues

* Only the first Ethernet port has been seen with link in the author's setup,
  the mapping of `eth1` to `eth3` (and of the service port, if it isn't one of
  the four) to the connectors has not been verified.
* PoE is implemented with the `tps23861` hwmon driver but has not been tried with a
  powered device yet: the mapping of PoE channels 1 and 2 to the front panel
  ports and the actual power up are unverified.
* The NOR flash (boot loader and environment, which holds the active image
  setting), USB, the RTC and the other I2C devices and the front panel LEDs are not used.
* The overlay is small (about 10 MiB), it is the 16 MiB partition the vendor
  doesn't use.
