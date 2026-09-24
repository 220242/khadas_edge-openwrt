'use strict';
'require view';
'require form';
'require fs';
'require rpc';
'require uci';
'require ui';

var callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: [ 'name' ],
	expect: { '': {} }
});

function running(services, name) {
	try {
		return services.kvm.instances[name].running === true;
	}
	catch (e) {
		return false;
	}
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callServiceList('kvm'), {}),
			L.resolveDefault(fs.stat('/dev/kvm'), null),
			uci.load('kvm')
		]);
	},

	render: function(data) {
		var services = data[0],
		    has_kvm = data[1] != null,
		    m, s, o;

		m = new form.Map('kvm', _('Virtual Machines'),
			_('QEMU/KVM virtual machines (arm64 guests with UEFI). ' +
			  'Enable a machine and press "Save & Apply" to start it, disable it to stop. ' +
			  'The VM screen is available with any VNC client on port 5900 + VNC display.'));

		if (!has_kvm)
			m.description += '<br /><strong>' +
				_('/dev/kvm not found: the kernel has no KVM support, virtual machines can not start.') +
				'</strong>';

		s = m.section(form.NamedSection, 'global', 'kvm', _('Settings'));

		o = s.option(form.Value, 'storage', _('Storage directory'),
			_('Default directory for VM disks and UEFI variables, use NVMe / USB / SD storage.'));
		o.placeholder = '/mnt/vm';

		s = m.section(form.GridSection, 'vm', _('Machines'));
		s.addremove = true;
		s.anonymous = false;
		s.nodescriptions = true;
		s.modaltitle = function(section_id) {
			return _('Virtual machine') + ' » ' + section_id;
		};

		o = s.option(form.DummyValue, '_status', _('Status'));
		o.modalonly = false;
		o.textvalue = function(section_id) {
			return running(services, section_id)
				? E('span', { 'style': 'color:green' }, [ _('running') ])
				: E('span', {}, [ _('stopped') ]);
		};

		o = s.option(form.Flag, 'enabled', _('Run'));
		o.editable = true;
		o.rmempty = false;

		o = s.option(form.ListValue, 'cpus', _('vCPUs'));
		[ '1', '2', '3', '4' ].forEach(function(n) { o.value(n); });
		o.default = '1';

		o = s.option(form.Value, 'memory', _('Memory (MB)'));
		o.datatype = 'and(uinteger,min(64))';
		o.placeholder = '512';

		o = s.option(form.Value, 'disk', _('Disk image'),
			_('Path to .qcow2 or raw disk image, created automatically if "Disk size" is set.'));
		o.placeholder = '/mnt/vm/<name>.qcow2';

		o = s.option(form.Value, 'disk_size', _('Disk size'),
			_('Size for a new disk image, e.g. 16G.'));
		o.modalonly = true;
		o.placeholder = '16G';
		o.validate = function(section_id, value) {
			return (value == '' || /^[0-9]+[KMGT]?$/.test(value)) ? true : _('Expecting size like 16G');
		};

		o = s.option(form.Value, 'cdrom', _('CD/DVD image'),
			_('ISO image to install from, boots before the disk. Clear it after installation.'));
		o.modalonly = true;
		o.placeholder = '/mnt/vm/debian-13-arm64-netinst.iso';

		o = s.option(form.Value, 'bridge', _('Network bridge'));
		o.placeholder = 'br-lan';
		o.default = 'br-lan';

		o = s.option(form.Value, 'mac', _('MAC address'),
			_('Generated from the VM name if empty.'));
		o.modalonly = true;
		o.datatype = 'macaddr';

		o = s.option(form.Value, 'vnc', _('VNC display'),
			_('VNC port 5900 + display, empty to disable the screen.'));
		o.datatype = 'range(0,99)';
		o.textvalue = function(section_id) {
			var v = uci.get('kvm', section_id, 'vnc');
			return (v != null && v !== '') ? '%s (%d)'.format(v, 5900 + +v) : '-';
		};

		o = s.option(form.Value, 'cpu_affinity', _('CPU affinity'),
			_('RK3399: cores 0-3 are Cortex-A53, 4-5 are Cortex-A72. KVM vCPUs must stay on one core type. Default: 1-2 vCPUs on 4-5, 3-4 vCPUs on 0-3.'));
		o.modalonly = true;
		o.value('4-5', _('4-5 (Cortex-A72)'));
		o.value('0-3', _('0-3 (Cortex-A53)'));

		o = s.option(form.Flag, 'respawn', _('Restart on exit'));
		o.modalonly = true;

		o = s.option(form.Value, 'extra', _('Extra QEMU arguments'));
		o.modalonly = true;

		return m.render();
	}
});
