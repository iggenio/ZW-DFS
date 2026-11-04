<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<!--
  ZW-DFS 1.0.0 - WebUI page
  SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 iggenio
  Developed with the assistance of Claude (Anthropic), an AI model.
  Licensed under the GNU General Public License v3.0 or later.
  See the LICENSE file or <https://www.gnu.org/licenses/>.
-->
<head>
<meta http-equiv="X-UA-Compatible" content="IE=Edge"/>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta HTTP-EQUIV="Pragma" CONTENT="no-cache">
<meta HTTP-EQUIV="Expires" CONTENT="-1">
<link rel="shortcut icon" href="images/favicon.png">
<link rel="icon" href="images/favicon.png">
<title>ZW-DFS</title>
<link rel="stylesheet" type="text/css" href="index_style.css">
<link rel="stylesheet" type="text/css" href="form_style.css">
<script language="JavaScript" type="text/javascript" src="/state.js"></script>
<script language="JavaScript" type="text/javascript" src="/general.js"></script>
<script language="JavaScript" type="text/javascript" src="/popup.js"></script>
<script language="JavaScript" type="text/javascript" src="/help.js"></script>
<script language="JavaScript" type="text/javascript" src="/validator.js"></script>
<style>
.FormTable td span.zw-ok, span.zw-ok{color:#8BC34A !important;font-weight:bold;}
.FormTable td span.zw-warn, span.zw-warn{color:#FFC107 !important;font-weight:bold;}
.FormTable td span.zw-bad, span.zw-bad{color:#FF5252 !important;font-weight:bold;}
.FormTable td span.zw-off, span.zw-off{color:#9E9E9E !important;font-weight:bold;}
.FormTable td span.zw-small, span.zw-small{color:#CFD8DC !important;font-size:11px;}
.zw-log{font-family:monospace;font-size:11px;white-space:pre-wrap;background:#2F3A3E;padding:6px;max-height:240px;overflow:auto;}
</style>
<script>
var custom_settings = <% get_custom_settings(); %>;
var thisPage = location.pathname.split('/').pop();

function esc(s){ return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function el(id){ return document.getElementById(id); }

function renderStatus(){
	var s = window.zwdfs_status;
	if (!s) { el('zw_time').innerHTML = 'status not available yet'; return; }
	el('zw_time').innerHTML = esc(s.time);
	if (s.version) el('zw_version').innerHTML = 'v' + esc(s.version);

	el('zw_enabled_txt').innerHTML = (s.enabled == '1') ? '<span class="zw-ok">Enabled</span>' : '<span class="zw-off">Disabled</span>';

	var onTarget = (s.current == s.target);
	var cls, txt;
	if (onTarget) { cls = 'zw-ok'; txt = 'on target DFS channel'; }
	else if (s.running == '1') { cls = 'zw-warn'; txt = 'move in progress'; }
	else if (s.current == s.base) { cls = (s.enabled == '1') ? 'zw-warn' : 'zw-off'; txt = 'on start channel'; }
	else { cls = 'zw-warn'; txt = 'on fallback channel'; }
	el('zw_current').innerHTML = '<span class="' + cls + '">' + esc(s.current) + '</span> (' + txt + ')';
	el('zw_base').innerHTML = esc(s.base) + ' &rarr; ' + esc(s.target) + ' <span class="zw-small">(fallback: ' + esc(s.fallback) + ')</span>';

	var st = s.state || 'Idle';
	var scls = (st == 'Idle') ? 'zw-ok' : 'zw-warn';
	var mv = '<span class="' + scls + '">' + esc(st) + '</span>';
	if (s.lm_time) {
		var r = s.lm_result || '';
		var rcls = (r.indexOf('OK') == 0 && r.indexOf('did not follow') < 0) ? 'zw-ok' : (r.indexOf('FAILED') == 0 ? 'zw-bad' : 'zw-warn');
		mv += '<br><span class="zw-small">Last move: ' + esc(s.lm_time) + ' &middot; ' + esc(s.lm_from) + ' &rarr; ' + esc(s.lm_to) +
			' &middot; clients ' + esc(s.lm_moved) + '/' + esc(s.lm_before) + '</span> <span class="' + rcls + '">' + esc(r) + '</span>';
		if (s.lm_clients) mv += '<br><span class="zw-small">' + esc(s.lm_clients).split(';').join('<br>') + '</span>';
	}
	el('zw_move').innerHTML = mv;

	el('zw_radar').innerHTML = (s.radar_count == '0' || s.radar_count == '')
		? '<span class="zw-ok">none detected</span>'
		: '<span class="zw-bad">' + esc(s.radar_count) + ' event(s)</span> &ndash; last: ' + esc(s.radar_last);

	el('zw_clients').innerHTML = '2.4 GHz: <b>' + esc(s.c24) + '</b> &nbsp; 5 GHz: <b>' + esc(s.c5) + '</b> &nbsp; 6 GHz: <b>' + esc(s.c6) + '</b>';
	el('zw_log').innerHTML = esc(s.log).split('|').join('\n');
}

function loadStatus(){
	var old = el('zw_status_js');
	if (old) old.parentNode.removeChild(old);
	var sc = document.createElement('script');
	sc.id = 'zw_status_js';
	sc.src = '/user/zwdfs_status.js?t=' + new Date().getTime();
	sc.onload = renderStatus;
	sc.onerror = function(){ el('zw_time').innerHTML = 'status file not found'; };
	document.getElementsByTagName('head')[0].appendChild(sc);
}

function blockOf(c){ var p = parseInt(c, 10); if (p >= 52 && p <= 64) return 'A'; if (p >= 100 && p <= 112) return 'B'; return ''; }

function updateFallback(){
	var tg = el('zw_target').value, fb = el('zw_fallback');
	for (var i = 0; i < fb.options.length; i++) {
		var o = fb.options[i];
		o.disabled = (o.value != 'none' && blockOf(o.value) == blockOf(tg));
	}
	if (fb.selectedIndex >= 0 && fb.options[fb.selectedIndex].disabled) {
		fb.value = (blockOf(tg) == 'A') ? '100/80' : '64/80';
	}
}

function initial(){
	show_menu();
	document.form.current_page.value = thisPage;
	document.form.next_page.value = thisPage;
	el('zw_enabled').value = custom_settings.zwdfs_enabled || '1';
	el('zw_target').value = custom_settings.zwdfs_target || '64/80';
	el('zw_fallback').value = (custom_settings.zwdfs_fallback == null) ? '100/80' : custom_settings.zwdfs_fallback.split(' ')[0];
	el('zw_target').onchange = updateFallback;
	updateFallback();
	loadStatus();
	setInterval(loadStatus, 10000);
}

function formValues(){
	return { zwdfs_enabled: el('zw_enabled').value, zwdfs_target: el('zw_target').value, zwdfs_fallback: el('zw_fallback').value };
}

function isDirty(){
	var f = formValues();
	return f.zwdfs_enabled != (custom_settings.zwdfs_enabled || '1') ||
		f.zwdfs_target != (custom_settings.zwdfs_target || '64/80') ||
		f.zwdfs_fallback != (custom_settings.zwdfs_fallback || '100/80');
}

// settings = object to store (null = keep the saved ones), script = rc action
function send(settings, script){
	var cs = JSON.parse(JSON.stringify(custom_settings));
	if (settings) { for (var k in settings) cs[k] = settings[k]; }
	el('amng_custom').value = JSON.stringify(cs);
	document.form.action_script.value = script;
	showLoading(3);
	document.form.submit();
	if (settings) { for (var k in settings) custom_settings[k] = settings[k]; }
	setTimeout(loadStatus, 4000);
}

function doSave(){ send(formValues(), 'start_zwdfsstatus'); }

function doMove(){
	if (isDirty()) {
		if (!confirm('Settings have unsaved changes. Save them and move now?')) return;
		send(formValues(), 'restart_zwdfs');
	} else {
		send(null, 'restart_zwdfs');
	}
}

function doRefresh(){ send(null, 'start_zwdfsstatus'); }
</script>
</head>
<body onload="initial();" class="bg">
<div id="TopBanner"></div>
<div id="Loading" class="popup_bg"></div>
<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
<form method="post" name="form" action="start_apply.htm" target="hidden_frame">
<input type="hidden" name="current_page" value="">
<input type="hidden" name="next_page" value="">
<input type="hidden" name="group_id" value="">
<input type="hidden" name="modified" value="0">
<input type="hidden" name="action_mode" value="apply">
<input type="hidden" name="action_wait" value="3">
<input type="hidden" name="first_time" value="">
<input type="hidden" name="action_script" value="">
<input type="hidden" name="preferred_lang" id="preferred_lang" value="<% nvram_get("preferred_lang"); %>">
<input type="hidden" name="firmver" value="<% nvram_get("firmver"); %>">
<input type="hidden" name="amng_custom" id="amng_custom" value="">
<table class="content" align="center" cellpadding="0" cellspacing="0">
<tr>
<td width="17">&nbsp;</td>
<td valign="top" width="202">
<div id="mainMenu"></div>
<div id="subMenu"></div>
</td>
<td valign="top">
<div id="tabMenu" class="submenuBlock"></div>
<table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
<tr><td align="left" valign="top">
<table width="760px" border="0" cellpadding="5" cellspacing="0" class="FormTitle" id="FormTitle">
<tr><td bgcolor="#4D595D" valign="top">
<div>&nbsp;</div>
<div class="formfonttitle">Wireless - ZW-DFS (zero-wait DFS) <span id="zw_version" style="font-size:12px;font-weight:normal;"></span></div>
<div style="margin:10px 0 10px 5px;" class="splitLine"></div>
<div class="formfontdesc">The 5 GHz radio starts on the channel saved in Wireless &gt; General (non-DFS, no radar wait). After a background radar check it moves to the selected DFS channel without disconnecting clients. If radar blocks the target, the fallback channel is used and the target is retried after 30 minutes. Clients that fall back to 2.4 GHz during the move are sent back to 5 GHz.</div>

<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable">
<thead><tr><td colspan="2">Status <span style="float:right;font-weight:normal;">updated: <span id="zw_time">-</span></span></td></tr></thead>
<tr><th width="30%">Automation</th><td id="zw_enabled_txt">-</td></tr>
<tr><th>Current 5 GHz channel</th><td id="zw_current">-</td></tr>
<tr><th>Start channel &rarr; target</th><td id="zw_base">-</td></tr>
<tr><th>DFS move status</th><td id="zw_move">-</td></tr>
<tr><th>Radar events</th><td id="zw_radar">-</td></tr>
<tr><th>Clients per band</th><td id="zw_clients">-</td></tr>
</table>

<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable" style="margin-top:8px;">
<thead><tr><td colspan="2">Settings</td></tr></thead>
<tr><th width="30%">Automation</th><td>
<select id="zw_enabled" class="input_option"><option value="1">Enabled</option><option value="0">Disabled</option></select>
</td></tr>
<tr><th>Target DFS channel</th><td>
<select id="zw_target" class="input_option">
<option value="52/80">52 / 80 MHz</option><option value="56/80">56 / 80 MHz</option>
<option value="60/80">60 / 80 MHz</option><option value="64/80">64 / 80 MHz</option>
<option value="100/80">100 / 80 MHz</option><option value="104/80">104 / 80 MHz</option>
<option value="108/80">108 / 80 MHz</option><option value="112/80">112 / 80 MHz</option>
</select>
</td></tr>
<tr><th>Fallback DFS channel<br><span class="zw-small">used if radar blocks the target</span></th><td>
<select id="zw_fallback" class="input_option">
<option value="none">None</option>
<option value="52/80">52 / 80 MHz</option><option value="56/80">56 / 80 MHz</option>
<option value="60/80">60 / 80 MHz</option><option value="64/80">64 / 80 MHz</option>
<option value="100/80">100 / 80 MHz</option><option value="104/80">104 / 80 MHz</option>
<option value="108/80">108 / 80 MHz</option><option value="112/80">112 / 80 MHz</option>
</select>
<span class="zw-small">Channels in the same 80 MHz block as the target (52&ndash;64 or 100&ndash;112) share its radar check and cannot be selected.</span>
</td></tr>
</table>

<table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" bordercolor="#6b8fa3" class="FormTable" style="margin-top:8px;">
<thead><tr><td>Recent events</td></tr></thead>
<tr><td><div id="zw_log" class="zw-log">-</div></td></tr>
</table>

<div class="formfontdesc" style="margin-top:10px;text-align:right;"><span class="zw-small">ZW-DFS by iggenio &middot; developed with the assistance of Claude (Anthropic) &middot; GPL-3.0-or-later</span></div>
<div class="apply_gen">
<input type="button" class="button_gen" onclick="doSave();" value="Save" title="Save settings (no channel change)">
<input type="button" class="button_gen" onclick="doMove();" value="Move now" title="Start the background DFS check and move to the target channel">
<input type="button" class="button_gen" onclick="doRefresh();" value="Refresh" title="Regenerate and reload the status">
</div>
</td></tr>
</table>
</td></tr>
</table>
</td>
<td width="10" align="center" valign="top">&nbsp;</td>
</tr>
</table>
</form>
<div id="footer"></div>
</body>
</html>
