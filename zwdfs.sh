#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 iggenio
#
# Developed with the assistance of Claude (Anthropic), an AI model.
# The code has been reviewed and tested by the author on a GT-AXE11000.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# ZW-DFS for Asuswrt-Merlin - version 1.0.3
# 5 GHz starts on the saved non-DFS channel (e.g. 48); after a background radar check (CAC)
# it moves to the chosen DFS channel (e.g. 64) without disconnecting clients (wl dfs_ap_move).
# If radar blocks the target, it tries the fallback DFS channels and retries the target later.
# Usage: zwdfs.sh install | startup | event <action> <service> | run [now] | check | status | version | uninstall

. /usr/sbin/helper.sh

VERSION=1.0.3
ADDIR=/jffs/addons/zwdfs
PAGE=$ADDIR/zwdfs.asp
SELF=$ADDIR/zwdfs.sh
LASTMOVE=$ADDIR/lastmove.txt
RADARLOG=$ADDIR/radar.log
ATTEMPT=$ADDIR/lastattempt
IF=eth7
TAG=zwdfs
STATUS=/www/user/zwdfs_status.js
SYSLOG=/opt/var/log/messages
[ -f "$SYSLOG" ] || SYSLOG=/tmp/syslog.log
LOCK=/tmp/zwdfs.lock
LEASES=/var/lib/misc/dnsmasq.leases
RETRY_AFTER=1800   # seconds: radar non-occupancy period before retrying the target channel
PHASE=/tmp/zwdfs.phase

log() { logger -t "$TAG" "$*"; }
get_set() { v=$(am_settings_get "$1"); [ -z "$v" ] && v="$2"; echo "$v"; }
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\t' ' '; }
chan() { wl -i "$1" chanspec 2>/dev/null | awk '{print $1}'; }
macs() { wl -i "$1" assoclist 2>/dev/null | awk '{print tolower($2)}'; }
count() { wl -i "$1" assoclist 2>/dev/null | wc -l; }
name_of() { n=$(awk -v m="$1" 'tolower($2)==m {print $4}' "$LEASES" 2>/dev/null | head -1); [ -z "$n" ] || [ "$n" = "*" ] && n="?"; echo "$n"; }
band_of() { for i in eth7 eth8 eth6; do macs $i | grep -qx "$1" && { echo $i; return; }; done; echo none; }
band_name() { case "$1" in eth6) echo "2.4 GHz";; eth7) echo "5 GHz";; eth8) echo "6 GHz";; *) echo "not connected";; esac; }
radar_count() { dmesg 2>/dev/null | grep -ci 'radar'; }
lm_get() { grep "^$1=" "$LASTMOVE" 2>/dev/null | head -1 | cut -d= -f2-; }

set_phase() { echo "$1" > "$PHASE"; write_status; }
# state of the background radar sub-radio (@1): IDLE, CAC, ...
bg_state() { wl -i $IF dfs_ap_move 2>/dev/null | sed -n 's/^@1: state: \([^,]*\),.*/\1/p' | head -1; }
# overall state of the DFS AP move ("IDLE" when nothing is in progress)
mv_state() { wl -i $IF dfs_ap_move 2>/dev/null | sed -n 's/^dfs AP move in \(.*\) state.*/\1/p' | head -1; }
# true while a background DFS check or move is in progress
dfs_busy() {
	m=$(mv_state); b=$(bg_state)
	[ -n "$m" ] && [ "$m" != "IDLE" ] && return 0
	case "$b" in ""|IDLE) return 1 ;; *) return 0 ;; esac
}

default_fallback() {
	p=${1%%/*}
	if [ "$p" -ge 52 ] 2>/dev/null && [ "$p" -le 64 ]; then echo "100/80"; else echo "64/80"; fi
}

write_status() {
	en=$(get_set zwdfs_enabled 1)
	tg=$(get_set zwdfs_target 64/80)
	fb=$(get_set zwdfs_fallback "$(default_fallback "$tg")")
	cur=$(chan $IF)
	base=$(nvram get wl1_chanspec)
	running=0; [ -d "$LOCK" ] && running=1
	if [ $running = 1 ] && [ -f "$PHASE" ]; then
		state=$(cat "$PHASE")
	elif [ $running = 1 ]; then
		state="Running"
	else
		case "$(bg_state)" in
			*CAC*|*vailability*) state="Scanning (background radar check)" ;;
			*) state="Idle" ;;
		esac
	fi
	rc=0; rl=""
	[ -f "$RADARLOG" ] && { rc=$(wc -l < "$RADARLOG"); rl=$(tail -1 "$RADARLOG"); }
	last=$(grep -a " $TAG: " "$SYSLOG" 2>/dev/null | tail -12 | tr '\n' '|')
	{
		echo "var zwdfs_status = {"
		echo "\"version\":\"$VERSION\",\"time\":\"$(date '+%Y-%m-%d %H:%M:%S')\","
		echo "\"enabled\":\"$en\",\"target\":\"$(esc "$tg")\",\"fallback\":\"$(esc "$fb")\",\"current\":\"$(esc "$cur")\",\"base\":\"$(esc "$base")\",\"running\":\"$running\","
		echo "\"state\":\"$(esc "$state")\","
		echo "\"c24\":\"$(count eth6)\",\"c5\":\"$(count eth7)\",\"c6\":\"$(count eth8)\","
		echo "\"lm_time\":\"$(esc "$(lm_get time)")\",\"lm_from\":\"$(esc "$(lm_get from)")\",\"lm_to\":\"$(esc "$(lm_get to)")\","
		echo "\"lm_before\":\"$(esc "$(lm_get before)")\",\"lm_moved\":\"$(esc "$(lm_get moved)")\",\"lm_result\":\"$(esc "$(lm_get result)")\",\"lm_clients\":\"$(esc "$(lm_get clients)")\","
		echo "\"radar_count\":\"$rc\",\"radar_last\":\"$(esc "$rl")\","
		echo "\"log\":\"$(esc "$last")\""
		echo "};"
	} > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"
}

# Try one DFS channel with background CAC. Returns 0 if the radio is on it at the end.
try_move() {
	c=$1
	r0=$(radar_count)
	# a previous background check may still be running: wait for it (max 10 min)
	n=0
	while dfs_busy && [ $n -lt 60 ]; do sleep 10; n=$((n+1)); done
	[ "$(chan $IF)" = "$c" ] && return 0
	if ! wl -i $IF dfs_ap_move "$c" >/dev/null 2>&1; then
		sleep 15
		if ! wl -i $IF dfs_ap_move "$c" >/dev/null 2>&1; then
			log "driver refused background DFS move to $c (state: move=$(mv_state) bg=$(bg_state))"; return 1
		fi
	fi
	log "background DFS check started on $c"
	echo "Scanning $c (background radar check)" > "$PHASE"
	i=0; prevsnap=""
	while [ $i -lt 72 ]; do   # up to 12 minutes (weather-radar channels need 10)
		sleep 10; i=$((i+1))
		if [ "$(chan $IF)" = "$c" ]; then
			log "background DFS check on $c completed, radio moved after about $((i*10)) s"
			return 0
		fi
		snap="move=$(mv_state) bg=$(bg_state)"
		[ "$snap" != "$prevsnap" ] && { log "DFS state on $c: $snap"; prevsnap=$snap; }
		case "$(bg_state)" in
			IDLE|"") echo "Moving to $c" > "$PHASE" ;;
			*) echo "Scanning $c (background radar check)" > "$PHASE" ;;
		esac
		write_status
		# finished without moving (give the driver 20 s to start)
		[ $i -ge 2 ] && ! dfs_busy && break
	done
	[ "$(chan $IF)" = "$c" ] && return 0
	if [ "$(radar_count)" -gt "$r0" ]; then
		echo "$(date '+%Y-%m-%d %H:%M:%S') radar on $c" >> "$RADARLOG"
		log "RADAR detected on $c - channel not available, trying the next one"
	else
		log "move to $c did not complete after $((i*10)) s, no radar reported (driver: $(wl -i $IF dfs_ap_move 2>/dev/null | tr '\n' ' ' | tr -s ' '))"
	fi
	return 1
}

do_run() {
	mkdir "$LOCK" 2>/dev/null || { log "already running"; return 0; }
	trap 'rm -f "$PHASE"; rmdir "$LOCK" 2>/dev/null' EXIT
	date +%s > "$ATTEMPT"
	if [ "$(get_set zwdfs_enabled 1)" != "1" ]; then
		log "automation disabled - no move"; write_status; return 0
	fi
	tg=$(get_set zwdfs_target 64/80)
	fb=$(get_set zwdfs_fallback "$(default_fallback "$tg")")
	[ "$fb" = "none" ] && fb=""
	if [ "$1" != "now" ]; then
		set_phase "Waiting for clients to settle"
		n=0
		while [ $n -lt 60 ]; do
			wl -i $IF bss 2>/dev/null | grep -q up && break
			sleep 5; n=$((n+1))
		done
		sleep 90   # let clients settle on the start channel
	fi
	from=$(chan $IF)
	if [ "$from" = "$tg" ]; then
		log "5 GHz already on target channel $tg"; write_status; return 0
	fi
	before_list=$(macs $IF)
	before=$(echo "$before_list" | grep -c .)
	to=""
	for c in $tg $fb; do
		[ "$c" = "$from" ] && { to=$c; break; }
		if try_move "$c"; then to=$c; break; fi
	done
	if [ -z "$to" ]; then
		result="FAILED: no DFS channel available, staying on $from"
		log "$result"
		{ echo "time=$(date '+%Y-%m-%d %H:%M:%S')"; echo "from=$from"; echo "to=$from"; echo "before=$before"; echo "moved=$before"; echo "result=$result"; echo "clients="; } > "$LASTMOVE"
		write_status; return 1
	fi
	[ "$to" != "$tg" ] && log "WARNING: target $tg unavailable, using fallback $to (target retried later)"
	set_phase "Checking clients"
	sleep 10
	after_list=$(macs $IF)
	missing=""
	for m in $before_list; do echo "$after_list" | grep -qx "$m" || missing="$missing $m"; done
	nmiss=$(echo $missing | wc -w)
	moved=$((before - nmiss))
	clients=""
	if [ $nmiss -gt 0 ]; then
		log "$nmiss of $before clients did not follow the move - checking"
		sleep 30
		recover=""
		for m in $missing; do
			b=$(band_of $m)
			if [ "$b" = "eth6" ]; then
				wl -i eth6 deauthenticate $m 2>/dev/null
				recover="$recover $m"
				log "client $m ($(name_of $m)) fell back to 2.4 GHz - sent back to 5 GHz"
			else
				clients="$clients $m ($(name_of $m)): $(band_name $b);"
				log "client $m ($(name_of $m)) after move: $(band_name $b)"
			fi
		done
		if [ -n "$recover" ]; then
			set_phase "Recovering clients to 5 GHz"
			sleep 30
			for m in $recover; do
				b=$(band_of $m)
				clients="$clients $m ($(name_of $m)): 2.4 GHz -> $(band_name $b);"
				log "client $m ($(name_of $m)) recovery result: $(band_name $b)"
			done
		fi
	fi
	if [ "$to" = "$tg" ]; then result="OK"; else result="FALLBACK (target unavailable)"; fi
	[ $nmiss -gt 0 ] && result="$result - $nmiss client(s) did not follow"
	{
		echo "time=$(date '+%Y-%m-%d %H:%M:%S')"; echo "from=$from"; echo "to=$to"
		echo "before=$before"; echo "moved=$moved"; echo "result=$result"; echo "clients=$clients"
	} > "$LASTMOVE"
	log "result: $from -> $to, clients moved $moved/$before, $result"
	rm -f "$PHASE"; rmdir "$LOCK" 2>/dev/null
	write_status
}

# Periodic check (cron, every minute): refresh status and retry the target after the radar non-occupancy period
do_check() {
	write_status
	[ "$(get_set zwdfs_enabled 1)" = "1" ] || return 0
	[ -d "$LOCK" ] && return 0
	tg=$(get_set zwdfs_target 64/80)
	[ "$(chan $IF)" = "$tg" ] && return 0
	wl -i $IF bss 2>/dev/null | grep -q up || return 0
	dfs_busy && return 0
	la=$(cat "$ATTEMPT" 2>/dev/null); [ -z "$la" ] && la=0
	wait=600   # 10 min after a failure without radar
	if [ -f "$RADARLOG" ]; then
		rt=$(date -r "$RADARLOG" +%s 2>/dev/null); [ -n "$rt" ] && [ "$rt" -ge "$la" ] && wait=$RETRY_AFTER
	fi
	[ $(( $(date +%s) - la )) -ge $wait ] || return 0
	log "5 GHz not on target $tg - retrying"
	"$SELF" run now >/dev/null 2>&1 &
}

# remove WebUI pages left by previous ZW-DFS versions (am_get_webui_page matches by content,
# so a new version would otherwise get a new userN.asp slot and the old page would stay)
remove_old_pages() {
	for f in /www/user/user*.asp; do
		[ -f "$f" ] || continue
		grep -q 'zwdfs_status.js' "$f" || continue
		cmp -s "$f" "$PAGE" && continue
		rm -f "$f" && log "removed old WebUI page $(basename "$f")"
	done
}

install_page() {
	remove_old_pages
	am_get_webui_page "$PAGE"
	if [ "$am_webui_page" = "none" ]; then log "no free WebUI page slot"; return 1; fi
	cp "$PAGE" "/www/user/$am_webui_page"
	if [ ! -f /tmp/menuTree.js ]; then
		cp /www/require/modules/menuTree.js /tmp/
		mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
	fi
	sed -i '/tabName: "ZW-DFS"/d' /tmp/menuTree.js
	anchor=Advanced_WAdvanced_Content.asp
	grep -q "url: \"$anchor\", tabName:" /tmp/menuTree.js || anchor=Tools_OtherSettings.asp
	sed -i "/url: \"$anchor\", tabName:/a {url: \"$am_webui_page\", tabName: \"ZW-DFS\"}," /tmp/menuTree.js
	umount /www/require/modules/menuTree.js 2>/dev/null
	mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
	[ -z "$(am_settings_get zwdfs_enabled)" ] && am_settings_set zwdfs_enabled 1
	[ -z "$(am_settings_get zwdfs_target)" ] && am_settings_set zwdfs_target 64/80
	[ -z "$(am_settings_get zwdfs_fallback)" ] && am_settings_set zwdfs_fallback "$(default_fallback "$(get_set zwdfs_target 64/80)")"
	cru d zwdfs_status 2>/dev/null
	cru d zwdfs_check 2>/dev/null
	cru a zwdfs_check "* * * * * $SELF check"
	log "ZW-DFS $VERSION: WebUI page installed as $am_webui_page (next to Wireless > Professional)"
	write_status
}

uninstall_page() {
	am_get_webui_page "$PAGE"
	[ "$am_webui_page" != "none" ] && rm -f "/www/user/$am_webui_page"
	if [ -f /tmp/menuTree.js ]; then
		sed -i '/tabName: "ZW-DFS"/d' /tmp/menuTree.js
		umount /www/require/modules/menuTree.js 2>/dev/null
		mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
	fi
	cru d zwdfs_check 2>/dev/null
	cru d zwdfs_status 2>/dev/null
	rm -f "$STATUS"
	sed -i '/zwdfs/d' /jffs/scripts/service-event /jffs/scripts/services-start 2>/dev/null
	log "uninstalled (files kept in $ADDIR: rm -r $ADDIR to delete them)"
}

case "$1" in
	install) install_page ;;
	startup) install_page; (sleep 30; "$SELF" run) >/dev/null 2>&1 & ;;
	event)
		case "$3" in
			wireless) [ "$2" = "restart" ] && { "$SELF" run >/dev/null 2>&1 & } ;;
			zwdfs) "$SELF" run now >/dev/null 2>&1 & ;;
			zwdfsstatus) write_status ;;
		esac ;;
	run) do_run "$2" ;;
	check) do_check ;;
	status) write_status ;;
	uninstall) uninstall_page ;;
	version) echo "ZW-DFS $VERSION" ;;
	*) echo "ZW-DFS $VERSION - usage: $0 install | startup | event <action> <service> | run [now] | check | status | version | uninstall" ;;
esac
