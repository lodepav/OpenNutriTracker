import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';
import 'package:opennutritracker/fork/adaptive/adaptive_store.dart';
import 'package:opennutritracker/fork/leftovers/meal_photo_cache.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Where a meal photo would go, and the name the disclosure gives it.
typedef PhotoDestination = ({AiProvider provider, String name});

/// The destination a photo would be sent to now, or null when there is no
/// identifiable one: the stored provider is unknown, its model is not in
/// the catalogue, or a server the user runs has no passed photo probe or
/// readable address. The photo sheet on Log with AI and the settings row
/// both name it from here.
Future<PhotoDestination?> photoDestinationOf(
  AiCredentialStorage storage,
) async {
  final provider = await storage.activeProvider();
  if (provider == null) return null;
  if (provider == AiProvider.ownServer) {
    return _ownServerDestination(storage);
  }
  final model = AiModelCatalogue.resolve(
    provider,
    await storage.readModel(provider: provider),
  );
  if (model == null) return null;
  return (provider: provider, name: model.servedBy);
}

/// A server the user runs, **only once a photo probe has passed against the
/// pair currently configured** — and null otherwise.
///
/// The stored pass is the whole gate (#735). There is no curated list here
/// and no behavioural screen the project can run against a machine it has
/// never seen, so the app's own setup-time test is what stands in for one;
/// and unlike the text path there is nothing underneath a photo to fall
/// back to, so offering the camera to a model that cannot see is offering a
/// dead end. [AiCredentialStorage.writeEndpoint] and
/// [AiCredentialStorage.writeModel] each discard the record when their
/// value changes, so a pass read here can only describe the address and
/// model in use right now.
///
/// A missing host is a second, independent null: the sheet's whole job for
/// this provider is to say the address out loud, and it cannot do that from
/// text that is not one.
Future<PhotoDestination?> _ownServerDestination(
  AiCredentialStorage storage,
) async {
  const provider = AiProvider.ownServer;
  final probe = await storage.readProbe(provider: provider);
  if (probe.photo != AiCapability.passed) return null;
  final endpoint = await storage.readEndpoint(provider: provider);
  if (endpoint == null) return null;
  final host = AiCredentialStorage.displayHost(endpoint);
  if (host == null) return null;
  return (provider: provider, name: host);
}

/// What happens to a photo sent to [destination], as the photo sheet and
/// the settings row say it; [keepsPhoto] when a copy is kept for leftovers.
String photoDisclosureText(
  S s,
  PhotoDestination destination, {
  required bool keepsPhoto,
}) {
  final disclosure = switch (destination.provider) {
    AiProvider.anthropic => s.bulkAddPhotoDisclosureAnthropic,
    AiProvider.openrouter => s.bulkAddPhotoDisclosureOpenRouter(
      destination.name,
    ),
    // No placeholder: a direct path has no serving vendor to name, so this
    // string is flat where OpenRouter's is parameterised.
    AiProvider.openai => s.bulkAddPhotoDisclosureOpenAI,
    // The address, and nothing beyond it. Not "no third party receives it",
    // however tempting: the app cannot tell a local runtime from a
    // self-hosted proxy forwarding to OpenAI, and #732 ruled those out of
    // scope by making no claim about them rather than by detecting them.
    // The no-copy sentence below is about this app and still holds.
    AiProvider.ownServer => s.bulkAddPhotoDisclosureOwnServer(destination.name),
  };
  return '$disclosure '
      '${keepsPhoto ? keptPhotoDisclosure : s.bulkAddPhotoDisclosureCommon}\n\n'
      // The photo path has no deterministic fallback, so this is the only
      // surface besides Settings where a user opts into a model. The
      // stability note belongs on both.
      '${s.aiAssistExperimentalNote}';
}

/// What the disclosure was shown for: a changed vendor, server address or
/// keep-photos switch is a new one.
String photoDisclosureKey(
  PhotoDestination destination, {
  required bool keepsPhoto,
}) => '${destination.provider.name}|${destination.name}|$keepsPhoto';

enum PhotoSheet {
  /// No identifiable destination: nothing honest to say, so no photo.
  refuse,

  /// The disclosure first, with the button that opens the camera.
  show,

  /// Straight to the camera or gallery.
  skip,
}

/// Whether the photo sheet shows before a photo is taken: once per
/// [photoDisclosureKey], whose last one continued from is [seen]. A
/// [shared] photo always shows it, since its button is the only
/// confirmation there.
PhotoSheet photoSheetFor(
  PhotoDestination? destination, {
  required bool keepsPhoto,
  required String? seen,
  required bool shared,
}) {
  if (destination == null) return PhotoSheet.refuse;
  if (shared) return PhotoSheet.show;
  return seen == photoDisclosureKey(destination, keepsPhoto: keepsPhoto)
      ? PhotoSheet.skip
      : PhotoSheet.show;
}

/// The [photoDisclosureKey] the active profile last continued from, in the
/// profile's fork box. Never in a backup: a restore on another phone
/// discloses again.
class PhotoDisclosureSeen {
  static const key = 'photoDisclosureSeen';

  final Future<Box<dynamic>> Function() _box;

  PhotoDisclosureSeen([Future<Box<dynamic>> Function()? box])
    : _box = box ?? AdaptiveStore.openActiveBox;

  /// Null when nothing is stored or it cannot be read: then the sheet shows.
  Future<String?> read() async {
    try {
      return (await _box()).get(key) as String?;
    } catch (e) {
      Logger('PhotoDisclosure').info('Seen disclosure not read: $e');
      return null;
    }
  }

  /// A failure only means the sheet shows again next time.
  Future<void> write(String seen) async {
    try {
      await (await _box()).put(key, seen);
    } catch (e) {
      Logger('PhotoDisclosure').info('Seen disclosure not kept: $e');
    }
  }
}

/// The photo disclosure for the current destination, from Settings.
Future<void> showPhotoDisclosure(
  BuildContext context,
  AiCredentialStorage storage, {
  MealPhotoCache? cache,
}) async {
  final destination = await photoDestinationOf(storage);
  final keepsPhoto = await (cache ?? MealPhotoCache()).keepsPhotos;
  if (!context.mounted) return;
  final s = S.of(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('What happens to a meal photo'),
      content: SingleChildScrollView(
        child: Text(
          destination == null
              ? 'No model that reads photos is set up, so no photo is sent.'
              : photoDisclosureText(s, destination, keepsPhoto: keepsPhoto),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
        ),
      ],
    ),
  );
}
