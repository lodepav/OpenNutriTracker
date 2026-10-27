import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/fork/launch/launch_actions.dart';

void main() {
  group('LaunchAction.parse', () {
    test('reads each shortcut', () {
      expect(LaunchAction.parse({'kind': 'scan'}), isA<ScanAction>());
      expect(LaunchAction.parse({'kind': 'photo'}), isA<PhotoAction>());
      expect(LaunchAction.parse({'kind': 'quickAdd'}), isA<QuickAddAction>());
      expect(LaunchAction.parse({'kind': 'weighIn'}), isA<WeighInAction>());
    });

    test('reads a shared photo with its path', () {
      final action = LaunchAction.parse({
        'kind': 'sharedPhoto',
        'path': '/cache/fork_shared/shared_1',
      });
      expect(action, isA<SharedPhotoAction>());
      expect(
        (action! as SharedPhotoAction).path,
        '/cache/fork_shared/shared_1',
      );
    });

    test('reads shared text, trimmed', () {
      final action = LaunchAction.parse({
        'kind': 'sharedText',
        'text': '  2 eggs and toast \n',
      });
      expect((action! as SharedTextAction).text, '2 eggs and toast');
    });

    test('ignores an ordinary start, an unknown kind and missing data', () {
      expect(LaunchAction.parse(null), isNull);
      expect(LaunchAction.parse({'kind': 'teleport'}), isNull);
      expect(LaunchAction.parse({'kind': 'sharedPhoto'}), isNull);
      expect(LaunchAction.parse({'kind': 'sharedText', 'text': '  '}), isNull);
    });
  });
}
