/*
 * yupp-buttons: the mirror's three buttons as an input device.
 *
 * Under the power button sit volume up, volume down and the Bluetooth button,
 * GPIOs 0, 1 and 2 of an Exar XR20M1172 at i2c7 0x30, active low. Its
 * interrupt line does not reach Linux, so the state register is polled over
 * i2c-dev every 10 ms, as yuppd does on the Armbian image
 * (hardware/buttons/expander_yupp.go), and changes go out through uinput:
 * KEY_VOLUMEUP, KEY_VOLUMEDOWN and KEY_HELP (Android's Generic.kl maps them
 * to VOLUME_UP, VOLUME_DOWN and HELP). Android repeats a held volume key
 * itself.
 *
 * The chip's I2C sub-address is reg << 3 (channel A), as on the SC16IS7xx;
 * IOState is register 0x0B and reads 0xFF with nothing pressed.
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <linux/uinput.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define BUS "/dev/i2c-7"
#define ADDR 0x30
#define REG_IOSTATE 0x0B

static const int keys[3] = { KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_HELP };

static int read_state(int bus, uint8_t *state)
{
	uint8_t sub = REG_IOSTATE << 3;

	if (write(bus, &sub, 1) != 1 || read(bus, state, 1) != 1)
		return -1;
	return 0;
}

static void emit(int ui, int type, int code, int value)
{
	struct input_event ev;

	memset(&ev, 0, sizeof(ev));
	ev.type = type;
	ev.code = code;
	ev.value = value;
	if (write(ui, &ev, sizeof(ev)) != sizeof(ev))
		perror("yupp-buttons: uinput write");
}

static int open_uinput(void)
{
	struct uinput_user_dev dev;
	int ui, i;

	ui = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
	if (ui < 0)
		return -1;
	ioctl(ui, UI_SET_EVBIT, EV_KEY);
	for (i = 0; i < 3; i++)
		ioctl(ui, UI_SET_KEYBIT, keys[i]);
	memset(&dev, 0, sizeof(dev));
	snprintf(dev.name, UINPUT_MAX_NAME_SIZE, "yupp-buttons");
	dev.id.bustype = BUS_I2C;
	dev.id.vendor = 0x1d6b;
	dev.id.product = 0x0001;
	if (write(ui, &dev, sizeof(dev)) != sizeof(dev) || ioctl(ui, UI_DEV_CREATE) < 0) {
		close(ui);
		return -1;
	}
	return ui;
}

int main(void)
{
	const struct timespec tick = { 0, 10 * 1000 * 1000 };
	uint8_t state, last = 0xff;
	int bus, ui, i, errors = 0;

	bus = open(BUS, O_RDWR);
	if (bus < 0 || ioctl(bus, I2C_SLAVE, ADDR) < 0) {
		fprintf(stderr, "yupp-buttons: %s 0x%02x: %s\n", BUS, ADDR, strerror(errno));
		return 1;
	}
	ui = open_uinput();
	if (ui < 0) {
		fprintf(stderr, "yupp-buttons: uinput: %s\n", strerror(errno));
		return 1;
	}

	for (;;) {
		nanosleep(&tick, NULL);
		if (read_state(bus, &state) < 0) {
			/* A bus error now and then is no reason to stop; a dead
			 * chip is, so init restarts us and logs it. */
			if (++errors > 500) {
				fprintf(stderr, "yupp-buttons: %s: %s\n", BUS, strerror(errno));
				return 1;
			}
			continue;
		}
		errors = 0;
		for (i = 0; i < 3; i++) {
			int was = !(last & (1 << i)), now = !(state & (1 << i));

			if (was != now) {
				emit(ui, EV_KEY, keys[i], now);
				emit(ui, EV_SYN, SYN_REPORT, 0);
			}
		}
		last = state;
	}
}
