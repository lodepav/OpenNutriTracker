# Decision index

One line per decision in [DECISIONS.md](DECISIONS.md), its bold lead sentence. Read the full row
there before changing anything a line touches. After adding or rewording a decision, regenerate:
`fork/tools/decision-index.sh > fork/DECISIONS-INDEX.md`.

- **D1** Base: OpenNutriTracker.
- **D2** Android only, no server of our own.
- **D3** Must-have logging methods:
- **D4** Bring your own AI
- **D5** Testing on the Android emulator
- **D6** Branches.
- **D7** A cheap vision model; the database supplies the numbers.
- **D8** Own app id and name: OpenBite
- **D9** Break a dish down before estimating.
- **D10** Google Drive backup through a sync app; the app only writes backup files
- **D52** What a backup carries is a list, and a new stored key must be on it
- **D53** Log with AI: the meal is a chip, Log can be undone, the photo notice shows once per destination
- **D54** Editing an entry: a tap selects the amount, and a meal's entry opens the dialog at once
- **D11** Generic foods come from open tables bundled into the app as an offline asset. No API key and no backend.
- **D12** Dishes come from recipes, and the AI writes the recipe.
- **D14** Leftovers are subtracted from the logged meal, manually or by AI.
- **D24** A weighed plate's weights are the user's
- **D25** A photo named without an amount gets estimated grams
- **D26** A meal read by the app takes the user's own food only by its name
- **D42** A photo with no note gets estimated grams too
- **D43** Google Gemini as a choice in AI settings
- **D44** A Size on a photo's meal card
- **D45** One amount question and the user's own earlier amounts on a photo's review
- **D46** A photo's amounts sized the way the user usually corrects them
- **D47** Unusual amounts marked on a photo's review: built, measured, removed
- **D48** "Cooked with oil or butter?" on a photo's meal card when the fat is likely and missing
- **D49** Chips that write a photo's note
- **D50** A photo's review takes the screen
- **D51** The model reads one rule per field
- **D13** MacroFactor-style algorithms sit beside upstream's, chosen by a switch.
- **D15** Build everything now; wait for nobody
- **D16** Releases on GitHub, with an in-app updater
- **D17** Expenditure and check-in settings
- **D18** Check-ins after a real journey
- **D19** Activity and start-up after the journey runs
- **D20** A settings change makes a check-in due
- **D21** The daily limit holds for the base too; today's activity waits for the day to end
- **D22** Protein and fat per kg, the rest carbs
- **D23** Whole screens, not patches
- **D27** A break in logging holds the target for a week
- **D28** Go Hevier can read the phase, nothing else
- **D29** Falling strength may suggest a calorie change, and only the user applies it
- **D30** A tap selects on the Diary; Home leads with quick actions
- **D31** Home logs the usual foods in one tap
- **D32** A goal moved by the calendar is said on Home; a window's means count today
- **D33** A food's amount is typed or stepped over unit chips, and the user may name a portion
- **D34** Fat moves with the goal; protein holds
- **D35** Log with AI's review list works as the food page does
- **D36** Log with AI's review list as cards with the meal's macros
- **D37** Log with AI's review reads as the Diary does
- **D38** The review's − [amount] + is on the row; macros are in muted colours everywhere
- **D39** The basket shows its meal; the plus names what it adds
- **D40** A photo's foods are the foods as eaten, at the amounts on the plate
- **D41** Upstream 2.7.0 beside the fork's features
