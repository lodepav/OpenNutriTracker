// Fork cases moved out of test/unit_test/ai_model_catalogue_test.dart (they test the fork's changes).
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/ai_model_catalogue.dart';

void main() {
  group('the default nobody chose', () {
    // `AiCredentialStorage.writeModel` is only ever reached from an explicit
    // tap in the settings dialog, so everyone who saved a key without opening
    // the model list has no stored id and resolves to `.first` on every
    // request. That makes list *order* a behavioural property, not a
    // cosmetic one, and these tests exist because #726 added a model that is
    // a tenth of the default's price and would have been tempting to promote.

    test(
      'adding cheaper OpenAI models did not move the OpenRouter default',
      () {
        // Reordering would send the food photographs of everyone who never
        // opened the picker to a different company, with no interaction, after
        // the photo sheet had named the old one — it interpolates `servedBy`.
        // #688 refused a smaller version of this.
        final unchosen = AiModelCatalogue.resolve(AiProvider.openrouter, null)!;
        expect(unchosen.id, 'anthropic/claude-sonnet-5.5');
        expect(unchosen.servedBy, 'Anthropic');
      },
    );

    test('a stored GPT-5.6 choice moves to its successor, same vendor', () {
      for (final (provider, old, successor) in [
        (AiProvider.openrouter, 'openai/gpt-5.6-luna', 'openai/gpt-6-luna'),
        (AiProvider.openrouter, 'openai/gpt-5.6-terra', 'openai/gpt-6.1-terra'),
        (AiProvider.openai, 'gpt-5.6-luna', 'gpt-6-luna'),
        (AiProvider.openai, 'gpt-5.6-terra', 'gpt-6.1-terra'),
      ]) {
        final model = AiModelCatalogue.resolve(provider, old)!;
        expect(model.id, successor);
        expect(model.servedBy, 'OpenAI');
      }
    });

    test('a retired id falls back rather than 404ing forever', () {
      expect(
        AiModelCatalogue.resolve(AiProvider.openrouter, 'anthropic/gone')!.id,
        'anthropic/claude-sonnet-5.5',
      );
    });
  });

  group('what a row is allowed to say about itself', () {
    test(
      'only the OpenRouter list claims a cheapest, and Haiku 5.5 holds it',
      () {
        // The superlative is safe because no sibling is below Haiku 5.5
        // ($0.10/$0.50) on the prompt or the completion axis; GPT-6 luna
        // ties it. It is only meaningful among
        // siblings, so it must not appear on a list where there is nothing to
        // be cheapest *than*.
        for (final provider in AiProvider.values) {
          final models = AiModelCatalogue.forProvider(provider);
          final cheapest = models.where((m) => m.note == AiModelNote.cheapest);
          if (provider == AiProvider.openrouter) {
            expect(cheapest.single.id, 'anthropic/claude-haiku-5.5');
            expect(models.length, greaterThan(1));
          } else {
            expect(cheapest, isEmpty, reason: provider.name);
          }
        }
      },
    );
  });
}
