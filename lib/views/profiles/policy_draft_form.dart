import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/policy_draft.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

enum PolicyDraftFormKind {
  domain,
  ip,
  domainDefault,
  ipDefault,
  dns,
  bootstrap,
  proxy,
  group,
  listeners,
}

typedef PolicyDraftFormResult = ({Map<String, dynamic> value, String label});

class PolicyDraftForm extends StatefulWidget {
  final PolicyDraftFormKind kind;
  final String title;
  final PolicyDraftDocument document;
  final Map<String, dynamic> initial;
  final String? resourceId;

  const PolicyDraftForm({
    super.key,
    required this.kind,
    required this.title,
    required this.document,
    required this.initial,
    this.resourceId,
  });

  @override
  State<PolicyDraftForm> createState() => _PolicyDraftFormState();
}

class _PolicyDraftFormState extends State<PolicyDraftForm> {
  late final Map<String, dynamic> _value;
  final _controllers = <String, TextEditingController>{};
  late List<String> _members;
  late bool _auth;
  bool _showSecrets = false;

  @override
  void initState() {
    super.initState();
    _value = jsonDecode(jsonEncode(widget.initial));
    _members = List<String>.from(_value['members'] ?? []);
    _auth = _value.containsKey('username') || _value.containsKey('password');
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _text(String field, String label, {bool secret = false}) {
    final controller = _controllers.putIfAbsent(
      field,
      () => TextEditingController(
        text: field == '_label'
            ? widget.document.label(widget.resourceId!)
            : '${_value[field] ?? ''}',
      ),
    );
    final port = int.tryParse(controller.text);
    final invalid =
        field != '_label' &&
        (controller.text.isEmpty ||
            (['port', 'mixedPort', 'dnsPort'].contains(field) &&
                (port == null || port < 1 || port > 65535)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        key: ValueKey('draft-field-$field'),
        controller: controller,
        obscureText: secret && !_showSecrets,
        autocorrect: !secret,
        enableSuggestions: !secret,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          errorText: invalid
              ? context.appLocalizations.policyDraftIncomplete(field)
              : null,
        ),
      ),
    );
  }

  Widget _choice(String field, String label, Map<String, String> options) {
    final current = _value[field] as String? ?? '';
    final items = {'': context.appLocalizations.policyDraftUnset, ...options};
    if (!items.containsKey(current)) {
      items[current] = context.appLocalizations.policyDraftUnset;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        key: ValueKey('draft-choice-$field'),
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          errorText: current.isEmpty
              ? context.appLocalizations.policyDraftUnset
              : null,
        ),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) => setState(() => _value[field] = value),
      ),
    );
  }

  Widget _target(bool withDns) {
    final l = context.appLocalizations;
    final target = _value['target'];
    final selected = target is Map
        ? switch (target['kind']) {
            'direct' => 'direct',
            'reject' => 'reject',
            'proxy' => 'proxy:${target['group']}',
            _ => 'invalid',
          }
        : '';
    final choices = {
      '': l.policyDraftUnset,
      'direct': 'DIRECT',
      'reject': 'REJECT',
      for (final id in widget.document.resources('groups').keys)
        'proxy:$id': '${l.proxyGroup}: ${widget.document.label(id)}',
    };
    if (!choices.containsKey(selected)) choices[selected] = l.policyDraftUnset;
    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('draft-target'),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l.policyDraftTarget,
            errorText: selected.isEmpty ? l.policyDraftUnset : null,
          ),
          items: [
            for (final e in choices.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (value) => setState(() {
            if (value == 'direct' || value == 'reject') {
              _value['target'] = {'kind': value};
              if (value == 'reject') _value.remove('dnsService');
            } else if (value?.startsWith('proxy:') == true) {
              _value['target'] = {
                'kind': 'proxy',
                'group': value!.substring(6),
              };
            } else if (value == '') {
              _value['target'] = null;
            }
          }),
        ),
        if (withDns && selected != 'reject')
          _choice('dnsService', l.policyDraftDnsServices, {
            for (final id in widget.document.resources('dnsServices').keys)
              id: widget.document.label(id),
          }),
      ],
    );
  }

  void _confirm() {
    final label = _controllers['_label']?.text ?? '';
    for (final entry in _controllers.entries) {
      if (entry.key == '_label') continue;
      final text = entry.value.text;
      _value[entry.key] = ['port', 'mixedPort', 'dnsPort'].contains(entry.key)
          ? int.tryParse(text) ?? text
          : text;
    }
    if (widget.kind == PolicyDraftFormKind.proxy) {
      _value['type'] = 'socks5';
      _value['udp'] ??= false;
      if (!_auth) {
        _value.remove('username');
        _value.remove('password');
      }
    }
    if (widget.kind == PolicyDraftFormKind.group) _value['members'] = _members;
    Navigator.of(
      context,
    ).pop<PolicyDraftFormResult>((value: _value, label: label));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final fields = <Widget>[];
    if (widget.resourceId != null) fields.add(_text('_label', l.name));
    switch (widget.kind) {
      case PolicyDraftFormKind.domain:
        fields.addAll([
          _choice('type', l.rule, {
            'DOMAIN': 'DOMAIN',
            'DOMAIN-SUFFIX': 'DOMAIN-SUFFIX',
          }),
          _text('value', l.domain),
          _target(true),
        ]);
      case PolicyDraftFormKind.ip:
        fields.addAll([_text('cidr', 'CIDR'), _target(false)]);
      case PolicyDraftFormKind.domainDefault:
        fields.addAll([Text(l.policyDraftDirectWarning), _target(true)]);
      case PolicyDraftFormKind.ipDefault:
        fields.add(_target(false));
      case PolicyDraftFormKind.dns:
      case PolicyDraftFormKind.bootstrap:
        fields.addAll([
          _choice('protocol', l.policyDraftProtocol, {
            'tls': 'TLS',
            'tcp': 'TCP',
            'udp': 'UDP',
          }),
          _text('address', l.server),
          _text('port', l.port),
        ]);
      case PolicyDraftFormKind.listeners:
        fields.addAll([
          _text('mixedPort', 'mixed-port'),
          _text('dnsPort', 'DNS ${l.port}'),
        ]);
      case PolicyDraftFormKind.proxy:
        fields.addAll([
          _text('address', l.server),
          _text('port', l.port),
          ListItem.toggle(
            title: Text(l.policyDraftUdp),
            value: _value['udp'] == true,
            onChanged: (v) => setState(() => _value['udp'] = v),
          ),
          ListItem.toggle(
            title: Text(l.policyDraftAuthentication),
            value: _auth,
            onChanged: (v) => setState(() => _auth = v),
          ),
          if (_auth) ...[
            _text('username', l.policyDraftUsername, secret: true),
            _text('password', l.password, secret: true),
            ListItem.toggle(
              title: Text(l.policyDraftRevealCredentials),
              value: _showSecrets,
              onChanged: (v) => setState(() => _showSecrets = v),
            ),
          ],
        ]);
      case PolicyDraftFormKind.group:
        fields.add(Text(l.policyDraftMembers));
        for (final id in {
          ..._members,
          ...widget.document.resources('proxies').keys,
        }) {
          final selected = _members.contains(id);
          fields.add(
            CheckboxListTile(
              value: selected,
              title: Text(
                '${selected ? '${_members.indexOf(id) + 1}. ' : ''}${widget.document.label(id)}',
              ),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _members.add(id);
                } else {
                  _members.remove(id);
                }
              }),
            ),
          );
        }
    }
    return CommonDialog(
      title: widget.title,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _confirm, child: Text(l.confirm)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: fields,
      ),
    );
  }
}
