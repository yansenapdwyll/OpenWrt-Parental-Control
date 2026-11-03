# 🛡️ luci-app-parentctrl

[![Build OpenWrt 25 APK](https://github.com/yansenapdwyll/OpenWrt-Parental-Control/actions/workflows/build-apk.yml/badge.svg)](https://github.com/yansenapdwyll/OpenWrt-Parental-Control/actions/workflows/build-apk.yml)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Target: OpenWrt 25](https://img.shields.io/badge/OpenWrt-25.x-brightgreen.svg)](https://openwrt.org)

A modern, robust, and lightweight **Parental Control** module engineered specifically for the **OpenWrt 25** ecosystem.

Traditional parental control suites are largely ineffective against modern smartphones and client OSes (Android, iOS, Windows, macOS). Kids routinely bypass network restrictions using **randomized Wi-Fi MAC addresses (Private MAC)**, encrypted DNS (**DNS-over-HTTPS / DoT / DoQ**), and built-in proxy tunnels (such as Apple iCloud Private Relay).

**`luci-app-parentctrl`** eliminates these loopholes directly at the Linux kernel level by combining the power of **Firewall4 (`nftables`)**, the **`ucode`** runtime, and dynamic **`dnsmasq`** tag filtering.

---

## ✨ Features

### 1. ⏱️ True Activity Screen-Time Quota
* **Traffic-Aware Accounting**: Does not deduct minutes for idle standby connections. Quotas are only consumed when actual activity occurs (streaming, gaming, social media). Low-volume background traffic (e.g., push pings) does not burn time.
* **Kernel-Level Dropping**: When a daily budget reaches 0, the device MAC addresses are immediately inserted into a kernel `nftables` set (`@blocked_devices`) with an immediate `reject with icmpx admin-prohibited`.
* **Automatic Midnight Reset**: Profile quotas automatically refresh at `00:00` daily without requiring router reboots or cron jobs.

### 2. 🛑 DNS Bypass Prevention (Anti-DoH / DoT / DoQ)
* **Port 53 Redirection**: Transparently redirects all outbound TCP/UDP port 53 traffic to the router's local DNS resolver.
* **Port 853 Blocking**: Drops DNS-over-TLS (DoT) and DNS-over-QUIC (DoQ) sessions.
* **Canary Domains for DoH**: Returns `NXDOMAIN` for `use-application-dns.net`, forcing Chromium and Firefox browsers to automatically turn off built-in encrypted DNS fallbacks.
* **Dynamic DoH Resolution Sets**: Collects IP addresses for public DoH endpoints dynamically via `dnsmasq`'s `nftset` directive and blocks outbound TCP port 443 connections to them.
* **Apple iCloud Private Relay Blocker**: Drops resolution of Apple mask domains (`mask.icloud.com` / `mask-h2.icloud.com`), preventing traffic cloaking.

### 3. 🚨 Quarantine for Unknown Devices (Anti-Random MAC)
* Changing MAC addresses via "Private Wi-Fi Address" on modern phones usually evades rule sets.
* Under `luci-app-parentctrl`, unrecognized MACs are isolated in **Quarantine**:
  * Unencrypted web requests (HTTP/80) are hijacked and redirected to an internal splash portal: *"New Device Detected – Parental Authorization Required"*.
  * All remaining WAN traffic (HTTPS/443, games, mobile apps) is rejected until a parent assigns the device to a profile in LuCI.

### 4. 🔍 Strict SafeSearch & YouTube Restrictions
* Enforces search filtering at the DNS resolution level using transparent CNAME rewrites:
  * Google $\to$ `forcesafesearch.google.com`
  * Bing $\to$ `strict.bing.com`
  * DuckDuckGo $\to$ `safe.duckduckgo.com`
* **YouTube Restricted Mode**: Enforces `restrict.youtube.com` globally across web and mobile applications.

### 5. 🛡️ Profile-Based DNS Filtering
Assign devices to child profiles with tailored DNS upstream resolvers using DHCP tagging:
* **Family / Strict**: Blocks malware, phishing, and adult content (Cloudflare 1.1.1.3 / AdGuard Family).
* **Safe / Moderate**: Protects against malicious domains and phishing without blocking general media.

### 6. 📊 Real-Time Analytics & SVG Visualizations
* Built-in, responsive client-side SVG bar charts rendering screen-time consumption over the **past 7 days**.
* Bandwidth usage aggregation (total MB/GB per profile).
* **Zero Flash Wear**: High-frequency telemetric states stay in volatile RAM (`tmpfs`). History is synced to flash storage (`/etc/parentctrl_history.json`) only every 6 hours or upon graceful system shutdown.

---

## 🏗️ Technical Architecture

Tailored specifically for **OpenWrt 25**:
* **Backend**: Written entirely in native `ucode` scripts using the `uloop` asynchronous event scheduler.
* **Firewall Engine**: Fully integrated with **Firewall4** and dedicated `nftables` tables (`table inet parentctrl`).
* **Frontend**: Pure LuCI JavaScript API (ES6+), rendered client-side without legacy Lua dependencies.
* **Packaging**: Built for the standard **APK** package format (`apk-tools`).

---

## 📦 Requirements

* **OpenWrt 25.x** (or compatible snapshot releases)
* `firewall4` + `nftables`
* `dnsmasq-full` (with `nftset` support)
* `ucode`, `ucode-mod-fs`, `ucode-mod-uci`, `ucode-mod-uloop`, `ucode-mod-socket`

---

## 🚀 Installation


1. Download the compiled `.apk` artifact from [Actions](../../actions) or [Releases](../../releases).
2. Transfer it to your router's `/tmp` directory.
3. Install via `apk`:
   ```sh
   apk add --allow-untrusted /tmp/luci-app-parentctrl-1.0.0-r1.apk
