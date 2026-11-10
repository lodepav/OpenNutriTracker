import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/gemini_endpoint.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Google Gemini as a choice in AI settings (D43, S209).
///
/// A preset of [AiProvider.ownServer], not a fifth provider: the own-server
/// client already speaks to Google's OpenAI-compatible endpoint, and its
/// disclosure, consent, key binding and setup check already know the host
/// (#1253, #1257). The row fills in Google's address and the model, so the
/// user only pastes a key. The cost is that it shares the own-server slot:
/// saving Gemini replaces a server the user runs, which the dialog says.

/// Google's documented base (`…/v1beta/openai/`), completed to the chat
/// route as [AiCredentialStorage.resolveEndpoint] stores it.
const geminiPresetEndpoint =
    'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';

/// Gemini 3.8 Flash, as Google's OpenAI compatibility page names it
/// (https://ai.google.dev/gemini-api/docs/openai, read 2026-11-10).
const geminiPresetModel = 'gemini-3.8-flash';

/// The models a Gemini address may carry and still show as the Google Gemini
/// row. A Gemini address with another model was typed under "Your own
/// server" and stays there, fields and all. A later preset model goes in
/// front, and the old one stays so its users keep the row.
const geminiPresetModels = {geminiPresetModel};

/// `max_tokens` for Google's endpoint.
///
/// Google counts thinking against the output limit ("`max_output_tokens`
/// … including thought tokens", https://ai.google.dev/gemini-api/docs/thinking),
/// and Gemini 3.8 Flash thinks at medium by default, which cannot be turned
/// off for Gemini 3 models (https://ai.google.dev/gemini-api/docs/openai).
/// At the client's 1,024 it returned nothing for 25 of 67 photos, and for
/// none at 4,096, the limit its 22% median calorie error was measured at.
/// Thinking is left at the default: `reasoning_effort: "low"` is documented
/// and would be quicker and cheaper, but its accuracy was never measured.
const geminiMaxTokens = 4096;

/// Whether [endpoint] is Google's Gemini API.
bool isGeminiAddress(String? endpoint) {
  final uri = endpoint == null ? null : Uri.tryParse(endpoint.trim());
  return uri != null && uri.host.isNotEmpty && isGeminiEndpoint(uri);
}

/// Whether [provider] at [endpoint] with [model] is the Google Gemini row.
bool isGeminiPreset({
  required AiProvider provider,
  required String? endpoint,
  required String? model,
}) =>
    provider == AiProvider.ownServer &&
    isGeminiAddress(endpoint) &&
    geminiPresetModels.contains(model?.trim());

/// Whether the dialog shows the Google Gemini row as chosen after reading
/// the store: the stored configuration is the preset, or the row was chosen
/// and nothing is stored yet (a key just removed keeps the row).
bool geminiChosenAfterLoad({
  required AiProvider provider,
  required String? endpoint,
  required String? model,
  required bool wasChosen,
}) =>
    isGeminiPreset(provider: provider, endpoint: endpoint, model: model) ||
    (wasChosen && provider == AiProvider.ownServer && endpoint == null);

/// The row's name, a brand, as the other providers' are.
const geminiChoiceLabel = 'Google Gemini';

const geminiKeyHint =
    'Paste a key from Google AI Studio (aistudio.google.com/apikey).';

/// Google's terms in two sentences, checked against
/// https://ai.google.dev/gemini-api/terms (effective 2026-03-23): "Unpaid
/// Services … to provide, improve, and develop Google products", "Paid
/// Services … doesn't use your prompts … to improve our products", "You must
/// be 18 years of age or older to use the APIs".
const geminiTermsNote =
    "On Google's free tier, Google may use what you send to improve its "
    "products; on the paid tier it does not. Google's terms require users to "
    'be 18 or over.';

const geminiKeyMissing = 'Paste a key from Google AI Studio.';

const geminiReplacesOwnServer =
    "Saving replaces your own server's address and model.";

/// Speed and cost only, measured on 51 photos (D43). No accuracy claim: one
/// run on lab plates, and the user's own meals read well under it.
const geminiMeasured =
    r'About 13 s and $0.006 a photo (Haiku 5.5: 1.6 s, $0.0005).';

/// The consent screen's own-server note, for Google: it is not the user's
/// server, and the row asks it for no model list.
const geminiCheckNote =
    'Saving also runs one setup check with Google: a fixed example line and '
    'a sample photograph of ours, never anything of yours.';

/// The Google Gemini row under the provider radios.
class GeminiChoiceTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onSelect;

  const GeminiChoiceTile({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: 'ai-assist-provider-gemini',
    // The same deprecated-but-working form as the dialog's other radios.
    // ignore: deprecated_member_use
    child: RadioListTile<bool>(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text(geminiChoiceLabel),
      value: true,
      // ignore: deprecated_member_use
      groupValue: selected,
      // ignore: deprecated_member_use
      onChanged: (_) => onSelect(),
    ),
  );
}

/// Under the key field while the Google Gemini row is chosen: where the key
/// comes from, Google's terms, and that saving replaces a server the user
/// runs when one is stored.
class GeminiKeyNotes extends StatelessWidget {
  final bool replacesOwnServer;

  const GeminiKeyNotes({super.key, required this.replacesOwnServer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(geminiKeyHint, style: style),
          const SizedBox(height: 4),
          Text(geminiTermsNote, style: style),
          if (replacesOwnServer) ...[
            const SizedBox(height: 4),
            Text(geminiReplacesOwnServer, style: style),
          ],
        ],
      ),
    );
  }
}

/// The model section for the Google Gemini row: the model and who serves
/// it, as a single curated model is shown, with its measured speed and cost.
class GeminiModelLine extends StatelessWidget {
  final String model;

  const GeminiModelLine({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            s.aiAssistModelLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Text(
          '$model — ${s.aiAssistServedByLabel('Google')}',
          style: theme.textTheme.bodyMedium,
        ),
        if (model == geminiPresetModel)
          Text(
            geminiMeasured,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
