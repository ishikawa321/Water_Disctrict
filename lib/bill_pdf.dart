import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// One bill, with amounts already computed in centavos.
class BillPdfLine {
  const BillPdfLine({
    required this.billNumber,
    required this.accountNumber,
    required this.holderName,
    required this.serviceAddress,
    required this.periodStart,
    required this.periodEnd,
    required this.dueDate,
    required this.billed,
    required this.paid,
    required this.remaining,
    required this.status,
  });

  final String billNumber, accountNumber, holderName, serviceAddress;
  final String periodStart, periodEnd, dueDate, status;
  final int billed, paid, remaining;
}

const _blue = PdfColor.fromInt(0xFF2563EB);
const _ink = PdfColor.fromInt(0xFF111827);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _line = PdfColor.fromInt(0xFFE5E7EB);
const _tint = PdfColor.fromInt(0xFFEFF4FF);

String _peso(int centavos) {
  final whole = (centavos ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '₱$whole.${(centavos % 100).toString().padLeft(2, '0')}';
}

Future<pw.ThemeData> _theme() async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DMSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DMSans-SemiBold.ttf'));
  // DM Sans has no peso sign; the bundled currency font supplies it.
  final currency = pw.Font.ttf(await rootBundle.load('assets/fonts/CurrencySymbols.ttf'));
  return pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [currency]);
}

/// A one-bill document, or a statement table when [bills] has several.
Future<Uint8List> buildBillsPdf(List<BillPdfLine> bills, {DateTime? now}) async {
  final generated = now ?? DateTime.now();
  final doc = pw.Document(
    theme: await _theme(),
    title: bills.length == 1 ? 'Bill ${bills.first.billNumber}' : 'Billing statement',
    author: 'Maramag Water District',
  );
  final first = bills.first;
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    header: (_) => _header(bills.length == 1 ? 'Water bill' : 'Billing statement', generated),
    footer: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Divider(color: _line),
      pw.Text(
        'Copy of your billing record from Water District Connect. This is not an official receipt; '
        'payments appear after district verification.',
        style: const pw.TextStyle(fontSize: 8, color: _muted),
      ),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ),
    ]),
    build: (_) => [
      _account(first),
      pw.SizedBox(height: 20),
      if (bills.length == 1) ..._single(first) else ..._statement(bills),
    ],
  ));
  return doc.save();
}

/// Saves (web) or shares (mobile/desktop) the PDF.
Future<void> shareBillsPdf(List<BillPdfLine> bills, {required String filename}) async {
  await Printing.sharePdf(bytes: await buildBillsPdf(bills), filename: filename);
}

pw.Widget _header(String title, DateTime generated) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 20),
  padding: const pw.EdgeInsets.only(bottom: 12),
  decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _blue, width: 2))),
  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
    pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Maramag Water District', style: pw.TextStyle(fontSize: 11, color: _blue, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text(title, style: pw.TextStyle(fontSize: 22, color: _ink, fontWeight: pw.FontWeight.bold)),
    ])),
    pw.Text('Generated ${_date(generated)}', style: const pw.TextStyle(fontSize: 9, color: _muted)),
  ]),
);

pw.Widget _account(BillPdfLine b) => pw.Container(
  padding: const pw.EdgeInsets.all(14),
  decoration: pw.BoxDecoration(color: _tint, borderRadius: pw.BorderRadius.circular(6)),
  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Expanded(child: _field('Account holder', b.holderName)),
    pw.Expanded(child: _field('Account number', b.accountNumber)),
    pw.Expanded(flex: 2, child: _field('Service address', b.serviceAddress)),
  ]),
);

List<pw.Widget> _single(BillPdfLine b) => [
  pw.Row(children: [
    pw.Expanded(child: _field('Bill number', b.billNumber)),
    pw.Expanded(child: _field('Billing period', '${b.periodStart} – ${b.periodEnd}')),
    pw.Expanded(child: _field('Due date', b.dueDate)),
  ]),
  pw.SizedBox(height: 20),
  pw.Table(
    border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line)),
    children: [
      _amountRow('Original bill', b.billed),
      _amountRow('Verified payments', b.paid),
    ],
  ),
  pw.Container(
    margin: const pw.EdgeInsets.only(top: 8),
    padding: const pw.EdgeInsets.symmetric(vertical: 12),
    decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _ink, width: 1))),
    child: pw.Row(children: [
      pw.Expanded(child: pw.Text('Amount due', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
      pw.Text(_peso(b.remaining), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink)),
    ]),
  ),
  pw.SizedBox(height: 6),
  pw.Text('Status: ${b.status}', style: const pw.TextStyle(fontSize: 11, color: _muted)),
];

List<pw.Widget> _statement(List<BillPdfLine> bills) {
  final total = bills.fold<int>(0, (sum, b) => sum + b.remaining);
  return [
    pw.TableHelper.fromTextArray(
      headers: ['Bill', 'Period', 'Due', 'Billed', 'Paid', 'Balance', 'Status'],
      data: [
        for (final b in bills)
          [b.billNumber, '${b.periodStart} – ${b.periodEnd}', b.dueDate,
            _peso(b.billed), _peso(b.paid), _peso(b.remaining), b.status],
      ],
      headerStyle: pw.TextStyle(fontSize: 9, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: _blue),
      cellStyle: const pw.TextStyle(fontSize: 9, color: _ink),
      cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line))),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    ),
    pw.SizedBox(height: 14),
    pw.Row(children: [
      pw.Expanded(child: pw.Text('Total outstanding', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
      pw.Text(_peso(total), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
    ]),
  ];
}

pw.TableRow _amountRow(String label, int value) => pw.TableRow(children: [
  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 8),
    child: pw.Text(label, style: const pw.TextStyle(fontSize: 11, color: _muted))),
  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 8),
    child: pw.Text(_peso(value), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 11))),
]);

pw.Widget _field(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.only(right: 10),
  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _muted)),
    pw.SizedBox(height: 3),
    pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
  ]),
);

String _date(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
