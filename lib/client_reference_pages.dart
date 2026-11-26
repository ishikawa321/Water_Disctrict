part of 'main.dart';

String _accountInitials(String name) => name
    .split(RegExp(r'\s+'))
    .where((s) => s.isNotEmpty)
    .take(2)
    .map((s) => s[0])
    .join()
    .toUpperCase();

/// These helpers are used only by the two reference client pages.
class _ClientReferenceHeader extends StatefulWidget {
  const _ClientReferenceHeader({this.name = ''});
  final String name;
  @override
  State<_ClientReferenceHeader> createState() => _ClientReferenceHeaderState();
}

class _ClientReferenceHeaderState extends State<_ClientReferenceHeader> {
  String name = '';
  @override
  void initState() {
    super.initState();
    loadName();
  }

  Future<void> loadName() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final profile = await supabase
          .from('profiles')
          .select('display_name')
          .eq('user_id', user.id)
          .maybeSingle();
      if (mounted) {
        setState(() => name = profile?['display_name'] as String? ?? '');
      }
    } catch (_) {
      /* Profile content has its own error state. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = _accountInitials(
      widget.name.isNotEmpty ? widget.name : name,
    );
    return Row(
      children: [
        Image.asset(
          'assets/images/maramag-water-district-logo.png',
          width: 40,
          height: 40,
          semanticLabel: 'Maramag Water District logo',
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Maramag Water District',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: const EdgeInsets.all(10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: UtilityStyle.border),
          ),
          child: initials.isEmpty
              ? const Icon(
                  CupertinoIcons.person,
                  color: UtilityStyle.blue,
                  size: 20,
                )
              : Text(
                  initials,
                  style: const TextStyle(
                    color: UtilityStyle.blue,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ClientAccountDetail extends StatelessWidget {
  const _ClientAccountDetail({
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: UtilityStyle.aqua,
          child: Icon(icon, color: UtilityStyle.blue, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: muted, fontSize: 13)),
              if (value != null) ...[
                const SizedBox(height: 4),
                Text(
                  value!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Flexible(child: trailing!),
        ],
      ],
    ),
  );
}

extension _ReferenceAccountLayout on _ClientAccountPageState {
  Widget referenceAccount(BuildContext context) {
    final record = account;
    final holder = record?['holder_name'] as String? ?? '';
    return UtilityScaffold(
      extendBody: false,
      bottomNavigationBar: const ClientDesignNav(index: 3),
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: () async {
                await loadAccount();
                await loadNoticeCount();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _ClientReferenceHeader(name: holder),
                  const SizedBox(height: 24),
                  const Text('My account', style: UtilityStyle.title),
                  const SizedBox(height: 6),
                  const Text(
                    'Your account details, district notices and help.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 22),
                  if (loading)
                    const LoadingCards(count: 1)
                  else if (error != null) ...[
                    Text(error!),
                    TextButton(
                      onPressed: loadAccount,
                      child: const Text('Retry'),
                    ),
                  ] else if (record == null)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No linked account. Contact district personnel to finish setup.',
                        ),
                      ),
                    )
                  else ...[
                    WaterSurface(
                      radius: 18,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: UtilityStyle.aqua,
                              child: Text(
                                _accountInitials(holder),
                                style: const TextStyle(
                                  color: UtilityStyle.navy,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    holder,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Water-service account holder',
                                    style: TextStyle(
                                      color: Color(0xFFEEF5FF),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text('Account details', style: UtilityStyle.section),
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: UtilityStyle.border),
                      ),
                      child: Column(
                        children: [
                          _ClientAccountDetail(
                            icon: CupertinoIcons.number,
                            label: 'Account number',
                            value: '${record['account_number']}',
                          ),
                          const Divider(height: 1, indent: 56),
                          _ClientAccountDetail(
                            icon: CupertinoIcons.location,
                            label: 'Service address',
                            value: '${record['service_address']}',
                          ),
                          const Divider(height: 1, indent: 56),
                          _ClientAccountDetail(
                            icon: CupertinoIcons.shield_lefthalf_fill,
                            label: 'Account status',
                            trailing: StatusBadge(
                              record['active'] == true ? 'Active' : 'Inactive',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  const Text('Notices & help', style: UtilityStyle.section),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: UtilityStyle.border),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: const Icon(
                        CupertinoIcons.speaker_2,
                        color: UtilityStyle.blue,
                      ),
                      title: const Text(
                        'Announcements',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        noticeCount == null
                            ? 'View notices from the district'
                            : noticeCount == 0
                            ? 'No published district notices'
                            : '$noticeCount published district notices',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (noticeCount != null && noticeCount! > 0) ...[
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: UtilityStyle.blue,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$noticeCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          const Icon(CupertinoIcons.chevron_right, size: 16),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const AnnouncementsPage(isAdmin: false),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: UtilityStyle.border),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: const Icon(
                        CupertinoIcons.question_circle,
                        color: UtilityStyle.blue,
                      ),
                      title: const Text(
                        'Get help',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'How to fix account details or ask the district',
                      ),
                      trailing: const Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                      ),
                      onTap: showHelp,
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(CupertinoIcons.square_arrow_right),
                    label: const Text('Sign out'),
                    onPressed: () async {
                      try {
                        await supabase.auth.signOut();
                        if (context.mounted) {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not sign out. Please retry.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension _ReferenceBillsLayout on _BillsPageState {
  Widget referenceBills(BuildContext context) {
    final visible = bills
        .where(
          (b) =>
              !outstandingOnly ||
              moneyCentavos(b['amount_due']) > billPayments(b),
        )
        .toList();
    return UtilityScaffold(
      extendBody: false,
      bottomNavigationBar: const ClientDesignNav(index: 1),
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: loadBills,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      children: [
                        const _ClientReferenceHeader(),
                        const SizedBox(height: 24),
                        const Text(
                          'Bills & payments',
                          style: UtilityStyle.title,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'See what you owe, your payments, and download your bills.',
                          style: TextStyle(color: muted),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: UtilityStyle.border),
                          ),
                          child: Row(
                            children: [
                              for (final payments in [false, true])
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => selectPaymentTab(payments),
                                    style: TextButton.styleFrom(
                                      backgroundColor: showPayments == payments
                                          ? UtilityStyle.aqua
                                          : Colors.transparent,
                                      foregroundColor: showPayments == payments
                                          ? UtilityStyle.navy
                                          : muted,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      payments ? 'Payments' : 'Bills',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (showPayments)
                          const SizedBox(
                            height: 620,
                            child: PaymentsPage(isAdmin: false, embedded: true),
                          )
                        else ...[
                          const SizedBox(height: 20),
                          Center(
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const Text('Outstanding'),
                                  selected: outstandingOnly,
                                  onSelected: (_) => selectBillFilter(true),
                                ),
                                ChoiceChip(
                                  label: const Text('All bills'),
                                  selected: !outstandingOnly,
                                  onSelected: (_) => selectBillFilter(false),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (loading)
                            const LoadingCards()
                          else if (error != null)
                            EmptyState(
                              title: 'Unable to load bills',
                              message: error!,
                              icon: CupertinoIcons.wifi_exclamationmark,
                              actionLabel: 'Retry',
                              onAction: loadBills,
                            )
                          else if (visible.isEmpty)
                            EmptyState(
                              title: outstandingOnly
                                  ? 'No outstanding bills'
                                  : 'No bills yet',
                              message: outstandingOnly
                                  ? 'You can still review your billing history.'
                                  : 'New billing records will appear here.',
                              icon: CupertinoIcons.doc_text,
                              actionLabel: outstandingOnly
                                  ? 'View all bills'
                                  : null,
                              onAction: outstandingOnly
                                  ? () => selectBillFilter(false)
                                  : null,
                            )
                          else
                            ...visible.map(
                              (bill) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: referenceBillCard(context, bill),
                              ),
                            ),
                          if (bills.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: loading || exporting || error != null
                                  ? null
                                  : () => downloadHistory(),
                              icon: const Icon(CupertinoIcons.arrow_down_doc),
                              label: Text(
                                exporting
                                    ? 'Preparing PDF...'
                                    : 'Download billing history PDF',
                              ),
                            ),
                            const Text(
                              'Includes paid and outstanding bills.',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget referenceBillCard(BuildContext context, Map<String, dynamic> bill) {
    final billed = moneyCentavos(bill['amount_due']), paid = billPayments(bill);
    final remaining = billed > paid ? billed - paid : 0;
    final account = bill['service_accounts'] as Map<String, dynamic>?;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: UtilityStyle.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  'Bill ${bill['bill_number']}',
                  style: UtilityStyle.section,
                ),
                StatusBadge(
                  remaining == 0
                      ? 'Paid'
                      : paid > 0
                      ? 'Partially paid'
                      : 'Unpaid',
                ),
              ],
            ),
            const SizedBox(height: 18),
            AmountText('₱${formatCentavos(remaining)}', color: ink),
            const SizedBox(height: 8),
            Text(
              'Due ${recordDate(bill['due_date'])}',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: const Text(
                'Billing details',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: UtilityStyle.blue,
                ),
              ),
              children: [
                DesignValue('Original bill', '₱${formatCentavos(billed)}'),
                const SizedBox(height: 12),
                DesignValue('Verified payments', '₱${formatCentavos(paid)}'),
                const SizedBox(height: 16),
                Text(
                  'Period: ${recordDate(bill['billing_period_start'])} – ${recordDate(bill['billing_period_end'])}',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 8),
                Text('Account: ${account?['account_number'] ?? 'Unavailable'}'),
                if (paid > billed)
                  Text(
                    'Payments exceed this bill by ₱${formatCentavos(paid - billed)}. Contact district personnel for review.',
                  ),
                if (paid > 0)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PaymentsPage(
                          isAdmin: false,
                          billNumber: '${bill['bill_number']}',
                        ),
                      ),
                    ),
                    icon: const Icon(CupertinoIcons.doc_text, size: 18),
                    label: const Text('View payment record'),
                  ),
              ],
            ),
            if (remaining > 0) ...[
              OutlinedButton.icon(
                onPressed: () => showPaymentGuidance(
                  context,
                  accountNumber:
                      '${account?['account_number'] ?? 'Unavailable'}',
                  billNumber: '${bill['bill_number']}',
                ),
                icon: const Icon(CupertinoIcons.info_circle, size: 18),
                label: const Text('View payment instructions'),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
