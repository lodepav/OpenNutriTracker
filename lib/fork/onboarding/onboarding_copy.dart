/// The fork's own English for upstream strings that read wrong in OpenBite
/// (G1 sweep): stale, repeated, Title Case, or naming a tab the app calls
/// otherwise. Shown at seams in place of the l10n key.
library;

/// Under Try Demo; the policy part only while it is not accepted.
String tryDemoSubtitle({required bool acceptedPolicy}) => acceptedPolicy
    ? 'Skip setup and explore the app with sample data.'
    : 'Skip setup and explore the app with sample data. Accept the privacy '
          'policy first.';

/// The policy row: the sentence around its link, read once.
const policyLead = 'I have read and accept the ';
const policyLink = 'privacy policy';
const policySentence = '$policyLead$policyLink.';

/// Activity levels, in sentence case as the app's other labels.
const palLowActiveLabel = 'Lightly active';
const palVeryActiveLabel = 'Very active';

/// Each level's example, all four in one form.
const palSedentaryDescription = 'Office job, and mostly sitting in free time';
const palLowActiveDescription =
    'Sitting or standing at work, and light activity in free time';
const palActiveDescription =
    'Mostly standing or walking at work, and active free time';
const palVeryActiveDescription =
    'Mostly walking, running or carrying weight at work, and active free time';

const otherOptionsSubtitle =
    'Personalise the app. You can change all of this later in Settings.';

/// What the daily reminder does, under its switch.
const dailyReminderSubtitle =
    'A reminder once a day to log your meals. Set its time in Settings.';

/// The first-launch disclaimer; the tab is "You", not "Profile".
const disclaimerText =
    'OpenBite is not a medical application. All data provided is not '
    'validated and should be used with caution. Please maintain a healthy '
    'lifestyle and consult a professional if you have any problems. Use '
    'during illness, pregnancy or lactation is not recommended. For the '
    'peer-reviewed sources behind each calculation, tap the info icon on the '
    'Home or You screen.';
