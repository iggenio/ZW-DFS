# ZW-DFS

**Zero-wait DFS for Asuswrt-Merlin.** Keep your 5 GHz network on a clean DFS channel without losing 5 GHz for a minute every time the router reboots or the Wi-Fi restarts.

Version 1.0.3 · Author: iggenio · License: GPL-3.0-or-later · Tested on ASUS ROG Rapture GT-AXE11000 with Asuswrt-Merlin 3004.388.12_2

---

## The problem

DFS channels (52–64 and 100–144 in Europe) are often the cleanest 5 GHz channels, but before using one the router must listen for radar for about 60 seconds (Channel Availability Check, CAC). During that minute the 5 GHz network does not exist:

- after every reboot or Wi-Fi restart, dual-band clients connect to 2.4 GHz instead;
- once they are connected and active, Smart Connect band steering does not move them, so they can stay on 2.4 GHz for hours.

The non-DFS channels (36–48 in Europe) have no radar wait, but they are usually the most crowded.

## The solution

ZW-DFS uses the background radar check built into recent Broadcom Wi-Fi chips (`wl dfs_ap_move`):

1. The 5 GHz radio starts on a **non-DFS channel** (e.g. 48): clients can connect immediately.
2. After clients settle (90 seconds), ZW-DFS starts a **background radar check** on the target DFS channel (e.g. 64) while clients keep using 5 GHz.
3. When the check is complete, the radio **moves to the DFS channel** and announces the change to clients, which follow it without disconnecting.

## Features

- Automatic move after every boot and Wi-Fi restart.
- **Radar handling**: if radar blocks the target, a fallback DFS channel is used, the event is logged, and the target is retried after the 30-minute non-occupancy period.
- **Client tracking**: 5 GHz clients are counted before and after the move; clients that fall back to 2.4 GHz are sent back to 5 GHz and reported by MAC address and DHCP name.
- **WebUI page** under *Wireless > ZW-DFS*:
  - status: automation state, current channel, synthetic move state (Idle, Waiting for clients to settle, Scanning, Moving, Checking clients, Recovering clients), last move summary, radar events, clients per band;
  - settings: enable/disable, target DFS channel, fallback DFS channel;
  - buttons: Save, Move now, Refresh;
  - recent events from the system log.
- Periodic check every minute (cron): keeps the WebUI status fresh and retries the target channel when needed.
- No dependencies on other add-ons: works without amtm, Entware, scribe, Skynet or a USB drive.

## Requirements

| Requirement | Notes |
|---|---|
| Asuswrt-Merlin firmware | Uses the Merlin Addons API, `service-event` / `services-start` hooks and `cru`. Does **not** work on stock ASUS firmware. |
| JFFS custom scripts | *Administration > System > Enable JFFS custom scripts and configs* = Yes |
| Broadcom driver with `wl dfs_ap_move` | Tested on **GT-AXE11000** (5 GHz radio on `eth7`). Other models may not support it or may use another interface name. |
| SSH access | LAN access is enough. |
| Legal region | ZW-DFS only uses the DFS channels allowed by the router's region. |

### Check driver support first

On the router (SSH):

```sh
wl -i eth7 chanspec
wl -i eth7 dfs_ap_move
```

`dfs_ap_move` must answer with something like:

```
version=1, move status=-1
dfs AP move in IDLE state
```

If it returns `Unsupported` or an error, your router cannot run ZW-DFS. If `eth7` is not your 5 GHz radio, find the right interface with `wl -i ethX chanspec` and change `IF=eth7` at the top of `zwdfs.sh`.

## Installation

Replace `<router-user>` and `<router-ip>` with your router login name and LAN address.

**1. Set the start channel** in the router WebUI: *Wireless > General > 5 GHz*: Control Channel = **48**, Bandwidth = **80 MHz**, then Apply.

**2. Copy the files** from your PC:

```sh
ssh <router-user>@<router-ip> "mkdir -p /jffs/addons/zwdfs"
scp -O zwdfs.sh zwdfs.asp <router-user>@<router-ip>:/jffs/addons/zwdfs/
```

> `-O` is needed by recent OpenSSH versions (otherwise: `sftp-server: not found`). Remove it on older versions (`invalid option -- 'O'`). Files must keep Unix (LF) line endings.

**3. Install** on the router (SSH):

```sh
chmod +x /jffs/addons/zwdfs/zwdfs.sh
grep -q zwdfs /jffs/scripts/service-event || echo '/jffs/addons/zwdfs/zwdfs.sh event "$1" "$2" & # zwdfs' >> /jffs/scripts/service-event
grep -q zwdfs /jffs/scripts/services-start || echo '/jffs/addons/zwdfs/zwdfs.sh startup & # zwdfs' >> /jffs/scripts/services-start
chmod +x /jffs/scripts/service-event /jffs/scripts/services-start
/jffs/addons/zwdfs/zwdfs.sh install
```

> The event hook is `service-event` (singular); the startup hook is `services-start` (plural). If a file did not exist, add `#!/bin/sh` as its first line.

**4. Open the page**: reload the WebUI (Ctrl+F5), go to *Wireless > ZW-DFS*, check the settings and press **Save**.

**5. Test**: press **Move now** (or Apply in *Wireless > General*). Within 3–4 minutes the current channel turns green on the target, and the last move shows the same number of clients before and after.

See [INSTALL.txt](INSTALL.txt) for the full guide.

## Usage

| Command (router, SSH) | Description |
|---|---|
| `zwdfs.sh run now` | Move to the target channel now |
| `zwdfs.sh check` | Periodic check (run by cron every minute) |
| `zwdfs.sh status` | Regenerate the status shown in the WebUI |
| `zwdfs.sh version` | Show the installed version |
| `zwdfs.sh install` | (Re)install the WebUI page and cron job |
| `zwdfs.sh uninstall` | Remove the page, cron job and hooks |

Logs: `grep -a ' zwdfs: ' /opt/var/log/messages` (or `/tmp/syslog.log` without scribe).

Settings are stored in `/jffs/addons/custom_settings.txt` (`zwdfs_enabled`, `zwdfs_target`, `zwdfs_fallback`).

## Updating

Copy the new `zwdfs.sh` and `zwdfs.asp` as in step 2, then:

```sh
chmod +x /jffs/addons/zwdfs/zwdfs.sh
/jffs/addons/zwdfs/zwdfs.sh install
```

and reload the WebUI with Ctrl+F5.

## Uninstalling

```sh
/jffs/addons/zwdfs/zwdfs.sh uninstall
rm -r /jffs/addons/zwdfs
```

Then set the 5 GHz channel you want in *Wireless > General*.

## Choosing channels

- **Start channel**: a non-DFS channel (36–48 in Europe). It is used only for the first couple of minutes.
- **Target**: the cleanest DFS channel in your area (scan with a Wi-Fi analyzer, or check `obss` in `wl -i eth7 chanim_stats`).
- **Fallback**: a channel in a **different** 80 MHz block from the target (e.g. target 64, fallback 100). Channels in the same block share the same radar check, so the WebUI does not let you select them.
- Avoid **116–128** in Europe: they need a 10-minute weather-radar check.

## Known limitations

- Radar detection is inferred from the driver messages (`dmesg`). It has not yet been verified with a real radar event.
- A client that does not support channel switch announcements may disconnect briefly during the move; ZW-DFS sends it back to 5 GHz if it lands on 2.4 GHz (one attempt per move).
- A factory reset erases `/jffs`, so the add-on must be reinstalled. Firmware updates normally keep `/jffs`; check the page afterwards.

## Compliance

ZW-DFS does not bypass radar detection. It uses the driver's background Channel Availability Check, so the router never transmits on a DFS channel before the check is complete, and the router keeps monitoring for radar while in service. Keep the router set to its legal region.

## Changelog

See [CHANGELOG.txt](CHANGELOG.txt).

## License

ZW-DFS is free software, released under the **GNU General Public License v3.0 or later** (GPL-3.0-or-later). You can redistribute it and/or modify it under the terms of the GPL; see the [LICENSE](LICENSE) file for the full text.

## Author

**iggenio**

## AI assistance

ZW-DFS was developed by iggenio with the assistance of **Claude** (Anthropic), an AI model, which contributed to the analysis, the code and the documentation. The author defined the requirements, reviewed the code and tested it on an ASUS GT-AXE11000. As with any software, review it before installing it on your own router.

## Disclaimer

Use at your own risk. ZW-DFS changes Wi-Fi channels on your router using undocumented driver commands; test it on your own model before relying on it.
