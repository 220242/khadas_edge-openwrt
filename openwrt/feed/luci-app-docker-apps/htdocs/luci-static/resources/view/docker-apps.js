'use strict';
'require view';
'require fs';
'require ui';
'require uci';
'require poll';

var HELPER = '/usr/libexec/docker-apps';
var CATALOG = '/usr/share/docker-apps/catalog.json';
var RESERVED_PORTS = { 22: 1, 53: 1, 80: 1, 443: 1, 9993: 1 };

var state = { installed: {}, tz: 'UTC' };

function exec(args) {
	return fs.exec(HELPER, args).then(function(res) {
		if (res.code != 0)
			throw new Error((res.stderr || res.stdout || _('Command failed')).trim());
		return res.stdout || '';
	});
}

function execJSON(args) {
	return exec(args).then(function(out) { return JSON.parse(out); });
}

function notify(err) {
	ui.addNotification(null, E('p', {}, err.message || String(err)), 'danger');
}

function webLink(port, proto) {
	var url = '%s://%s:%d/'.format(proto || 'http', window.location.hostname, port);
	return E('a', { 'href': url, 'target': '_blank', 'rel': 'noreferrer' }, url);
}

function suggestName(s) {
	var n = String(s).toLowerCase().replace(/^.*\//, '').replace(/[:@].*$/, '').replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '');
	return (n || 'app').substr(0, 32);
}

function validName(n) {
	return /^[a-z0-9][a-z0-9_-]{0,31}$/.test(n);
}

/* follow a background job, then call done(ok) */
function followJob(name, title, done) {
	var logEl = E('pre', { 'style': 'height:20em;overflow:auto;white-space:pre-wrap;font-size:85%' }, _('Starting…'));
	var status = E('p', { 'class': 'spinning' }, _('Working, pulling images can take several minutes…'));
	var close = E('button', { 'class': 'btn', 'disabled': true, 'click': function() { ui.hideModal(); window.location.reload(); } }, _('Close'));

	ui.showModal(title, [ status, logEl, E('div', { 'class': 'right' }, close) ]);

	var fn = function() {
		return L.resolveDefault(execJSON([ 'job', name ]), {}).then(function(job) {
			logEl.textContent = job.log || '';
			logEl.scrollTop = logEl.scrollHeight;
			if (job.state == 'done' || job.state == 'failed') {
				poll.remove(fn);
				close.disabled = false;
				status.className = '';
				status.innerHTML = '';
				status.appendChild(job.state == 'done'
					? E('strong', { 'style': 'color:green' }, _('Done.'))
					: E('strong', { 'style': 'color:red' }, _('Failed, see the log.')));
				if (done)
					done(job.state == 'done', status);
			}
		});
	};
	poll.add(fn, 2);
}

/* install dialog: name + editable compose */
function installDialog(title, name, compose, web, notes) {
	var nameEl = E('input', { 'class': 'cbi-input-text', 'value': name });
	var text = E('textarea', { 'class': 'cbi-input-textarea', 'rows': 16, 'style': 'width:100%;font-family:monospace;font-size:85%', 'wrap': 'off' }, compose);
	var install = E('button', { 'class': 'btn cbi-button cbi-button-positive' }, _('Install'));

	install.addEventListener('click', ui.createHandlerFn(null, function() {
		var n = nameEl.value.trim();
		if (!validName(n))
			return notify(new Error(_('Name: lowercase letters, digits, "-" and "_"')));
		if (state.installed[n])
			return notify(new Error(_('An app named "%s" is already installed').format(n)));

		return fs.write('/tmp/docker-apps/upload/%s.yml'.format(n), text.value).then(function() {
			return exec([ 'install', n ]);
		}).then(function() {
			followJob(n, _('Installing %s').format(n), function(ok, status) {
				if (ok && web)
					status.appendChild(E('p', {}, [ _('Open: '), webLink(web.port, web.proto) ]));
			});
		}).catch(notify);
	}));

	ui.showModal(title, [
		notes ? E('p', { 'class': 'alert-message notice' }, notes) : '',
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Name')),
			E('div', { 'class': 'cbi-value-field' }, nameEl)
		]),
		E('details', {}, [
			E('summary', {}, _('docker-compose.yml (data is stored in /opt/docker-apps/<name>/)')),
			text
		]),
		E('div', { 'class': 'right' }, [
			E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ', install
		])
	]);
}

/* compose for a single image */
function imageCompose(name, image, ports, volumes, env, host) {
	var q = function(s) { return JSON.stringify(String(s)); };
	var y = [ 'services:', '  %s:'.format(name), '    image: %s'.format(q(image)),
		'    restart: unless-stopped' ];

	if (host)
		y.push('    network_mode: host');
	else if (ports.length) {
		y.push('    ports:');
		ports.forEach(function(p) { y.push('      - %s'.format(q(p))); });
	}
	if (volumes.length) {
		y.push('    volumes:');
		volumes.forEach(function(v) { y.push('      - %s'.format(q(v))); });
	}
	if (env.length) {
		y.push('    environment:');
		env.forEach(function(e) { y.push('      - %s'.format(q(e))); });
	}
	return y.join('\n') + '\n';
}

/* image from Docker Hub / any registry: pull, detect ports and volumes, install */
function imageInstall(image) {
	image = image.trim();
	if (!/^[A-Za-z0-9][A-Za-z0-9._\/:@+-]*$/.test(image))
		return notify(new Error(_('Invalid image name')));
	if (!/:[^\/]+$/.test(image) && image.indexOf('@') < 0)
		image += ':latest';

	return exec([ 'pull', image ]).then(function() {
		followJob('pull', _('Downloading %s').format(image), function(ok) {
			if (!ok)
				return;
			return execJSON([ 'image-info', image ]).then(function(info) {
				var name = suggestName(image);
				var ports = (info.ports || []).map(function(p) {
					var port = +p.split('/')[0], proto = p.split('/')[1];
					var host = RESERVED_PORTS[port] ? 8000 + port : port;
					return '%d:%d%s'.format(host, port, proto == 'udp' ? '/udp' : '');
				});
				var volumes = (info.volumes || []).map(function(v) {
					return './data/%s:%s'.format(v.replace(/^\/+/, '').replace(/[^A-Za-z0-9._-]+/g, '_') || 'data', v);
				});
				var web = null;
				ports.forEach(function(p) {
					if (!web && !/\/udp$/.test(p))
						web = { port: +p.split(':')[0], proto: /443$/.test(p) ? 'https' : 'http' };
				});
				installDialog(_('Install %s').format(image), name,
					imageCompose(name, image, ports, volumes, [ 'TZ=' + state.tz ], false), web,
					_('Ports and volumes were detected from the image, check them in docker-compose.yml.'));
			}).catch(notify);
		});
	}).catch(notify);
}

function appAction(name, action) {
	if (action == 'delete' && !confirm(_('Delete %s with all its data and images?').format(name)))
		return;
	return exec([ 'action', name, action ]).then(function() {
		followJob(name, '%s: %s'.format(name, action));
	}).catch(notify);
}

function showLogs(name) {
	return exec([ 'logs', name ]).then(function(out) {
		ui.showModal(_('Logs: %s').format(name), [
			E('pre', { 'style': 'max-height:30em;overflow:auto;white-space:pre-wrap;font-size:80%' }, out || _('No logs')),
			E('div', { 'class': 'right' }, E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Close')))
		]);
	}).catch(notify);
}

function renderInstalled(list, catalog) {
	var byId = {};
	catalog.forEach(function(a) { byId[a.id] = a; });

	var rows = [ E('tr', { 'class': 'tr table-titles' }, [
		E('th', { 'class': 'th' }, _('App')),
		E('th', { 'class': 'th' }, _('Status')),
		E('th', { 'class': 'th' }, _('Web')),
		E('th', { 'class': 'th' }, _('Image')),
		E('th', { 'class': 'th cbi-section-actions' }, '')
	]) ];

	(list.apps || []).forEach(function(a) {
		var cat = byId[a.name], links = [];
		if (cat && cat.web)
			links.push(webLink(cat.web.port, cat.web.proto));
		else
			(a.ports || []).slice(0, 3).forEach(function(p) { links.push(webLink(p, p == 443 || p == 9443 || p == 8443 ? 'https' : 'http'), ' '); });

		var running = a.running > 0;
		var st = a.job == 'running' ? E('em', { 'class': 'spinning' }, _('working…'))
			: (running ? E('span', { 'style': 'color:green' }, _('running') + (a.containers > 1 ? ' %d/%d'.format(a.running, a.containers) : ''))
				: E('span', { 'style': 'color:#a00' }, _('stopped')));

		var btn = function(label, cls, act) {
			return E('button', { 'class': 'btn cbi-button ' + cls, 'click': ui.createHandlerFn(null, appAction, a.name, act) }, label);
		};

		rows.push(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, E('strong', {}, cat ? cat.name : a.name)),
			E('td', { 'class': 'td' }, st),
			E('td', { 'class': 'td' }, links.length ? links : '-'),
			E('td', { 'class': 'td', 'style': 'font-size:85%' }, (a.images || []).join(' ')),
			E('td', { 'class': 'td cbi-section-actions' }, [
				running ? btn(_('Stop'), 'cbi-button-neutral', 'stop') : btn(_('Start'), 'cbi-button-positive', 'start'), ' ',
				btn(_('Update'), 'cbi-button-action', 'update'), ' ',
				E('button', { 'class': 'btn cbi-button', 'click': ui.createHandlerFn(null, showLogs, a.name) }, _('Logs')), ' ',
				btn(_('Delete'), 'cbi-button-remove', 'delete')
			])
		]));
	});

	if (rows.length == 1)
		rows.push(E('tr', { 'class': 'tr placeholder' }, E('td', { 'class': 'td', 'colspan': 5 }, E('em', {}, _('No apps installed yet')))));

	return E('div', { 'class': 'cbi-section' }, [ E('h3', _('Installed apps')), E('table', { 'class': 'table' }, rows) ]);
}

function renderCatalog(catalog) {
	var cards = catalog.map(function(a) {
		var installed = !!state.installed[a.id];
		return E('div', { 'style': 'border:1px solid #ccc;border-radius:6px;padding:.7em;display:flex;flex-direction:column;justify-content:space-between' }, [
			E('div', {}, [
				E('strong', {}, a.name), ' ',
				E('small', { 'style': 'color:#888' }, a.category),
				E('p', { 'style': 'font-size:90%;margin:.4em 0' }, a.description)
			]),
			E('button', {
				'class': 'btn cbi-button ' + (installed ? '' : 'cbi-button-positive'),
				'disabled': installed ? true : null,
				'click': ui.createHandlerFn(null, function() {
					installDialog(_('Install %s').format(a.name), a.id,
						a.compose.replace(/\$\{TZ\}/g, state.tz), a.web, a.notes);
				})
			}, installed ? _('Installed') : _('Install'))
		]);
	});

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', _('App catalog')),
		E('p', {}, _('One click install, all images are available for arm64.')),
		E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fill,minmax(15em,1fr));gap:.7em' }, cards)
	]);
}

function renderHub() {
	var q = E('input', { 'class': 'cbi-input-text', 'placeholder': _('e.g. nginx, jellyfin, linuxserver/…') });
	var results = E('div', {});

	var search = function() {
		results.innerHTML = '';
		results.appendChild(E('p', { 'class': 'spinning' }, _('Searching…')));
		return execJSON([ 'search', q.value ]).then(function(res) {
			var rows = [ E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Image')), E('th', { 'class': 'th' }, _('Description')),
				E('th', { 'class': 'th' }, _('Stars')), E('th', { 'class': 'th' }, _('Downloads')),
				E('th', { 'class': 'th cbi-section-actions' }, '') ]) ];
			(res.results || []).forEach(function(r) {
				rows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, [ E('a', { 'href': 'https://hub.docker.com/' + (r.is_official ? '_/' : 'r/') + r.repo_name, 'target': '_blank', 'rel': 'noreferrer' }, r.repo_name),
						r.is_official ? E('small', { 'style': 'color:green' }, ' ' + _('official')) : '' ]),
					E('td', { 'class': 'td', 'style': 'font-size:85%' }, r.short_description || ''),
					E('td', { 'class': 'td' }, r.star_count),
					E('td', { 'class': 'td' }, '%1000.1m'.format(r.pull_count)),
					E('td', { 'class': 'td cbi-section-actions' }, E('button', {
						'class': 'btn cbi-button cbi-button-positive',
						'click': ui.createHandlerFn(null, imageInstall, r.repo_name)
					}, _('Install')))
				]));
			});
			results.innerHTML = '';
			results.appendChild(rows.length > 1 ? E('table', { 'class': 'table' }, rows) : E('em', {}, _('Nothing found')));
		}).catch(function(err) { results.innerHTML = ''; notify(err); });
	};
	q.addEventListener('keydown', function(ev) { if (ev.keyCode == 13) search(); });

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', _('Docker Hub')),
		E('div', {}, [ q, ' ', E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(null, search) }, _('Search')) ]),
		results
	]);
}

function renderCustom() {
	var image = E('input', { 'class': 'cbi-input-text', 'placeholder': 'ghcr.io/owner/app:tag, lscr.io/linuxserver/app, quay.io/…' });
	var url = E('input', { 'class': 'cbi-input-text', 'placeholder': 'https://raw.githubusercontent.com/…/docker-compose.yml' });
	var paste = E('textarea', { 'class': 'cbi-input-textarea', 'rows': 6, 'style': 'width:100%;font-family:monospace', 'placeholder': 'services:\n  myapp:\n    image: …' });

	var fromText = function(text, hint) {
		var m = /image:\s*["']?([^\s"']+)/.exec(text);
		installDialog(_('Install from docker-compose.yml'), suggestName(hint || (m ? m[1] : 'app')), text, null, null);
	};

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', _('Other sources')),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Image from any registry')),
			E('div', { 'class': 'cbi-value-field' }, [ image, ' ',
				E('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': ui.createHandlerFn(null, function() { return imageInstall(image.value); }) }, _('Install')) ])
		]),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('docker-compose.yml URL')),
			E('div', { 'class': 'cbi-value-field' }, [ url, ' ',
				E('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': ui.createHandlerFn(null, function() {
					return exec([ 'fetch', url.value.trim() ]).then(function(text) {
						fromText(text, url.value.split('/').slice(-2, -1)[0]);
					}).catch(notify);
				}) }, _('Load')) ])
		]),
		E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, _('Paste docker-compose.yml')),
			E('div', { 'class': 'cbi-value-field' }, [ paste,
				E('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': ui.createHandlerFn(null, function() { fromText(paste.value); }) }, _('Install')) ])
		])
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.read(CATALOG).then(JSON.parse), { apps: [] }),
			L.resolveDefault(execJSON([ 'list' ]), { docker: false, apps: [] }),
			uci.load('system')
		]);
	},

	render: function(data) {
		var catalog = (data[0] || {}).apps || [], list = data[1] || {};

		state.tz = uci.get('system', '@system[0]', 'zonename') || 'UTC';
		state.installed = {};
		(list.apps || []).forEach(function(a) { state.installed[a.name] = a; });

		var nodes = [
			E('h2', _('Docker Apps')),
			E('div', { 'class': 'cbi-map-descr' }, _('Install containers with one click from the catalog, Docker Hub or any registry. Advanced management: Services → Docker.'))
		];

		if (!list.docker)
			nodes.push(E('div', { 'class': 'alert-message warning' }, [
				_('Docker is not running.'), ' ',
				E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(null, function() {
					return fs.exec(HELPER, [ 'docker-start' ]).then(function() { window.setTimeout(function() { window.location.reload(); }, 5000); });
				}) }, _('Start Docker'))
			]));

		nodes.push(renderInstalled(list, catalog), renderCatalog(catalog), renderHub(), renderCustom());

		return E([], nodes);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
