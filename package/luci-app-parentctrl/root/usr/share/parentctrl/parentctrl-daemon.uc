#!/usr/bin/ucode
'use strict';

import * as uloop from 'uloop';
import * as uci from 'uci';
import * as fs from 'fs';

uloop.init();

const STATE_FILE = '/tmp/parentctrl_state.json';
const STATS_FILE = '/tmp/parentctrl_stats.json';
const PERSIST_FILE = '/etc/parentctrl_history.json';

let cursor = uci.cursor();
let traffic_history = {};
let daily_state = {};
let stats_data = { daily: {} };

function read_cmd(cmd) {
    let p = fs.popen(cmd, 'r');
    if (!p) return null;
    let out = p.read('all');
    p.close();
    return out;
}

function get_current_date() {
    let d = localtime(time());
    return sprintf("%04d-%02d-%02d", d.year, d.mon, d.mday);
}

function load_all_state() {
    let f1 = fs.open(STATE_FILE, 'r');
    if (f1) {
        try { daily_state = json(f1.read('all')) || {}; } catch(e) {}
        f1.close();
    }
    let f2 = fs.open(STATS_FILE, 'r') || fs.open(PERSIST_FILE, 'r');
    if (f2) {
        try { stats_data = json(f2.read('all')) || { daily: {} }; } catch(e) {}
        f2.close();
    }
}

function save_stats(persist) {
    let f = fs.open(STATS_FILE, 'w');
    if (f) {
        f.write(sprintf("%J", stats_data));
        f.close();
    }
    if (persist) {
        let pf = fs.open(PERSIST_FILE, 'w');
        if (pf) {
            pf.write(sprintf("%J", stats_data));
            pf.close();
        }
    }
}

function save_state() {
    let f = fs.open(STATE_FILE, 'w');
    if (f) {
        f.write(sprintf("%J", daily_state));
        f.close();
    }
}

function nft_block_mac(mac, block) {
    if (block) {
        system(sprintf("nft add element inet parentctrl blocked_devices { %s } 2>/dev/null", mac));
    } else {
        system(sprintf("nft delete element inet parentctrl blocked_devices { %s } 2>/dev/null", mac));
    }
}

let sync_counter = 0;

function accounting_tick() {
    cursor.load('parentctrl');
    let config = cursor.get_all('parentctrl');
    if (!config || !config.settings || config.settings.enabled != '1') {
        timer.set(60000);
        return;
    }

    let threshold_bytes = (+(config.settings.activity_threshold_kb || 50)) * 1024;
    let today = get_current_date();

    if (!stats_data.daily[today]) {
        stats_data.daily[today] = {};
        let days = sort(keys(stats_data.daily));
        while (length(days) > 7) {
            delete stats_data.daily[shift(days)];
        }
    }

    for (let prof in daily_state) {
        if (daily_state[prof].date != today) {
            daily_state[prof] = { used_minutes: 0, date: today };
            for (let s in config) {
                let sec = config[s];
                if (sec['.type'] == 'device' && sec.profile == prof && sec.mac) {
                    nft_block_mac(sec.mac, false);
                }
            }
        }
    }

    let nft_raw = read_cmd("nft -j list set inet parentctrl accounting_macs");
    let nft_data = null;
    try { nft_data = json(nft_raw); } catch(e) {}

    let elements = [];
    if (nft_data && nft_data.nftables) {
        for (let obj in nft_data.nftables) {
            if (obj.set && obj.set.name == 'accounting_macs' && obj.set.elem) {
                elements = obj.set.elem;
                break;
            }
        }
    }

    let current_bytes = {};
    for (let el in elements) {
        if (type(el) == 'object' && el.elem) {
            let mac = tolower(el.elem.val);
            let b = +(el.elem.counter ? el.elem.counter.bytes : 0);
            current_bytes[mac] = b;
        }
    }

    let profile_activity = {};
    let profile_delta_bytes = {};

    for (let s in config) {
        let sec = config[s];
        if (sec['.type'] == 'device' && sec.mac && sec.profile) {
            let mac = tolower(sec.mac);
            let prof = sec.profile;
            let bytes_now = current_bytes[mac] || 0;
            let bytes_before = traffic_history[mac] || bytes_now;
            let delta = bytes_now - bytes_before;
            if (delta < 0) delta = bytes_now;

            traffic_history[mac] = bytes_now;

            if (!profile_delta_bytes[prof]) profile_delta_bytes[prof] = 0;
            profile_delta_bytes[prof] += delta;

            if (delta >= threshold_bytes) {
                profile_activity[prof] = true;
            }
        }
    }

    for (let s in config) {
        let sec = config[s];
        if (sec['.type'] == 'profile') {
            let prof_name = sec['.name'];
            let quota = +(sec.daily_quota_minutes || 0);

            if (!daily_state[prof_name])
                daily_state[prof_name] = { used_minutes: 0, date: today };

            if (!stats_data.daily[today][prof_name])
                stats_data.daily[today][prof_name] = { minutes: 0, megabytes: 0 };

            let delta_mb = (profile_delta_bytes[prof_name] || 0) / (1024 * 1024);
            stats_data.daily[today][prof_name].megabytes += delta_mb;

            if (profile_activity[prof_name]) {
                daily_state[prof_name].used_minutes++;
                stats_data.daily[today][prof_name].minutes++;
            }

            let used = daily_state[prof_name].used_minutes;
            if (quota > 0 && used >= quota) {
                for (let d in config) {
                    let dev = config[d];
                    if (dev['.type'] == 'device' && dev.profile == prof_name && dev.mac) {
                        nft_block_mac(tolower(dev.mac), true);
                    }
                }
            }
        }
    }

    save_state();
    sync_counter++;
    let should_persist = (sync_counter >= 360);
    if (should_persist) sync_counter = 0;
    save_stats(should_persist);

    timer.set(60000);
}

load_all_state();
let timer = uloop.timer(1000, accounting_tick);
uloop.run();
