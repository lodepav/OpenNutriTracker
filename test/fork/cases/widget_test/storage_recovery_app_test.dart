// Fork cases moved out of test/widget_test/storage_recovery_app_test.dart (they test the fork's changes).

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/storage_recovery_app.dart';
import 'package:opennutritracker/fork/backup/storage_rescue.dart';

void main() {
  testWidgets('a lost key offers no setting aside', (tester) async {
    await tester.pumpWidget(
      StorageRecoveryApp(
        errorCode: 'hive_encryption_key_missing_with_existing_data',
        onRetry: () async {},
      ),
    );
    expect(find.byType(StorageRescuePanel), findsNothing);
    expect(find.textContaining('contact support'), findsOneWidget);
  });
}
