'use strict';
'require view';
'require fs';
'require ui';
'require poll';

var HELPER = '/usr/libexec/khadas-fwupdate';

function helper(args) {
	return fs.exec(HELPER, args).then(function(res) {
		var out = (res.stdout || '').trim(), err = (res.stderr || '').trim();
		if (res.code != 0)
			throw new Error(err.replace(/^ERROR: /, '') || out || _('Command failed'));
		return out ? JSON.parse(out) : {};
	});
}

function date(iso) {
	if (!iso)
		return '-';
	var d = new Date(iso);
	return isNaN(d) ? iso : d.toLocaleString();
}

function row(label, value) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '33%' }, label),
		E('td', { 'class': 'td left' }, value)
	]);
}

function releaseLink(repo, tag) {
	if (!tag)
		return E('em', {}, _('own build, not a release'));
	return E('a', { 'href': 'https://github.com/%s/releases/tag/%s'.format(repo, tag), 'target': '_blank', 'rel': 'noreferrer' }, tag);
}

var STATE = {
	'update': [ 'green', _('An update is available.') ],
	'current': [ '', _('This is the latest release.') ],
	'older': [ '', _('The installed firmware is newer than the latest release.') ],
	'no-image': [ 'red', _('The latest release has no image for this device.') ]
};

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.exec_direct(HELPER, [ 'status' ], 'json'), {}),
			L.resolveDefault(fs.exec_direct(HELPER, [ 'job' ], 'json'), {})
		]);
	},

	/* latest release section, filled by check() */
	renderCheck: function(chk) {
		var box = this.checkBox, l = chk.latest || {}, st = STATE[chk.state] || [ '', '' ];

		box.innerHTML = '';
		box.appendChild(E('table', { 'class': 'table' }, [
			row(_('Latest release'), l.html_url
				? E('a', { 'href': l.html_url, 'target': '_blank', 'rel': 'noreferrer' }, l.tag + (l.name && l.name != l.tag ? ' – ' + l.name : ''))
				: (l.tag || '-')),
			row(_('Published'), date(l.published)),
			row(_('Image for this device'), l.image
				? '%s (%1024.1mB)'.format(l.image, l.size)
				: E('em', {}, _('none'))),
			row(_('Checked'), date(chk.checked))
		]));
		box.appendChild(E('p', {}, E('strong', { 'style': st[0] ? 'color:' + st[0] : '' }, st[1])));

		if (l.image)
			box.appendChild(E('button', {
				'class': 'btn cbi-button ' + (chk.state == 'update' ? 'cbi-button-positive' : 'cbi-button-neutral'),
				'click': ui.createHandlerFn(this, 'download')
			}, chk.state == 'update' ? _('Download and verify') : _('Download and verify anyway')));
	},

	check: function() {
		var box = this.checkBox;

		box.innerHTML = '';
		box.appendChild(E('p', { 'class': 'spinning' }, _('Checking the releases…')));
		return helper([ 'check' ]).then(L.bind(this.renderCheck, this)).catch(function(err) {
			box.innerHTML = '';
			box.appendChild(E('p', { 'style': 'color:red' }, err.message));
		});
	},

	download: function() {
		return helper([ 'download' ]).then(L.bind(function() {
			this.watchJob();
		}, this)).catch(function(err) {
			ui.addNotification(null, E('p', err.message), 'danger');
		});
	},

	/* download / verify progress, then the flash controls */
	renderJob: function(job) {
		var box = this.jobBox, pct = job.size ? Math.min(100, Math.floor(100 * job.bytes / job.size)) : 0;

		box.innerHTML = '';
		if (!job.state)
			return;

		box.appendChild(E('h3', _('Downloaded image')));
		if (job.state == 'running')
			box.appendChild(E('div', {}, [
				E('p', {}, _('Downloading: %1024.1mB of %1024.1mB').format(job.bytes || 0, job.size || 0)),
				E('div', { 'style': 'height:1em;border:1px solid #ccc;margin:.5em 0' },
					E('div', { 'style': 'width:%d%%;height:100%%;background:#5cb85c;transition:width .5s'.format(pct) }))
			]));
		box.appendChild(E('pre', { 'style': 'max-height:12em;overflow:auto;white-space:pre-wrap' }, job.log || ''));

		if (job.state == 'failed')
			box.appendChild(E('p', {}, E('strong', { 'style': 'color:red' }, _('Download or verification failed, see the log.'))));

		if (!job.ready)
			return;

		var keep = E('input', { 'type': 'checkbox', 'checked': true });
		box.appendChild(E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Keep settings')),
			E('div', { 'class': 'cbi-value-field' }, [ keep,
				E('div', { 'class': 'cbi-value-description' }, _('Unchecked: the device starts with factory defaults.')) ])
		]));
		box.appendChild(E('div', {}, [
			E('button', {
				'class': 'btn cbi-button cbi-button-negative',
				'click': ui.createHandlerFn(this, 'install', job.image, keep)
			}, _('Install and reboot')), ' ',
			E('button', {
				'class': 'btn cbi-button',
				'click': ui.createHandlerFn(this, function() {
					return helper([ 'clean' ]).then(L.bind(this.renderJob, this, {}));
				})
			}, _('Remove the download'))
		]));
	},

	watchJob: function() {
		var self = this;
		var fn = function() {
			return L.resolveDefault(fs.exec_direct(HELPER, [ 'job' ], 'json'), {}).then(function(job) {
				self.renderJob(job);
				if (job.state != 'running')
					poll.remove(fn);
			});
		};
		poll.add(fn, 1);
		return fn();
	},

	install: function(image, keep) {
		if (!confirm(_('Flash %s and reboot? Do not power off the device until it is back.').format(image)))
			return;

		return helper([ 'install', keep.checked ? '1' : '0' ]).then(function() {
			ui.showModal(_('Flashing…'), [
				E('p', { 'class': 'spinning' }, _('The system is flashing now. DO NOT POWER OFF THE DEVICE! Wait a few minutes before you reload this page.'))
			]);
			/* factory defaults: the address may change, as in LuCI's own flash page */
			var hosts = [ window.location.host ];
			if (!keep.checked)
				hosts.push('192.168.1.1', 'openwrt.lan');
			window.setTimeout(function() {
				ui.awaitReconnect.apply(ui, hosts);
			}, 15000);
		}).catch(function(err) {
			ui.addNotification(null, E('p', err.message), 'danger');
		});
	},

	render: function(data) {
		var st = data[0] || {}, job = data[1] || {};

		this.checkBox = E('div', {});
		this.jobBox = E('div', { 'class': 'cbi-section' });

		var nodes = [
			E('h2', _('Firmware Update')),
			E('div', { 'class': 'cbi-map-descr' },
				_('Updates from the GitHub releases of this firmware: the image of this device is downloaded, its SHA256 checked against the release and flashed with sysupgrade.')),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Installed firmware')),
				E('table', { 'class': 'table' }, [
					row(_('Image'), st.variant || E('em', {}, _('unknown'))),
					row(_('Release'), releaseLink(st.repo, st.tag)),
					row(_('Built'), date(st.build_date)),
					row(_('Releases'), st.repo
						? E('a', { 'href': 'https://github.com/%s/releases'.format(st.repo), 'target': '_blank', 'rel': 'noreferrer' }, 'github.com/' + st.repo)
						: '-')
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Latest release')),
				this.checkBox,
				E('p', {}, E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, 'check')
				}, _('Check again')))
			]),
			this.jobBox
		];

		if (st.variant)
			this.check();
		else
			this.checkBox.appendChild(E('p', { 'style': 'color:red' },
				_('This image does not know which release images fit it (no /etc/khadas-release): update it once by hand.')));

		if (job.state == 'running')
			this.watchJob();
		else
			this.renderJob(job);

		return E([], nodes);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
