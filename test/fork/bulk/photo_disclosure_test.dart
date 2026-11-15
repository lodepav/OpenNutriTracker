import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/fork/bulk/photo_disclosure.dart';

void main() {
  const openRouter = (provider: AiProvider.openrouter, name: 'Google');
  final seen = photoDisclosureKey(openRouter, keepsPhoto: false);

  PhotoSheet sheet(
    PhotoDestination? destination, {
    bool keepsPhoto = false,
    String? seenKey,
    bool shared = false,
  }) => photoSheetFor(
    destination,
    keepsPhoto: keepsPhoto,
    seen: seenKey,
    shared: shared,
  );

  test('never seen: the sheet shows', () {
    expect(sheet(openRouter), PhotoSheet.show);
  });

  test('seen for the same destination: straight to the camera', () {
    expect(sheet(openRouter, seenKey: seen), PhotoSheet.skip);
  });

  test('any part of the destination changed: the sheet shows again', () {
    // another vendor behind the same provider
    expect(
      sheet((provider: AiProvider.openrouter, name: 'OpenAI'), seenKey: seen),
      PhotoSheet.show,
    );
    // another provider of the same name
    expect(
      sheet((provider: AiProvider.ownServer, name: 'Google'), seenKey: seen),
      PhotoSheet.show,
    );
    // another server address
    final server = (provider: AiProvider.ownServer, name: '192.168.1.5:11434');
    expect(
      sheet((
        provider: AiProvider.ownServer,
        name: '192.168.1.6:11434',
      ), seenKey: photoDisclosureKey(server, keepsPhoto: false)),
      PhotoSheet.show,
    );
    // meal photos kept now
    expect(sheet(openRouter, keepsPhoto: true, seenKey: seen), PhotoSheet.show);
  });

  test('a shared photo always shows it', () {
    expect(sheet(openRouter, seenKey: seen, shared: true), PhotoSheet.show);
  });

  test('no destination: refused, seen or not', () {
    expect(sheet(null), PhotoSheet.refuse);
    expect(sheet(null, seenKey: seen, shared: true), PhotoSheet.refuse);
  });
}
