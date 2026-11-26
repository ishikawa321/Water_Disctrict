import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class BillingHistoryLine {
  const BillingHistoryLine({
    required this.accountNumber,
    required this.holderName,
    required this.serviceAddress,
    required this.billNumber,
    required this.periodStart,
    required this.periodEnd,
    required this.dueDate,
    required this.billed,
    required this.paid,
  });

  final String accountNumber, holderName, serviceAddress, billNumber;
  final String periodStart, periodEnd, dueDate;
  final int billed, paid;
  int get balance => billed > paid ? billed - paid : 0;
  String get status => balance == 0
      ? 'Paid'
      : paid > 0
      ? 'Partially paid'
      : 'Unpaid';
}

String _money(int value) =>
    'PHP ${(value ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}.${(value % 100).toString().padLeft(2, '0')}';

/// Each account starts on its own page, so an admin export never attributes
/// multiple clients' bills to the first account holder.
Future<Uint8List> buildBillingHistoryPdf(
  List<BillingHistoryLine> bills, {
  DateTime? generatedAt,
}) async {
  if (bills.isEmpty) throw ArgumentError('No billing history to export.');
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/DMSans-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/DMSans-SemiBold.ttf'),
  );
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    title: 'Billing history',
    author: 'Maramag Water District',
  );
  final date = (generatedAt ?? DateTime.now()).toUtc().add(
    const Duration(hours: 8),
  );
  final stamp =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  final accounts = <String, List<BillingHistoryLine>>{};
  for (final bill in bills) {
    accounts.putIfAbsent(bill.accountNumber, () => []).add(bill);
  }
  const blue = PdfColor.fromInt(0xFF1852D8);
  const muted = PdfColor.fromInt(0xFF596579);
  for (final entry in accounts.entries) {
    final lines = entry.value;
    final first = lines.first;
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        maxPages: 10000,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MARAMAG WATER DISTRICT',
              style: pw.TextStyle(
                color: blue,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Billing history',
                  style: pw.TextStyle(
                    fontSize: 23,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Generated $stamp (Asia/Manila)',
                  style: const pw.TextStyle(fontSize: 9, color: muted),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Account: ${first.accountNumber}  |  Holder: ${first.holderName}',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Service address: ${first.serviceAddress}',
              style: const pw.TextStyle(fontSize: 10, color: muted),
            ),
            pw.Divider(color: blue),
          ],
        ),
        footer: (context) => pw.Column(
          children: [
            pw.Divider(color: PdfColors.grey300),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Billing record copy, not an official receipt. Payments appear after district verification. Amounts are in Philippine pesos (PHP).',
                    style: const pw.TextStyle(fontSize: 8, color: muted),
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: muted),
                ),
              ],
            ),
          ],
        ),
        build: (_) => [
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: [
              'Bill number',
              'Billing period',
              'Due date',
              'Billed',
              'Payments',
              'Balance',
              'Status',
            ],
            data: [
              for (final b in lines)
                [
                  b.billNumber,
                  '${b.periodStart}\n${b.periodEnd}',
                  b.dueDate,
                  _money(b.billed),
                  _money(b.paid),
                  _money(b.balance),
                  b.status,
                ],
            ],
            columnWidths: {
              0: const pw.FlexColumnWidth(1.8),
              1: const pw.FlexColumnWidth(1.35),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.7),
              4: const pw.FlexColumnWidth(1.7),
              5: const pw.FlexColumnWidth(1.7),
              6: const pw.FlexColumnWidth(1.3),
            },
            headerStyle: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: blue),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.all(8),
            // Headings and values share the same horizontal anchors. All body
            // cells start at the top, even when a billing period spans two lines.
            headerAlignment: pw.Alignment.centerLeft,
            headerAlignments: {
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            cellAlignment: pw.Alignment.topLeft,
            cellAlignments: {
              3: pw.Alignment.topRight,
              4: pw.Alignment.topRight,
              5: pw.Alignment.topRight,
            },
            border: null,
            oddRowDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF1F5FC),
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            '${lines.length} bill(s) | Total billed: ${_money(lines.fold(0, (sum, b) => sum + b.billed))} | Payments: ${_money(lines.fold(0, (sum, b) => sum + b.paid))}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Outstanding balance: ${_money(lines.fold(0, (sum, b) => sum + b.balance))}',
            style: pw.TextStyle(
              fontSize: 14,
              color: blue,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  return doc.save();
}
