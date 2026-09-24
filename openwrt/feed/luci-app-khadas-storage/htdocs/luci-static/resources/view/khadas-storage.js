'use strict';
'require view';
'require fs';
'require ui';
'require rpc';
'require poll';

var HELPER = '/usr/libexec/khadas-storage';

var callReboot = rpc.declare({
	object: 'system',
	method: 'reboot',
	expect: { result: 0 }
});

var TRANSPORT = {
	usb: _('USB'),
	nvme: _('NVMe'),
	emmc: _('eMMC'),
	sd: _('SD card'),
	sata: _('SATA')
};

function helper(args) {
	return fs.exec(HELPER, args).then(function(res) {
		var out = (res.stdout || '') + (res.stderr || '');
		if (res.code != 0)
			throw new Error(out.trim() || _('Command failed'));
		return out;
	});
}

function getStatus() {
	return L.resolveDefault(fs.exec_direct(HELPER, [ 'status' ], 'json'), {});
}

function reboot() {
	return callReboot().then(function() {
		ui.showModal(_('Rebooting…'), [
			E('p', { 'class': 'spinning' }, _('Waiting for the device…'))
		]);
		window.setTimeout(function() { ui.awaitReconnect(); }, 15000);
	});
}

function rebootButton() {
	return E('button', {
		'class': 'btn cbi-button cbi-button-negative',
		'click': ui.createHandlerFn(null, reboot)
	}, _('Reboot now'));
}

function diskLabel(d) {
	var name = [ d.vendor, d.model ].filter(function(s) { return s; }).join(' ');
	return '%s %s %s%s'.format(TRANSPORT[d.transport] || d.transport, '/dev/' + d.name,
		'%1024.1mB'.format(d.size), name ? ' – ' + name : '');
}

function showJob() {
	var logEl = E('pre', { 'style': 'max-height:20em;overflow:auto;white-space:pre-wrap' }, ''),
	    bar = E('div', { 'style': 'width:0%;height:100%;background:#5cb85c;transition:width .5s' }),
	    stateEl = E('p', {}, _('Installing…')),
	    closeBtn = E('button', { 'class': 'btn', 'disabled': true, 'click': ui.hideModal }, _('Close'));

	ui.showModal(_('Install OpenWrt'), [
		stateEl,
		E('div', { 'style': 'height:1em;border:1px solid #ccc;margin:.5em 0' }, bar),
		logEl,
		E('div', { 'class': 'right' }, [ closeBtn, ' ', rebootButton() ])
	]);

	var fn = function() {
		return L.resolveDefault(fs.exec_direct(HELPER, [ 'job' ], 'json'), {}).then(function(job) {
			var log = job.log || '', pct = 0;
			(log.match(/PROGRESS (\d+)/g) || []).forEach(function(m) { pct = +m.split(' ')[1]; });
			bar.style.width = pct + '%';
			logEl.textContent = log.replace(/^PROGRESS \d+\n?/mg, '');
			if (job.state == 'done' || job.state == 'failed') {
				poll.remove(fn);
				closeBtn.disabled = false;
				stateEl.innerHTML = '';
				stateEl.appendChild(job.state == 'done'
					? E('strong', { 'style': 'color:green' }, _('Done. Reboot to start OpenWrt from the new disk.'))
					: E('strong', { 'style': 'color:red' }, _('Installation failed, see the log.')));
			}
		});
	};
	poll.add(fn, 2);
}

function installDialog(disk) {
	var src = E('select', { 'class': 'cbi-input-select' }, [
		E('option', { 'value': 'system' }, _('Copy of this system')),
		E('option', { 'value': 'upload' }, _('Upload image (openwrt-…-khadas_edge…-sysupgrade.img.gz)'))
	]);
	var keep = E('input', { 'type': 'checkbox', 'checked': true });
	var ext = E('input', { 'type': 'checkbox', 'checked': (disk.transport == 'usb' || disk.transport == 'nvme') ? true : null });
	var confirm = E('input', { 'type': 'checkbox' });
	var install = E('button', { 'class': 'btn cbi-button cbi-button-positive', 'disabled': true }, _('Install'));

	confirm.addEventListener('change', function() { install.disabled = !confirm.checked; });

	install.addEventListener('click', ui.createHandlerFn(null, function() {
		var chain = Promise.resolve('system');

		if (src.value == 'upload')
			chain = ui.uploadFile('/tmp/khadas-install/image.img.gz').then(function() {
				return '/tmp/khadas-install/image.img.gz';
			});

		return chain.then(function(source) {
			return helper([ 'install', disk.name, source, keep.checked ? '1' : '0', ext.checked ? '1' : '0' ]);
		}).then(function() {
			showJob();
		}).catch(function(err) {
			ui.addNotification(null, E('p', err.message), 'danger');
			ui.hideModal();
		});
	}));

	var row = function(label, widget, descr) {
		return E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, label),
			E('div', { 'class': 'cbi-value-field' }, [ widget, descr ? E('div', { 'class': 'cbi-value-description' }, descr) : '' ])
		]);
	};

	ui.showModal(_('Install OpenWrt to %s').format(diskLabel(disk)), [
		row(_('Source'), src, _('Copy: the running firmware, installed packages that are part of the image are kept.')),
		row(_('Keep settings'), keep, _('Current configuration is restored on the first boot from the new disk.')),
		row(_('Boot from this disk'), ext, _('eMMC / SD card start OpenWrt from this NVMe / USB disk when it is connected (the eMMC / SD card is still needed for the boot loader).')),
		E('p', { 'style': 'color:red' }, [ confirm, ' ', _('All data on /dev/%s will be erased').format(disk.name) ]),
		E('div', { 'class': 'right' }, [
			E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ', install
		])
	]);
}

function expand(st) {
	if (!confirm(_('Grow the root partition to the whole disk? The filesystem is resized on the next reboot.')))
		return;

	return helper([ 'expand' ]).then(function(out) {
		ui.showModal(_('Expand root filesystem'), [
			E('pre', {}, out),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': function() { ui.hideModal(); window.location.reload(); } }, _('Later')), ' ',
				rebootButton()
			])
		]);
	}).catch(function(err) {
		ui.addNotification(null, E('p', err.message), 'danger');
	});
}

function bootext(action) {
	return helper([ 'bootext', action ]).then(function(out) {
		ui.addNotification(null, E('pre', {}, out), 'info');
		window.setTimeout(function() { window.location.reload(); }, 1500);
	}).catch(function(err) {
		ui.addNotification(null, E('p', err.message), 'danger');
	});
}

return view.extend({
	load: function() {
		return getStatus();
	},

	render: function(st) {
		var root = st.root || {},
		    disks = (st.disks || []),
		    nodes = [];

		nodes.push(E('h2', _('Storage & Install')));
		nodes.push(E('div', { 'class': 'cbi-map-descr' },
			_('Install OpenWrt to a USB SSD, NVMe, eMMC or SD card and grow the root filesystem to the whole disk.')));

		/* root filesystem */
		var used = root.overlay_size ? Math.round(100 * root.overlay_used / root.overlay_size) : 0;
		nodes.push(E('div', { 'class': 'cbi-section' }, [
			E('h3', _('Root filesystem')),
			E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left', 'width': '33%' }, _('Boot disk')),
					E('td', { 'class': 'td left' }, st.boot_disk ? '/dev/' + st.boot_disk : _('unknown')) ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Root partition')),
					E('td', { 'class': 'td left' }, root.partition
						? '/dev/%s: %1024.1mB of %1024.1mB disk'.format(root.partition, root.partition_size, root.disk_size) : '-') ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Writable space (overlay)')),
					E('td', { 'class': 'td left' }, root.overlay_size
						? '%1024.1mB used of %1024.1mB (%d%%, %s)'.format(root.overlay_used, root.overlay_size, used, root.overlay_fs) : '-') ]),
				E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, _('Unallocated space')),
					E('td', { 'class': 'td left' }, '%1024.1mB'.format(root.unallocated || 0)) ])
			]),
			root.expand_pending
				? E('p', {}, [ E('strong', {}, _('Expansion pending: reboot to grow the filesystem.')), ' ', rebootButton() ])
				: E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'disabled': root.expandable ? null : true,
					'click': ui.createHandlerFn(null, expand, st)
				}, root.expandable ? _('Expand root to the whole disk') : _('Root already uses the whole disk'))
		]));

		/* install */
		var rows = [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Disk')),
				E('th', { 'class': 'th' }, _('Type')),
				E('th', { 'class': 'th' }, _('Model')),
				E('th', { 'class': 'th' }, _('Size')),
				E('th', { 'class': 'th cbi-section-actions' }, '')
			])
		];
		disks.forEach(function(d) {
			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, '/dev/' + d.name),
				E('td', { 'class': 'td' }, TRANSPORT[d.transport] || d.transport),
				E('td', { 'class': 'td' }, [ d.vendor, d.model ].join(' ').trim() || '-'),
				E('td', { 'class': 'td' }, '%1024.1mB'.format(d.size)),
				E('td', { 'class': 'td cbi-section-actions' }, d.boot
					? E('em', {}, _('running system'))
					: (d.in_use
						? E('em', {}, _('in use (mounted)'))
						: E('button', {
							'class': 'btn cbi-button cbi-button-apply',
							'click': ui.createHandlerFn(null, installDialog, d)
						}, _('Install OpenWrt…'))))
			]));
		});
		nodes.push(E('div', { 'class': 'cbi-section' }, [
			E('h3', _('Install OpenWrt to disk')),
			E('table', { 'class': 'table' }, rows)
		]));

		/* boot from external disk */
		var bext = st.bootext || [];
		var enabled = bext.some(function(b) { return b.enabled; });
		nodes.push(E('div', { 'class': 'cbi-section' }, [
			E('h3', _('Boot from NVMe / USB disk')),
			E('p', {}, _('The RK3399 boot ROM starts only from SPI flash, eMMC or SD card. With this option the boot loader on the eMMC / SD card starts OpenWrt from an NVMe or USB disk when one is connected, otherwise OpenWrt on the eMMC / SD card.')),
			bext.length
				? E('p', {}, [
					_('eMMC / SD card: %s').format(bext.map(function(b) {
						return '/dev/%s (%s)'.format(b.disk, b.enabled ? _('boot from NVMe / USB') : _('boot from itself'));
					}).join(', ')), ' ',
					E('button', {
						'class': 'btn cbi-button ' + (enabled ? 'cbi-button-negative' : 'cbi-button-positive'),
						'click': ui.createHandlerFn(null, bootext, enabled ? 'disable' : 'enable')
					}, enabled ? _('Disable') : _('Enable'))
				])
				: E('em', {}, _('No OpenWrt eMMC / SD card found (or it is the running system).'))
		]));

		return E([], nodes);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
