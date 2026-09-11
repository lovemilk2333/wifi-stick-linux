// SPDX-License-Identifier: GPL-2.0
/*
 * Boot smoke test for the QEMU test kernel. See kernel-ci/README.md.
 *
 * Cross-compiled with `aarch64-linux-gnu-gcc -static` and packed as /init of
 * a minimal initramfs. It runs as PID 1 on qemu-system-aarch64 -M virt,
 * asserts that the interfaces the wifi-stick-usb-switcher test environment
 * depends on exist, performs one real configfs gadget bind against the
 * virtual UDC, prints "SMOKE:" markers and powers the machine off.
 *
 * A static binary rather than a busybox shell keeps this check free of any
 * download and independent of the runner's own (x86_64) userland.
 */

#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <unistd.h>

/* Syscall numbers for reboot(2); sys/reboot.h is not exposed for glibc. */
#include <linux/reboot.h>
#include <sys/syscall.h>

static int failures;

static int check_path(const char *path)
{
	struct stat st;

	if (stat(path, &st) == 0) {
		printf("SMOKE: ok   %s\n", path);
		return 0;
	}

	printf("SMOKE: MISS %s (%s)\n", path, strerror(errno));
	failures++;
	return -1;
}

static int write_file(const char *path, const char *value)
{
	size_t len = strlen(value);
	ssize_t written;
	int fd;

	fd = open(path, O_WRONLY);
	if (fd < 0)
		return -1;

	written = write(fd, value, len);
	close(fd);

	return written == (ssize_t)len ? 0 : -1;
}

static int make_dir(const char *path)
{
	if (mkdir(path, 0755) == 0)
		return 0;

	return errno == EEXIST ? 0 : -1;
}

/*
 * Creates a configfs gadget and binds it to the dummy UDC — the same
 * sequence the switcher performs on the device for every mode change.
 */
static void gadget_bind(void)
{
	static const char *udc = "dummy_udc.0";
	char buf[64];
	int fd;
	ssize_t n;

	if (make_dir("/sys/kernel/config/usb_gadget/smoke") != 0) {
		printf("SMOKE: MISS cannot create gadget dir (%s)\n",
		       strerror(errno));
		failures++;
		return;
	}

#define G(p) "/sys/kernel/config/usb_gadget/smoke" p
	if (write_file(G("/idVendor"), "0x1d6b") != 0 ||
	    write_file(G("/idProduct"), "0x0104") != 0 ||
	    make_dir(G("/configs/c.1")) != 0 ||
	    make_dir(G("/functions/rndis.usb0")) != 0) {
		printf("SMOKE: MISS cannot build gadget (%s)\n", strerror(errno));
		failures++;
		return;
	}

	if (symlink(G("/functions/rndis.usb0"), G("/configs/c.1/rndis.usb0")) != 0 &&
	    errno != EEXIST) {
		printf("SMOKE: MISS cannot link function (%s)\n", strerror(errno));
		failures++;
		return;
	}

	if (write_file(G("/UDC"), udc) != 0) {
		printf("SMOKE: MISS cannot bind %s (%s)\n", udc, strerror(errno));
		failures++;
		return;
	}

	fd = open(G("/UDC"), O_RDONLY);
	if (fd < 0) {
		printf("SMOKE: MISS cannot read back UDC\n");
		failures++;
		return;
	}
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0) {
		printf("SMOKE: MISS empty UDC after bind\n");
		failures++;
		return;
	}
	buf[n] = '\0';
	buf[strcspn(buf, "\n")] = '\0';

	if (strcmp(buf, udc) != 0) {
		printf("SMOKE: MISS UDC is `%s`, expected `%s`\n", buf, udc);
		failures++;
		return;
	}

	printf("SMOKE: ok   bound %s with rndis.usb0\n", udc);
#undef G
}

int main(void)
{
	struct utsname uts;

	/* No tty: keep every marker in the serial log even on poweroff. */
	setvbuf(stdout, NULL, _IONBF, 0);

	make_dir("/proc");
	make_dir("/sys");
	make_dir("/dev");
	mount("proc", "/proc", "proc", 0, NULL);
	mount("sysfs", "/sys", "sysfs", 0, NULL);
	mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);

	make_dir("/sys/kernel");
	make_dir("/sys/kernel/config");
	if (mount("configfs", "/sys/kernel/config", "configfs", 0, NULL) != 0 &&
	    errno != EBUSY)
		printf("SMOKE: warn configfs mount failed (%s)\n", strerror(errno));

	if (uname(&uts) == 0)
		printf("SMOKE: running %s on %s\n", uts.release, uts.machine);

	check_path("/sys/class/udc/dummy_udc.0");
	check_path("/sys/kernel/config/usb_gadget");
	check_path("/sys/class/leds");
	check_path("/dev/input");
	check_path("/dev/uinput");
	check_path("/dev/uleds");

	if (failures == 0)
		gadget_bind();

	printf("SMOKE: RESULT %s\n", failures == 0 ? "PASS" : "FAIL");

	fflush(stdout);
	sync();
	syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		LINUX_REBOOT_CMD_POWER_OFF, NULL);

	/* Only reached if poweroff is unavailable. */
	for (;;)
		pause();

	return failures == 0 ? 0 : 1;
}
