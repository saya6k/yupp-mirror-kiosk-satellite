/*
 * reboot-to MODE: restarts with a reboot argument, straight through the
 * kernel (LINUX_REBOOT_CMD_RESTART2), the way Android's init would but
 * without init writing a bootloader message to misc. The kernel's
 * reboot-mode driver puts MODE in the PMU register Rockchip's U-Boot reads
 * once, so "recovery" boots the recovery partition a single time and a
 * power cycle is back to the boot partition.
 */
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/reboot.h>

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: %s MODE\n", argv[0]);
		return 2;
	}
	sync();
	return syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		       LINUX_REBOOT_CMD_RESTART2, argv[1]) ? 1 : 0;
}
