import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:water_district_connect/staff_workspace.dart';

void main() {
  test(
    'Staff completion requires Admin confirmation and centavos remain exact',
    () {
      expect(staffRepairChoices('In progress'), ['In progress', 'Completed']);
      expect(staffRepairChoices('Completed'), isEmpty);
      expect(
        staffRepairChoices('Completed', admin: true),
        contains('Resolved'),
      );
      expect(staffCents('0.10') + staffCents('0.20'), 30);
      expect(staffMoney(12345), '₱123.45');
      expect(() => staffCents('1e2'), throwsFormatException);
    },
  );
  testWidgets(
    'A failed repair save keeps its required note and allows a retry',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StaffActionForm(
            title: 'Update assigned repair',
            fields: const [OfficeInput('note', 'Update note')],
            save: (v) async {
              calls++;
              expect(v['note'], 'Repair completed at meter');
              throw Exception('offline');
            },
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField),
        'Repair completed at meter',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Repair completed at meter'), findsOneWidget);
      expect(find.textContaining('draft is retained'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
}
