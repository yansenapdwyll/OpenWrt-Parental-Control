'use strict';
'require view';
'require form';
'require fs';
'require rpc';
'require uci';

const callDHCPLeases = rpc.declare({
    object: 'luci-rpc',
    method: 'getDHCPLeases',
    expect: { leases: [] }
});

return view.extend({
    load: function() {
        return Promise.all([
            fs.read('/tmp/parentctrl_state.json').catch(() => '{}'),
            fs.read('/tmp/parentctrl_stats.json').catch(() => '{}'),
            callDHCPLeases(),
            uci.load('parentctrl')
        ]);
    },

    renderSVGChart: function(stats, profiles) {
        const days = Object.keys(stats.daily || {}).sort();
        if (days.length === 0) {
            return E('p', { 'class': 'alert-message' }, _('Brak danych historycznych do wyświetlenia wykresu.'));
        }

        const width = 650;
        const height = 180;
        const padding = 35;
        const barWidth = 24;

        let maxVal = 60;
        days.forEach(d => {
            profiles.forEach(p => {
                let m = (stats.daily[d][p['.name']] || {}).minutes || 0;
                if (m > maxVal) maxVal = m;
            });
        });
        maxVal = Math.ceil(maxVal / 60) * 60;

        const colors = ['#3b82f6', '#10b981', '#f59e0b', '#ec4899', '#8b5cf6'];
        let svgElements = [];

        for (let i = 0; i <= 3; i++) {
            let yVal = (maxVal / 3) * i;
            let yPos = height - padding - ((yVal / maxVal) * (height - 2 * padding));
            svgElements.push(E('line', {
                'x1': padding, 'y1': yPos, 'x2': width - 10, 'y2': yPos,
                'stroke': '#334155', 'stroke-dasharray': '3,3', 'stroke-width': '0.8'
            }));
            svgElements.push(E('text', {
                'x': 5, 'y': yPos + 4, 'fill': '#94a3b8', 'font-size': '10'
            }, `${Math.round(yVal)}m`));
        }

        const stepX = (width - 2 * padding) / days.length;

        days.forEach((day, dIdx) => {
            let startX = padding + (dIdx * stepX) + 10;
            let dateLabel = day.substring(5);
            svgElements.push(E('text', {
                'x': startX, 'y': height - 10, 'fill': '#94a3b8', 'font-size': '10'
            }, dateLabel));

            profiles.forEach((p, pIdx) => {
                let profName = p['.name'];
                let minutes = (stats.daily[day][profName] || {}).minutes || 0;
                let barH = (minutes / maxVal) * (height - 2 * padding);
                let xPos = startX + (pIdx * (barWidth / profiles.length));
                let yPos = height - padding - barH;

                svgElements.push(E('rect', {
                    'x': xPos, 'y': yPos,
                    'width': (barWidth / profiles.length) - 2,
                    'height': Math.max(1, barH),
                    'fill': colors[pIdx % colors.length],
                    'rx': '2'
                }, [
                    E('title', {}, `${p.label || profName} (${day}): ${minutes} min`)
                ]));
            });
        });

        let legendNodes = profiles.map((p, idx) => {
            return E('span', { 'style': 'margin-right: 15px; font-size: 12px;' }, [
                E('span', {
                    'style': `display:inline-block; width:10px; height:10px; background:${colors[idx % colors.length]}; border-radius:2px; margin-right:5px;`
                }),
                p.label || p['.name']
            ]);
        });

        return E('div', { 'style': 'background:#1e293b; padding:15px; border-radius:8px; margin-bottom:20px;' }, [
            E('div', { 'style': 'margin-bottom:10px;' }, legendNodes),
            E('svg', {
                'viewBox': `0 0 ${width} ${height}`,
                'style': 'width:100%; height:auto;'
            }, svgElements)
        ]);
    },

    render: function(data) {
        let state = {};
        let stats = { daily: {} };
        try { state = JSON.parse(data[0]) || {}; } catch(e) {}
        try { stats = JSON.parse(data[1]) || { daily: {} }; } catch(e) {}

        const leases = data[2] || [];
        const m = new form.Map('parentctrl', _('Kontrola Rodzicielska'),
            _('Zarządzanie czasem ekranowym, filtrowaniem treści oraz statystykami aktywności.'));

        const profiles = uci.sections('parentctrl', 'profile');

        const s_stats = m.section(form.NamedSection, 'settings', 'settings', _('Statystyki i Aktywność (Ostatnie 7 dni)'));
        s_stats.render = () => {
            const chartNode = this.renderSVGChart(stats, profiles);

            let transferRows = [];
            profiles.forEach(p => {
                let profName = p['.name'];
                let totalMB = 0;
                let totalMin = 0;

                Object.keys(stats.daily || {}).forEach(d => {
                    let entry = stats.daily[d][profName] || {};
                    totalMB += (entry.megabytes || 0);
                    totalMin += (entry.minutes || 0);
                });

                let formattedTraffic = totalMB > 1024 
                    ? (totalMB / 1024).toFixed(2) + ' GB' 
                    : totalMB.toFixed(1) + ' MB';

                transferRows.push(E('tr', { 'class': 'tr' }, [
                    E('td', { 'class': 'td' }, E('strong', {}, p.label || profName)),
                    E('td', { 'class': 'td' }, `${Math.floor(totalMin / 60)}h ${totalMin % 60}m`),
                    E('td', { 'class': 'td' }, formattedTraffic)
                ]));
            });

            const transferTable = E('table', { 'class': 'table' }, [
                E('tr', { 'class': 'tr table-titles' }, [
                    E('th', { 'class': 'th' }, _('Profil')),
                    E('th', { 'class': 'th' }, _('Łączny Czas (7 dni)')),
                    E('th', { 'class': 'th' }, _('Przesłane Dane (7 dni)'))
                ]),
                ...transferRows
            ]);

            return E('div', { 'class': 'cbi-section' }, [
                chartNode,
                E('h4', {}, _('Łączne zużycie danych per profil')),
                transferTable
            ]);
        };

        const s_status = m.section(form.NamedSection, 'settings', 'settings', _('Stan Bieżący (Dziś)'));
        s_status.render = function() {
            let table = E('table', { 'class': 'table' }, [
                E('tr', { 'class': 'tr table-titles' }, [
                    E('th', { 'class': 'th' }, _('Profil')),
                    E('th', { 'class': 'th' }, _('Wykorzystano')),
                    E('th', { 'class': 'th' }, _('Limit Dzienny')),
                    E('th', { 'class': 'th' }, _('Pasek Zużycia'))
                ])
            ]);

            profiles.forEach(p => {
                let profName = p['.name'];
                let used = (state[profName] && state[profName].used_minutes) ? state[profName].used_minutes : 0;
                let quota = parseInt(p.daily_quota_minutes || '0');
                let pct = quota > 0 ? Math.min(100, Math.round((used / quota) * 100)) : 0;

                let progressBar = E('div', {
                    'style': 'background:#334155; border-radius:6px; overflow:hidden; width:140px; height:16px; display:inline-block; vertical-align:middle; margin-right:8px;'
                }, [
                    E('div', {
                        'style': `background:${pct >= 100 ? '#ef4444' : '#3b82f6'}; width:${pct}%; height:100%; transition: width 0.3s;`
                    })
                ]);

                table.appendChild(E('tr', { 'class': 'tr' }, [
                    E('td', { 'class': 'td' }, E('strong', {}, p.label || profName)),
                    E('td', { 'class': 'td' }, `${used} min`),
                    E('td', { 'class': 'td' }, quota > 0 ? `${quota} min` : _('Brak limitu')),
                    E('td', { 'class': 'td' }, [progressBar, E('span', {}, `${pct}%`)])
                ]));
            });

            return E('div', { 'class': 'cbi-section' }, [table]);
        };

        const s_global = m.section(form.NamedSection, 'settings', 'settings', _('Ustawienia Główne'));
        let o = s_global.option(form.Flag, 'enabled', _('Włącz moduł'));
        o.rmempty = false;

        o = s_global.option(form.Flag, 'block_doh', _('Blokuj DNS-over-HTTPS (DoH) / DoT'));
        o.default = '1';

        o = s_global.option(form.Flag, 'block_unknown_devices', _('Kwarantanna nieznanych urządzeń (Anty-Random MAC)'));
        o.default = '1';

        o = s_global.option(form.Value, 'activity_threshold_kb', _('Czułość licznika czasu (KB/min)'));
        o.default = '50';
        o.datatype = 'uinteger';

        const s_prof = m.section(form.GridSection, 'profile', _('Profile Dzieci'));
        s_prof.addremove = true;
        s_prof.anonymous = false;

        o = s_prof.option(form.Value, 'label', _('Imię / Etykieta'));
        o.rmempty = false;

        o = s_prof.option(form.Value, 'daily_quota_minutes', _('Dzienny limit (minuty)'));
        o.datatype = 'uinteger';
        o.default = '120';

        o = s_prof.option(form.ListValue, 'dns_filter', _('Poziom Ochrony DNS'));
        o.value('family', 'Cloudflare Family (Malware + Dorosłe)');
        o.value('safe', 'Cloudflare Security (Malware)');
        o.value('adguard_family', 'AdGuard Family Protection');
        o.default = 'family';

        o = s_prof.option(form.Flag, 'force_safesearch', _('Wymuś SafeSearch & YouTube Restricted'));
        o.default = '1';

        const s_dev = m.section(form.TableSection, 'device', _('Urządzenia'));
        s_dev.addremove = true;
        s_dev.anonymous = true;

        o = s_dev.option(form.Value, 'mac', _('Adres MAC'));
        o.datatype = 'macaddr';
        leases.forEach(l => {
            if (l.macaddr) o.value(l.macaddr.toLowerCase(), `${l.macaddr} (${l.hostname || 'Host'})`);
        });

        o = s_dev.option(form.ListValue, 'profile', _('Przypisany Profil'));
        profiles.forEach(p => o.value(p['.name'], p.label || p['.name']));

        o = s_dev.option(form.Value, 'description', _('Nazwa Urządzenia'));

        return m.render();
    }
});
