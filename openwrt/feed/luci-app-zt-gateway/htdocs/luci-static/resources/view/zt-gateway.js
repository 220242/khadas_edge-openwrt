'use strict';
'require view';
'require form';
'require fs';
'require ui';
'require uci';

var HELPER = '/usr/libexec/zt-gateway';

function getStatus() {
	return L.resolveDefault(fs.exec_direct(HELPER, [ 'status' ], 'json'), {});
}

function memberAction(action, id, extra) {
	var args = [ action, id ];
	if (extra != null)
		args.push(extra);

	return fs.exec_direct(HELPER, args, 'json').then(function(res) {
		if (res && res.error)
			ui.addNotification(null, E('p', _('ZeroTier: %s').format(res.error)), 'danger');
		window.location.reload();
	}).catch(function(err) {
		ui.addNotification(null, E('p', err.message), 'danger');
	});
}

function renderStatus(st) {
	var rows = [];
	var add = function(label, value) {
		rows.push(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td left', 'width': '33%' }, [ label ]),
			E('td', { 'class': 'td left' }, [ value ])
		]));
	};

	add(_('Service'), st.running
		? (st.online ? _('running, online') : _('running, connecting to ZeroTier roots…'))
		: _('not running'));
	add(_('Node ID'), st.node_id || '-');
	add(_('Network ID'), st.network_id
		? E('strong', { 'style': 'user-select:all' }, [ st.network_id ])
		: '-');
	if (st.network_status)
		add(_('Network status'), '%s%s'.format(st.network_status, st.network_name ? ' (' + st.network_name + ')' : ''));
	if (st.addresses && st.addresses.length)
		add(_('ZeroTier address'), st.addresses.join(', '));
	add(_('Interface'), st.interface || '-');
	add(_('Controller'), st.controller
		? _('available')
		: _('not available (firmware built without the ZeroTier network controller)'));

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', _('Status')),
		E('table', { 'class': 'table' }, rows)
	]);
}

function renderMembers(st) {
	if (st.mode != 'controller' || !st.members)
		return E([]);

	var rows = [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, _('Member')),
			E('th', { 'class': 'th' }, _('Name')),
			E('th', { 'class': 'th' }, _('Address')),
			E('th', { 'class': 'th' }, _('Online')),
			E('th', { 'class': 'th' }, _('Authorized')),
			E('th', { 'class': 'th cbi-section-actions' }, '')
		])
	];

	st.members.forEach(function(m) {
		var actions = [];

		if (!m.self) {
			actions.push(E('button', {
				'class': 'btn cbi-button ' + (m.authorized ? 'cbi-button-negative' : 'cbi-button-positive'),
				'click': ui.createHandlerFn(null, function() {
					return memberAction(m.authorized ? 'deauthorize' : 'authorize', m.id);
				})
			}, m.authorized ? _('Deauthorize') : _('Authorize')));

			actions.push(' ', E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(null, function() {
					var name = prompt(_('Name for member %s').format(m.id), m.name || '');
					if (name != null)
						return memberAction('rename', m.id, name);
				})
			}, _('Rename')));

			actions.push(' ', E('button', {
				'class': 'btn cbi-button cbi-button-remove',
				'click': ui.createHandlerFn(null, function() {
					if (confirm(_('Delete member %s?').format(m.id)))
						return memberAction('delete', m.id);
				})
			}, _('Delete')));
		}

		rows.push(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, [ m.id ]),
			E('td', { 'class': 'td' }, [ m.self ? _('this device (gateway)') : (m.name || '-') ]),
			E('td', { 'class': 'td' }, [ (m.addresses || []).join(', ') || '-' ]),
			E('td', { 'class': 'td' }, [ m.online ? _('yes') : _('no') ]),
			E('td', { 'class': 'td' }, [ m.authorized ? _('yes') : E('strong', {}, _('waiting')) ]),
			E('td', { 'class': 'td cbi-section-actions' }, actions)
		]));
	});

	if (st.members.length <= 1)
		rows.push(E('tr', { 'class': 'tr placeholder' }, [
			E('td', { 'class': 'td', 'colspan': 6 }, [
				_('No clients yet: join network %s from a ZeroTier client, it appears here for authorization.').format(st.network_id)
			])
		]));

	return E('div', { 'class': 'cbi-section' }, [
		E('h3', _('Members')),
		E('table', { 'class': 'table' }, rows)
	]);
}

return view.extend({
	load: function() {
		return Promise.all([ getStatus(), uci.load('ztgateway') ]);
	},

	render: function(data) {
		var st = data[0] || {},
		    m, s, o;

		m = new form.Map('ztgateway', _('ZeroTier Gateway'),
			_('Share the internet connection of this device with ZeroTier clients (exit node).') + '<br />' +
			_('Clients: install ZeroTier, join the network ID and enable "Allow Default Route Override" ' +
			  '(Windows / macOS: "Route all traffic through ZeroTier", Android / iOS: "Route via ZeroTier").'));

		s = m.section(form.NamedSection, 'main', 'gateway');
		s.tab('general', _('General'));
		s.tab('controller', _('Own controller'));

		o = s.taboption('general', form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;

		o = s.taboption('general', form.ListValue, 'mode', _('Network'));
		o.value('join', _('Join a network from my.zerotier.com (or another controller)'));
		o.value('controller', _('Own network controller on this device') +
			(st.running && !st.controller ? ' – ' + _('not available in this firmware') : ''));
		o.default = 'join';
		o.description = _('my.zerotier.com: create a network, add route 0.0.0.0/0 via the ZeroTier IP of this device ' +
			'(Managed Routes) and authorize this device. Own controller: no account needed, clients are authorized on this page.');

		o = s.taboption('general', form.Value, 'network_id', _('Network ID'));
		o.datatype = 'and(hexstring,rangelength(16,16))';
		o.placeholder = '1234567890abcdef';
		o.depends('mode', 'join');

		o = s.taboption('general', form.Flag, 'exit_node', _('Internet gateway (exit node)'),
			_('ZeroTier clients can access the internet through this device.'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('general', form.Flag, 'lan_access', _('LAN access'),
			_('ZeroTier clients can access the LAN, also needed when the internet uplink of this device is the LAN port.'));

		o = s.taboption('general', form.Flag, 'admin_access', _('Device access'),
			_('LuCI, SSH and DNS of this device are reachable from ZeroTier.'));
		o.default = '1';
		o.rmempty = false;

		o = s.taboption('controller', form.Value, 'name', _('Network name'));
		o.placeholder = 'khadas-edge';
		o.depends('mode', 'controller');

		o = s.taboption('controller', form.Value, 'subnet', _('Subnet'),
			_('Addresses for ZeroTier clients, the first address is this device.'));
		o.datatype = 'cidr4';
		o.placeholder = '10.147.20.0/24';
		o.depends('mode', 'controller');

		o = s.taboption('controller', form.Flag, 'private', _('Private network'),
			_('New clients must be authorized on this page. Without it anybody who knows the network ID gets internet access through this device.'));
		o.default = '1';
		o.rmempty = false;
		o.depends('mode', 'controller');

		o = s.taboption('controller', form.Flag, 'dns', _('Push DNS'),
			_('Clients with "Allow DNS" use this device as DNS server.'));
		o.default = '1';
		o.rmempty = false;
		o.depends('mode', 'controller');

		return m.render().then(function(mapEl) {
			return E([], [
				renderStatus(st),
				mapEl,
				renderMembers(st),
				E('div', { 'class': 'cbi-section' }, [
					E('p', { 'style': 'font-size:90%' }, [
						_('The own controller uses the ZeroTier controller code under the ZeroTier Source-Available License: non-commercial use only.')
					])
				])
			]);
		});
	}
});
