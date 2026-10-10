/*
 * rretina_resize: follows the size of the host window on QEMU's virtio-gpu.
 *
 * QEMU proposes the size of its window (resized, or full screen) as the
 * display's preferred size; the virtio_gpu driver reports it through
 * VIRTIO_GPU_GET_PREFERRED_SIZE (renku-retina patch 0004). This background
 * application asks every half second and switches the screen to it once it
 * has held still for a second, the way a window manager on other systems
 * follows the host window. It quits when there is no virtio-gpu display.
 *
 * QEMU's cocoa display on a Retina Mac reports the window in points, not
 * pixels. ~/config/settings/rretina_resize may say "host_scale 2": the
 * screen is then made twice the window's point size, which QEMU (with
 * -display cocoa,zoom-to-fit=on) draws one guest pixel per physical pixel.
 *
 * Distributed under the terms of the MIT License.
 */

#include <Application.h>
#include <Directory.h>
#include <Entry.h>
#include <FindDirectory.h>
#include <MessageRunner.h>
#include <Path.h>
#include <Screen.h>

#include <algorithm>

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include <virtio_info.h>


static const uint32 kMsgPoll = 'poll';
static const bigtime_t kPollInterval = 500000;


class ResizeApp : public BApplication {
public:
	ResizeApp()
		:
		BApplication("application/x-vnd.renku-rretina-resize"),
		fDevice(-1),
		fRunner(NULL),
		fCandidateWidth(0),
		fCandidateHeight(0),
		fStablePolls(0),
		fHostScale(_ReadHostScale())
	{
	}

	~ResizeApp()
	{
		delete fRunner;
		if (fDevice >= 0)
			close(fDevice);
	}

	void ReadyToRun()
	{
		fDevice = _OpenDevice();
		if (fDevice < 0) {
			Quit();
			return;
		}
		BMessage poll(kMsgPoll);
		fRunner = new BMessageRunner(be_app_messenger, &poll, kPollInterval);
	}

	void MessageReceived(BMessage* message)
	{
		if (message->what == kMsgPoll)
			_Poll();
		else
			BApplication::MessageReceived(message);
	}

private:
	static float _ReadHostScale()
	{
		BPath path;
		if (find_directory(B_USER_SETTINGS_DIRECTORY, &path) != B_OK
			|| path.Append("rretina_resize") != B_OK)
			return 1.0f;

		float scale = 1.0f;
		FILE* file = fopen(path.Path(), "r");
		if (file == NULL)
			return scale;
		char line[128];
		while (fgets(line, sizeof(line), file) != NULL) {
			float value;
			if (sscanf(line, " host_scale %f", &value) == 1
				&& value >= 1.0f && value <= 4.0f)
				scale = value;
		}
		fclose(file);
		return scale;
	}

	static int _OpenDevice(const char* directoryPath = "/dev/graphics")
	{
		// virtio_gpu publishes its node as /dev/graphics/virtio/<n>
		BDirectory directory(directoryPath);
		BEntry entry;
		while (directory.GetNextEntry(&entry) == B_OK) {
			BPath path;
			if (entry.GetPath(&path) != B_OK)
				continue;
			if (entry.IsDirectory()) {
				if (strncmp(path.Leaf(), "virtio", 6) == 0) {
					int device = _OpenDevice(path.Path());
					if (device >= 0)
						return device;
				}
				continue;
			}
			if (strncmp(directoryPath, "/dev/graphics/virtio", 20) != 0
				&& strncmp(path.Leaf(), "virtio", 6) != 0)
				continue;
			int device = open(path.Path(), O_RDWR);
			if (device < 0)
				continue;
			virtio_gpu_preferred_size size;
			if (ioctl(device, VIRTIO_GPU_GET_PREFERRED_SIZE, &size,
					sizeof(size)) == 0)
				return device;
			close(device);
		}
		return -1;
	}

	void _Poll()
	{
		virtio_gpu_preferred_size size;
		if (ioctl(fDevice, VIRTIO_GPU_GET_PREFERRED_SIZE, &size,
				sizeof(size)) != 0)
			return;

		// Screen's UI scale choice rewrites it at any time
		fHostScale = _ReadHostScale();

		uint32 width = (uint32)(size.width * fHostScale + 0.5f);
		uint32 height = (uint32)(size.height * fHostScale + 0.5f);
		if (width > size.max_width || height > size.max_height) {
			// keep the aspect ratio inside what the frame buffer holds
			double scale = std::min((double)size.max_width / width,
				(double)size.max_height / height);
			width = (uint32)(width * scale);
			height = (uint32)(height * scale);
		}
		if (width < 640 || height < 400)
			return;

		if (width != fCandidateWidth || height != fCandidateHeight) {
			fCandidateWidth = width;
			fCandidateHeight = height;
			fStablePolls = 0;
			return;
		}
		if (++fStablePolls != 2)
			return;
			// acts once per new size, after a second without change

		BScreen screen;
		display_mode mode;
		if (screen.GetMode(&mode) != B_OK)
			return;
		if (mode.virtual_width == width && mode.virtual_height == height)
			return;

		mode.virtual_width = width;
		mode.virtual_height = height;
		mode.timing.h_display = width;
		mode.timing.v_display = height;
		mode.timing.h_sync_start = width + 48;
		mode.timing.h_sync_end = width + 80;
		mode.timing.h_total = width + 160;
		mode.timing.v_sync_start = height + 3;
		mode.timing.v_sync_end = height + 8;
		mode.timing.v_total = height + 40;
		mode.timing.pixel_clock = (uint32)((uint64)mode.timing.h_total
			* mode.timing.v_total * 60 / 1000);
		mode.h_display_start = 0;
		mode.v_display_start = 0;

		status_t status = screen.SetMode(&mode);
		syslog(LOG_INFO, "rretina_resize: %" B_PRIu32 "x%" B_PRIu32 ": %s\n",
			width, height, strerror(status));
	}

	int				fDevice;
	BMessageRunner*	fRunner;
	uint32			fCandidateWidth;
	uint32			fCandidateHeight;
	int32			fStablePolls;
	float			fHostScale;
};


int
main()
{
	ResizeApp app;
	app.Run();
	return 0;
}
