import 'package:supabase_flutter/supabase_flutter.dart';

/// Read the same issued records and verified payments as the office website.
/// The caller's session/RLS remains authoritative; due dates never hide bills.
Future<List<Map<String, dynamic>>> loadIssuedBills(
  SupabaseClient client, {
  required bool admin,
}) async {
  String? accountId;
  if (!admin) {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in to view bills.');
    final link = await client
        .from('account_access')
        .select('account_id')
        .eq('user_id', user.id)
        .eq('active', true)
        .maybeSingle();
    if (link == null) return [];
    accountId = link['account_id'] as String;
  }
  try {
    await client.rpc('wd_billing_refresh');
  } on PostgrestException catch (error) {
    // Older installations can still read issued bills during migration.
    if (error.code != 'PGRST202') rethrow;
  }
  final records = <Map<String, dynamic>>[];
  for (var offset = 0; ; offset += 500) {
    final query = client
        .from('bills')
        .select(
          'id,bill_number,billing_period_start,billing_period_end,due_date,'
          'amount_due,base_amount_due,interest_amount,interest_days,'
          'service_accounts(account_number,holder_name,service_address)',
        );
    final page =
        await (accountId == null ? query : query.eq('account_id', accountId))
            .order('due_date', ascending: false)
            .order('id')
            .range(offset, offset + 499);
    records.addAll(page);
    if (page.length < 500) break;
  }
  final byId = {for (final bill in records) bill['id'] as String: bill};
  for (final bill in records) {
    bill['offline_payments'] = <Map<String, dynamic>>[];
  }
  final ids = byId.keys.toList();
  for (var start = 0; start < ids.length; start += 50) {
    final batch = ids.sublist(
      start,
      start + 50 < ids.length ? start + 50 : ids.length,
    );
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('offline_payments')
          .select('id,bill_id,amount_paid')
          .inFilter('bill_id', batch)
          .order('id')
          .range(offset, offset + 499);
      for (final payment in page) {
        final bill = byId[payment['bill_id']];
        if (bill != null) (bill['offline_payments'] as List).add(payment);
      }
      if (page.length < 500) break;
    }
  }
  return records;
}
