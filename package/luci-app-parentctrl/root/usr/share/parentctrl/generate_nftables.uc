#!/usr/bin/ucode
'use strict';

import * as uci from 'uci';
import * as fs from 'fs';

let cursor = uci.cursor();
let config = cursor.get_all('parentctrl');

if (!config || !config.settings || config.settings.enabled != '1') {
    fs.unlink('/var/run/parentctrl.nft');
    exit(0);
}

let notify_port = config.settings.notify_http_port || '8088';

let doh_hardcoded_ips = [
    "1.1.1.1", "1.0.0.1",
    "8.8.8.8", "8.8.4.4",
    "9.9.9.9", "149.112.112.112",
    "94.140.14.14", "94.140.15.15"
];

let known_macs = [];
for (let s in config) {
    let sec = config[s];
    if (sec['.type'] == 'device' && sec.mac) {
        push(known_macs, tolower(sec.mac));
    }
}

let out = [];
push(out, "#!/usr/sbin/nft -f\n");
push(out, "table inet parentctrl {");

push(out, "    set known_macs {");
push(out, "        type ether_addr");
if (length(known_macs) > 0) {
    push(out, "        elements = { " + join(", ", known_macs) + " }");
}
push(out, "    }");

push(out, "    set accounting_macs {");
push(out, "        type ether_addr; flags dynamic;");
if (length(known_macs) > 0) {
    push(out, "        elements = { " + join(", ", known_macs) + " }");
}
push(out, "    }");

push(out, "    set doh_static {");
push(out, "        type ipv4_addr; flags interval;");
push(out, "        elements = { " + join(", ", doh_hardcoded_ips) + " }");
push(out, "    }");

push(out, "    set doh_dynamic {");
push(out, "        type ipv4_addr; flags timeout;");
push(out, "    }");

push(out, "    set blocked_devices {");
push(out, "        type ether_addr");
push(out, "    }\n");

push(out, "    chain dstnat_rules {");
push(out, "        type nat hook prerouting priority dstnat - 5; policy accept;");
push(out, "        meta l4proto { tcp, udp } th dport 53 redirect to :53");
if (config.settings.block_unknown_devices == '1' && config.settings.quarantine_notify == '1') {
    push(out, sprintf("        ether saddr != @known_macs tcp dport 80 redirect to :%s", notify_port));
}
push(out, "    }\n");

push(out, "    chain forward_filter {");
push(out, "        type filter hook forward priority filter - 5; policy accept;");
push(out, "        ether saddr @blocked_devices reject with icmpx type admin-prohibited");
push(out, "        ether saddr @accounting_macs counter");

if (config.settings.block_doh == '1') {
    push(out, "        tcp dport 853 reject");
    push(out, "        udp dport 853 reject");
    push(out, "        tcp dport 443 ip daddr @doh_static reject");
    push(out, "        tcp dport 443 ip daddr @doh_dynamic reject");
}

if (config.settings.block_unknown_devices == '1') {
    push(out, "        ether saddr != @known_macs counter reject with icmpx type admin-prohibited");
}

push(out, "    }");
push(out, "}\n");

let fd = fs.open('/var/run/parentctrl.nft', 'w');
if (fd) {
    fd.write(join("\n", out));
    fd.close();
}
