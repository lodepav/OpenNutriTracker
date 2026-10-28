/// How each listed model did in the phase 4 live eval, and its price tier,
/// in words for the settings screen's model rows (S174), by the model's id.
///
/// From the run of 2026-10-28 over the app's own read and breakdown path:
/// typed meals within 25% of the reference (English, Latvian), photos with
/// the dish named, and counts right.
///
/// | Model | Typed en | Typed lv | Dish named | Count right |
/// |---|---|---|---|---|
/// | Sonnet 5.5 | 17/24 | 8/13 | 60/65 | 18/20 |
/// | GPT-6 luna | 14/24 | 8/13 | 50/65 | 14/20 |
/// | GPT-6.1 terra | 12/24 | 6/13 | 52/65 | 17/20 |
/// | Haiku 5.5 | 12/24 | 6/13 | 57/65 | 14/20 |
///
/// The cost words follow OpenRouter's price per million tokens, input and
/// output: low for $0.10/$0.50 (Haiku 5.5, GPT-6 luna), medium for $1/$5
/// (GPT-6.1 terra), high for $2/$10 (Sonnet 5.5). A model not listed here
/// shows no rating.
const modelRatings = <String, String>{
  'anthropic/claude-sonnet-5.5': 'Best accuracy · High cost',
  'anthropic/claude-haiku-5.5': _haiku,
  'claude-haiku-5-5': _haiku,
  'openai/gpt-6-luna': _luna,
  'gpt-6-luna': _luna,
  'openai/gpt-6.1-terra': _terra,
  'gpt-6.1-terra': _terra,
};

const _haiku = 'Good accuracy · Low cost';
const _luna = 'Good accuracy · Low cost';
const _terra = 'Good accuracy · Medium cost';
