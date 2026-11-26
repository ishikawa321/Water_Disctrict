import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:water_district_connect/billing_history_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  BillingHistoryLine line(int index, {String account = 'MWD-001248'}) =>
      BillingHistoryLine(
        accountNumber: account,
        holderName: account == 'MWD-001248' ? 'Sample Client' : 'Second Client',
        serviceAddress: 'Maramag, Bukidnon - sample service address',
        billNumber: 'MWD-202611-${1000000000 + index}',
        periodStart: '2026-10-01',
        periodEnd: '2026-10-31',
        dueDate: '2026-11-15',
        billed: 123456,
        paid: index == 0
            ? 123456
            : index == 1
            ? 50000
            : 0,
      );
  test(
    'preserves centavos and distinguishes paid, partial and unpaid records',
    () {
      expect(line(0).status, 'Paid');
      expect(line(0).balance, 0);
      expect(line(1).status, 'Partially paid');
      expect(line(1).balance, 73456);
      expect(line(2).status, 'Unpaid');
      expect(line(2).balance, 123456);
    },
  );
  test(
    'rejects empty history instead of generating an invalid statement',
    () async {
      await expectLater(buildBillingHistoryPdf([]), throwsArgumentError);
    },
  );
  test('keeps large monetary values inside their designated columns', () async {
    final bytes = await buildBillingHistoryPdf([
      const BillingHistoryLine(
        accountNumber: 'MWD-001245',
        holderName: 'Sample Client',
        serviceAddress: 'Maramag service address',
        billNumber: '123456',
        periodStart: '27 Nov 2026',
        periodEnd: '29 Nov 2026',
        dueDate: '29 Nov 2026',
        billed: 12345678900,
        paid: 12345678900,
      ),
      const BillingHistoryLine(
        accountNumber: 'MWD-001245',
        holderName: 'Sample Client',
        serviceAddress: 'Maramag service address',
        billNumber: 'MAX-AMOUNT',
        periodStart: '27 Nov 2026',
        periodEnd: '29 Nov 2026',
        dueDate: '29 Nov 2026',
        billed: 999999999999,
        paid: 100,
      ),
    ], generatedAt: DateTime.utc(2026, 11, 27));
    await Directory('build/pdf-review').create(recursive: true);
    await File('build/pdf-review/aligned-billing-history.pdf')
        .writeAsBytes(bytes);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
  test(
    'generates a multipage admin history with independent account sections',
    () async {
      final records = [
        for (var i = 0; i < 65; i++) line(i),
        line(99, account: 'MWD-001249'),
      ];
      final bytes = await buildBillingHistoryPdf(
        records,
        generatedAt: DateTime.utc(2026, 11, 26, 18),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      await Directory('build/pdf-review').create(recursive: true);
      await File('build/pdf-review/admin-billing-history.pdf')
          .writeAsBytes(bytes);
      final client = await buildBillingHistoryPdf(
        records.take(3).toList(),
        generatedAt: DateTime.utc(2026, 11, 26, 18),
      );
      await File('build/pdf-review/client-billing-history.pdf')
          .writeAsBytes(client);
    },
  );
}
