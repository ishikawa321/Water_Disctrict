import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'concern_location.dart';

String staffRequestId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

int staffCents(dynamic value) {
  final raw = value.toString();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw)) {
    throw const FormatException(
      'Use a positive amount with up to two decimal places.',
    );
  }
  final parts = raw.split('.');
  return int.parse(parts[0]) * 100 +
      int.parse((parts.length > 1 ? parts[1] : '').padRight(2, '0'));
}

String staffMoney(int cents) =>
    '₱${(cents ~/ 100)}.${(cents % 100).toString().padLeft(2, '0')}';
String staffToday() => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);
List<String> staffRepairChoices(String status, {bool admin = false}) =>
    switch (status) {
      'Open' => admin ? ['Open', 'Assigned'] : [],
      'Assigned' => ['Assigned', 'In progress', 'Resolved'],
      'In progress' => ['In progress', 'Resolved'],
      'Completed' => ['In progress', 'Resolved'],
      _ => [],
    };

class StaffWorkspace extends StatefulWidget {
  const StaffWorkspace({
    super.key,
    required this.onSignOut,
    this.admin = false,
    this.initialTab = 0,
  });
  final VoidCallback onSignOut;
  final bool admin;
  final int initialTab;
  @override
  State<StaffWorkspace> createState() => _StaffWorkspaceState();
}

class _StaffWorkspaceState extends State<StaffWorkspace>
    with WidgetsBindingObserver {
  final client = Supabase.instance.client;
  late int tab;
  bool loading = false;
  String? error;
  List<Map<String, dynamic>> records = [];
  Timer? timer;
  @override
  void initState() {
    super.initState();
    tab = widget.initialTab;
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 60), (_) => load());
    load();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    if (loading || !mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final user = await client.auth.getUser();
      final profile = await client
          .from('profiles')
          .select('role,active')
          .eq('user_id', user.user!.id)
          .maybeSingle();
      if (profile == null ||
          profile['active'] != true ||
          profile['role'] != (widget.admin ? 'admin' : 'staff')) {
        if (mounted) {
          setState(() => records = []);
          await client.auth.signOut(scope: SignOutScope.local);
          widget.onSignOut();
        }
        return;
      }
      List<Map<String, dynamic>> result;
      if (tab == 0) {
        result = await client
            .from('service_concerns')
            .select(
              'id,xmin,account_id,category,subject,description,status,admin_response,repair_dispatched_at,latitude,longitude,location_note,service_accounts(account_number,holder_name)',
            )
            .order('created_at', ascending: false)
            .limit(500);
      } else if (tab == 1) {
        var q = client
            .from('repair_tickets')
            .select(
              'id,xmin,status,concern_id,assigned_to_user_id,assigned_to,latest_update,service_concerns(subject,service_accounts(account_number))',
            );
        if (!widget.admin) q = q.eq('assigned_to_user_id', user.user!.id);
        result = await q.order('updated_at', ascending: false).limit(500);
      } else if (tab == 2) {
        await client.rpc('wd_billing_refresh');
        result = await client
            .from('bills')
            .select(
              '*,service_accounts(account_number),offline_payments(amount_paid)',
            )
            .order('due_date', ascending: false)
            .limit(500);
      } else {
        result = await client
            .from('offline_payments')
            .select(
              'id,receipt_reference,payment_date,amount_paid,bills(bill_number,service_accounts(account_number))',
            )
            .order('verified_at', ascending: false)
            .limit(500);
      }
      if (mounted) setState(() => records = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Could not confirm current records. Refresh to retry. ${e is PostgrestException ? e.message : ''}',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic> relation(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : value is List && value.isNotEmpty
      ? Map<String, dynamic>.from(value.first)
      : {};
  int remaining(Map<String, dynamic> b) {
    var paid = 0;
    for (final p in b['offline_payments'] as List? ?? []) {
      paid += staffCents(p['amount_paid']);
    }
    return (staffCents(b['amount_due']) - paid).clamp(0, 999999999999999);
  }

  Future<void> openForm(
    String title,
    List<OfficeInput> fields,
    Future<String> Function(Map<String, String>) save,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StaffActionForm(title: title, fields: fields, save: save),
      ),
    );
    await load();
  }

  Future<void> review(Map<String, dynamic> c) async {
    if (c['repair_dispatched_at'] != null ||
        ['Closed', 'Resolved'].contains(c['status'])) {
      notice(
        'This concern has a linked repair or is already closed. Use the repair workflow.',
      );
      return;
    }
    await openForm(
      'Review concern',
      [
        OfficeInput(
          'status',
          'Review decision',
          value: 'Under review',
          choices: const {'Under review': 'Under review', 'Closed': 'Closed'},
        ),
        OfficeInput(
          'response',
          'Office response',
          value: c['admin_response'] ?? '',
          required: false,
        ),
      ],
      (v) async {
        await client.rpc(
          'wd_web_workflow',
          params: {
            'p_action': 'review',
            'p_id': c['id'],
            'p_version': int.parse(c['xmin'].toString()),
            'p_payload': {'status': v['status'], 'response': v['response']},
          },
        );
        return 'Review saved.';
      },
    );
  }

  Future<void> intake() async {
    try {
      final accounts = await client
          .from('service_accounts')
          .select('id,account_number,holder_name')
          .eq('active', true)
          .order('account_number')
          .limit(200);
      if (!mounted) return;
      final request = staffRequestId();
      await openForm(
        'Receive a concern',
        [
          OfficeInput(
            'accountId',
            'Service account',
            choices: {
              for (final a in accounts)
                a['id'].toString():
                    '${a['account_number']} / ${a['holder_name']}',
            },
          ),
          OfficeInput(
            'category',
            'Category',
            value: 'Water supply',
            choices: {
              for (final s in [
                'Water supply',
                'Billing inquiry',
                'Repair request',
                'Other',
              ])
                s: s,
            },
          ),
          OfficeInput('subject', 'Subject', max: 150),
          OfficeInput('description', 'Description', max: 3000),
        ],
        (v) async {
          await client.rpc(
            'wd_web_workflow',
            params: {'p_action': 'intake', 'p_id': request, 'p_payload': v},
          );
          return 'Concern received.';
        },
      );
    } catch (_) {
      notice('Active accounts could not be loaded.');
    }
  }

  Future<void> updateTicket(Map<String, dynamic> t) async {
    final choices = staffRepairChoices(t['status'], admin: widget.admin);
    if (choices.isEmpty) {
      notice(
        t['status'] == 'Completed'
            ? 'Work completed. Awaiting final resolution.'
            : 'No updates are available for this state.',
      );
      return;
    }
    try {
      final assignees = widget.admin
          ? await client
                .from('profiles')
                .select('user_id,display_name')
                .eq('role', 'staff')
                .eq('active', true)
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      await openForm(
        t['status'] == 'Completed'
            ? 'Resolve repair'
            : 'Update assigned repair',
        [
          OfficeInput(
            'status',
            'Repair status',
            value: choices.contains(t['status']) ? t['status'] : 'Resolved',
            choices: {for (final s in choices) s: s},
          ),
          if (widget.admin)
            OfficeInput(
              'assignedToUserId',
              'Assigned Staff',
              value: t['assigned_to_user_id'] ?? '',
              required: false,
              choices: {
                '': 'Unassigned',
                for (final p in assignees) p['user_id']: '${p['display_name']}',
              },
            ),
          OfficeInput('note', 'Update note', max: 3000),
        ],
        (v) async {
          await client.rpc(
            'wd_web_workflow',
            params: {
              'p_action': 'update_ticket',
              'p_id': t['id'],
              'p_version': int.parse(t['xmin'].toString()),
              'p_payload': {
                'status': v['status'],
                'note': v['note'],
                'assignedToUserId': widget.admin
                    ? (v['assignedToUserId']!.isEmpty
                          ? null
                          : v['assignedToUserId'])
                    : t['assigned_to_user_id'],
              },
            },
          );
          return v['status'] == 'Completed'
              ? 'Work completed. Awaiting final resolution.'
              : 'Repair update saved.';
        },
      );
    } catch (_) {
      notice('Repair form could not be loaded. Refresh to retry.');
    }
  }

  Future<void> history(Map<String, dynamic> t) async {
    try {
      final rows = await client.rpc(
        'wd_web_ticket_history',
        params: {'p_ticket_id': t['id']},
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: 450,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Saved repair history',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                for (final h in rows as List)
                  ListTile(
                    title: Text('${h['status']} · ${h['changedBy']}'),
                    subtitle: Text('${h['note']}\n${h['changedAt']}'),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      notice('History could not be loaded.');
    }
  }

  Future<void> payment([Map<String, dynamic>? selected]) async {
    try {
      await client.rpc('wd_billing_refresh');
      final bills = await client
          .from('bills')
          .select(
            '*,service_accounts(account_number),offline_payments(amount_paid)',
          )
          .order('due_date', ascending: false)
          .limit(500);
      if (!mounted) return;
      final request = staffRequestId();
      await openForm(
        'Confirm verified payment',
        [
          OfficeInput(
            'billId',
            'Bill',
            value: selected?['id'] ?? '',
            choices: {
              for (final b in bills)
                if (remaining(b) > 0)
                  b['id']:
                      '${b['bill_number']} / ${relation(b['service_accounts'])['account_number']} / ${staffMoney(remaining(b))} remaining',
            },
          ),
          OfficeInput(
            'amount',
            'Verified amount (PHP)',
            value: selected == null
                ? ''
                : (remaining(selected) / 100).toStringAsFixed(2),
            decimal: true,
          ),
          OfficeInput('date', 'Payment date', value: staffToday(), date: true),
        ],
        (v) async {
          final cents = staffCents(v['amount']);
          if (cents <= 0) {
            throw const FormatException('Amount must be positive.');
          }
          final result = await client.rpc(
            'wd_billing_confirm_payment',
            params: {
              'p_request_id': request,
              'p_bill_id': v['billId'],
              'p_amount': v['amount'],
              'p_payment_date': v['date'],
            },
          );
          return 'Payment confirmed. Reference: ${result['receipt_reference']}';
        },
      );
    } catch (_) {
      notice(
        'Bills could not be loaded. Refresh and check your current access.',
      );
    }
  }

  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['Concerns', 'Assigned repairs', 'Bills', 'Payments'];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.admin ? 'Admin repair review' : 'Staff workspace'),
        actions: [
          IconButton(
            tooltip: 'Refresh records',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
          if (!widget.admin)
            IconButton(
              tooltip: 'Sign out',
              onPressed: () async {
                await client.auth.signOut(scope: SignOutScope.local);
                widget.onSignOut();
              },
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: loading
            ? null
            : (i) {
                setState(() {
                  tab = i;
                  records = [];
                });
                load();
              },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Concerns',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            label: 'Repairs',
          ),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Bills'),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            label: 'Payments',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.admin && tab == 1 ? 'Repair review' : labels[tab],
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (tab == 0)
              FilledButton(
                onPressed: loading ? null : intake,
                child: const Text('Receive concern'),
              ),
            if (tab == 3)
              FilledButton(
                onPressed: loading ? null : () => payment(),
                child: const Text('Confirm payment'),
              ),
            if (!loading && error == null && records.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No saved records yet.'),
              ),
            for (final r in records)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: tab == 0
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r['subject']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${relation(r['service_accounts'])['account_number']} · ${r['status']}',
                            ),
                            Text('${r['description']}'),
                            ConcernLocationDetails(concern: r),
                            if (r['admin_response'] != null)
                              Text('${r['admin_response']}'),
                            TextButton(
                              onPressed: () => review(r),
                              child: const Text('Review concern'),
                            ),
                          ],
                        )
                      : tab == 1
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${relation(r['service_concerns'])['subject']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${r['status']} · ${r['assigned_to'] ?? 'Unassigned'}',
                            ),
                            Text('${r['latest_update']}'),
                            if (r['status'] == 'Completed')
                              const Text('Awaiting final resolution'),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: () => updateTicket(r),
                                  child: Text(
                                    r['status'] == 'Completed'
                                        ? 'Confirm resolution'
                                        : 'Update repair',
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => history(r),
                                  child: const Text('History'),
                                ),
                              ],
                            ),
                          ],
                        )
                      : tab == 2
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r['bill_number']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Account: ${relation(r['service_accounts'])['account_number']}',
                            ),
                            Text(
                              'Original: ${staffMoney(staffCents(r['base_amount_due'] ?? r['amount_due']))}',
                            ),
                            Text(
                              'Interest: ${staffMoney(staffCents(r['interest_amount'] ?? 0))} (${r['interest_days'] ?? 0} days)',
                            ),
                            Text(
                              'Remaining: ${staffMoney(remaining(r))} · Due ${r['due_date']}',
                            ),
                            if (remaining(r) > 0)
                              TextButton(
                                onPressed: () => payment(r),
                                child: const Text('Confirm payment'),
                              ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reference ${r['receipt_reference']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${r['payment_date']} · ${staffMoney(staffCents(r['amount_paid']))}',
                            ),
                            Text(
                              'Bill: ${relation(r['bills'])['bill_number']}',
                            ),
                          ],
                        ),
                ),
              ),
            const Text(
              'Up to 500 records shown. Refresh to load the latest saved records.',
            ),
          ],
        ),
      ),
    );
  }
}

class OfficeInput {
  const OfficeInput(
    this.key,
    this.label, {
    this.value = '',
    this.choices,
    this.max = 3000,
    this.required = true,
    this.decimal = false,
    this.date = false,
  });
  final String key, label, value;
  final Map<String, String>? choices;
  final int max;
  final bool required, decimal, date;
}

class StaffActionForm extends StatefulWidget {
  const StaffActionForm({
    super.key,
    required this.title,
    required this.fields,
    required this.save,
  });
  final String title;
  final List<OfficeInput> fields;
  final Future<String> Function(Map<String, String>) save;
  @override
  State<StaffActionForm> createState() => _StaffActionFormState();
}

class _StaffActionFormState extends State<StaffActionForm> {
  final key = GlobalKey<FormState>();
  final values = <String, String>{};
  final controllers = <String, TextEditingController>{};
  bool busy = false, verified = false;
  String? error;
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      values[f.key] = f.value;
      if (f.choices == null) {
        controllers[f.key] = TextEditingController(text: f.value);
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !key.currentState!.validate()) return;
    if (widget.title.contains('payment') && !verified) {
      setState(() => error = 'Confirm verification against district records.');
      return;
    }
    for (final entry in controllers.entries) {
      values[entry.key] = entry.value.text.trim();
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final success = await widget.save(values);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PostgrestException
              ? '${e.message}. Refresh records before retrying a changed version. Your draft is retained.'
              : e is FormatException
              ? e.message
              : 'Save could not be confirmed. Your draft is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Form(
      key: key,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: f.choices != null
                  ? DropdownButtonFormField<String>(
                      initialValue: f.choices!.containsKey(values[f.key])
                          ? values[f.key]
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: f.label),
                      items: f.choices!.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(
                                e.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() => values[f.key] = v ?? ''),
                      validator: (v) => f.required && (v == null || v.isEmpty)
                          ? 'Choose ${f.label}'
                          : null,
                    )
                  : TextFormField(
                      controller: controllers[f.key],
                      enabled: !busy,
                      maxLength: f.max,
                      keyboardType: f.decimal
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      readOnly: f.date,
                      decoration: InputDecoration(labelText: f.label),
                      onTap: f.date
                          ? () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime.parse(values[f.key]!),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.parse(staffToday()),
                              );
                              if (date != null) {
                                controllers[f.key]!.text = date
                                    .toIso8601String()
                                    .substring(0, 10);
                                values[f.key] = controllers[f.key]!.text;
                              }
                            }
                          : null,
                      validator: (v) => f.required && (v ?? '').trim().isEmpty
                          ? 'Enter ${f.label}'
                          : null,
                    ),
            ),
          if (widget.title.contains('payment'))
            CheckboxListTile(
              value: verified,
              onChanged: busy
                  ? null
                  : (v) => setState(() => verified = v ?? false),
              title: const Text(
                'I verified this payment against district records.',
              ),
            ),
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(busy ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    ),
  );
}
