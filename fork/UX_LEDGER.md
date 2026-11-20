# UX review ledger

What `/ux-review` decided, so a later review doesn't raise a rejected or
deferred finding again without new evidence. Newest last.

| Date | Round | Id | Severity | Rule | Screens | Claim | Decision | Reason |
|---|---|---|---|---|---|---|---|---|
| 2026-11-01 | 1 | U1 | medium | H1, H3 | Meal plan, plan card | Logging or dropping a planned food gives no message and no Undo | accept | Message names the meal and day, with Undo; checked on screen |
| 2026-11-01 | 1 | U2 | medium | A5 | Plan card, You Daily budget | Macros are spoken as letters | accept | Spoken as grams of carbs, fat and protein |
| 2026-11-01 | 1 | U3 | medium | A2, A10 | Goal planner | Selected card's subtitle has low contrast | accept | Uses onSurface; test fails without it |
| 2026-11-01 | 1 | U4 | medium | H6 | Goal planner | Next is disabled with no reason | accept | "Set the target weight to go on." above the buttons |
| 2026-11-01 | 1 | U5 | medium | H4, C5 | Nutrient goals editor | Editor sets sodium in mg while the rest of the app shows salt in g | accept | Row says what the value is in g of salt |
| 2026-11-01 | 1 | U6 | medium | H4 | You | "Goal: No goal" sits above "Goal: Lose weight" | accept | Row renamed Direction |
| 2026-11-01 | 1 | U7 | medium | A8 | Arrange Home | Reorder has no tap path | defer | ReorderableListView gives TalkBack move actions; occasional setting; a fix costs more. Fixed 2026-11-18 (8618a567): tapping a row's handle offers Move up and Move down |
| 2026-11-01 | 1 | U8 | medium | A7 | Plan card, Meal plan | Sections have no headings for screen readers | accept | Planned and Recurring meals are headers |
| 2026-11-01 | 1 | U9 | medium | A1 | Nutrient panel | Reference intake target is 40 dp | defer | Upstream's panel, deliberately compact. Fixed 2026-11-18 (8618a567, S231): the info button and the view switch are 48 dp |
| 2026-11-01 | 1 | U10 | low | - | Nutrient goals | Potassium shows 3400 and 3500 | defer | Upstream default |
| 2026-11-01 | 1 | U11 | low | - | Arrange Home | Reset has no Undo | reject | It resets layout only; nothing is lost. Undo added anyway 2026-11-18 (8618a567) |
| 2026-11-01 | 1 | U12 | low | - | Plan card | Logging on a future day is unclear | accept | Fixed by U1's message, which names the day |
| 2026-11-01 | 1 | U13 | low | A6 | Goals & nutrition | Expenditure title is cut at 200% text | reject | Only at 200%, and the row names it |
| 2026-11-01 | 1 | U14 | low | C1 | Expenditure settings | The limit sentence is unclear | accept | Reworded |
| 2026-11-01 | 1 | I1 | improvement | H6 | Search while planning | Title does not say you are planning | accept | "Planning lunch" |
| 2026-11-01 | 1 | I2 | improvement | A3 | Plan card | Tooltips do not name the food | accept | "Log X", "Drop X", "Repeat X" |
| 2026-11-01 | 1 | I3 | improvement | H10 | Plan card | Drop on a repeating food does not say it is this day only | accept | "Drop X on this day" |
| 2026-11-01 | 1 | I4 | improvement | H8 | Plan card | Three ways to log | defer | Each has its own scope; revisit with use |
| 2026-11-01 | 1 | I5 | improvement | - | Various | Check-in empty text, repeat dialog line, date format, "fiber", salt bar colour, donut at 200% | reject | Noise, or the fix gives little |
| 2026-11-01 | 2 | U1 | medium | H3, H1, H4 | Search while planning | "Add to plan" does not plan the food, and Back drops it with no warning | accept | "Leave without planning?" on Back; message and bar say "Review to plan it" and "1 to plan" |
| 2026-11-01 | 2 | U2 | medium | H3, H4 | Meal plan | "Stop repeating" on a recurring row deletes with no Undo, where the card's same button keeps the food | accept | That row's button says Remove, with a message and Undo |
| 2026-11-01 | 2 | U3 | low | A7 | Meal plan, plan card | Headings merge with the content below | accept | Round 1's fix was incomplete; container on both headers |
| 2026-11-01 | 2 | L1 | low | C4, A5 | Plan card | Spoken "1 grams fat" | accept | One-line plural |
| 2026-11-01 | 2 | L2 | low | H6 | Goal planner | With a target that will not do, the footer still says to set one | accept | "Change the target weight to go on." |
| 2026-11-01 | 2 | L3 | low | H6 | Meal plan | The Plan foods sheet has no title | reject | Opened straight from Plan foods, and the four meals explain themselves |
| 2026-11-01 | 2 | L4 | low | C5 | Meal plan | "Recurring meals" can hold a single food | reject | The word the user asked for; a food in a meal slot is still that meal |
| 2026-11-01 | 2 | I6 | improvement | H1 | Home Recent foods, plan card | Name the food in log messages | defer | Shared message helper; the row just tapped already shows it |
| 2026-11-01 | 2 | I7 | improvement | H7 | Search while planning | Plan a single food straight from its page | defer | Saves two taps, but is a new path past the amount and basket review |
| 2026-11-11 | 1 | U1 | medium | A4 | Photo review, Size | After "Use your amounts", "As shown" stays ticked and the chips are spoken "times the photo's amounts" | accept | The 1× chip reads "Your amounts" and the others are spoken "times your amounts" until Undo |
| 2026-11-11 | 1 | U2 | low | H3 | Photo review | Undo does not bring back the amount question | reject | One question a read (D45); the stepper remains |
| 2026-11-11 | 1 | U3 | low | A6, H1 | Photo review at 200% | The review scrolls in a short window and the Log button drops the energy | defer | The fixed entry block is an earlier choice (#820); nothing is cut off. Window fixed by D50: the entry block goes while a photo's foods show; the Log button's energy still drops at 2x. Fixed 2026-11-20: above 1.5x text the Log button shows its label and the energy on two lines |
| 2026-11-11 | 1 | U4 | low | A4 | Photo review, meal card | TalkBack reads the Size hint and the day totals before the offer and the chips | accept | The hint and the day totals have their own nodes, after the chips |
| 2026-11-11 | 1 | L1 | low | A1 | Amount question | Rows of chips touch | accept | 8 dp between rows, as the Size chips |
| 2026-11-11 | 1 | L2 | low | A5, H4 | Photo review row | The amount field reads "0.5 × khachapuri" after the "½" chip | reject | The field's format for every amount |
| 2026-11-11 | 1 | L3 | low | - | One-food photo | Size and the question both change the one row | reject | The question is the more precise control |
| 2026-11-11 | 1 | I1 | improvement | H1 | Photo review | Show "Meal now … kcal" on screen as well as speaking it | defer | Matters at 200%, with U3 |
| 2026-11-11 | 1 | I2 | improvement | H6 | Earlier amounts offer | Name the foods the offer changes | defer | Revisit with use |
| 2026-11-11 | 2 | - | - | - | Photo review | No findings; U1, U4 and L1 fixed on screen | - | Open: TalkBack focus after Undo, unseen in a UI dump |
| 2026-11-11 | 1 | U1 | medium | H1 | Photo review additions: Size | A chip's ×0.8 on top of the usual ×0.8 was unseen | accept | Fixed: the hint says sizes change the usual amounts; the whole-meal usual size it also stated was dropped later the same day (D46) |
| 2026-11-11 | 1 | U2 | medium | - | Photo review additions: fat question | The question keyed on the matched name: "without dressing" read as a fat, a fried table food asked again | accept | Fixed: the cooked word comes from the model's row on a plain table food; a fat named as absent is none (D48) |
| 2026-11-11 | 1 | L1 | low | - | Photo review additions: note chips | Opposite chips could stand together | accept | Fixed: Small/Large plate and Restaurant/Home-cooked take each other's words out |
| 2026-11-11 | 1 | L2 | low | - | Photo review additions: fat question | Answering for butter adds sunflower oil | reject | The row is ordinary and can be changed; oil is the commoner case. Changed 2026-11-20 (D48): with an oil or butter row on the read, the answer goes into that row |
| 2026-11-11 | 1 | L3 | low | - | Photo review additions: fat question | The oil row lands at the bottom, away from the question | defer | Revisit with use. Since 2026-11-20 (D48) a read with an oil or butter row gets no new row: the answer goes into that row |
| 2026-11-11 | 1 | L4 | low | - | Photo review additions: fat question | None closes the question for good | defer | Revisit with use |
| 2026-11-11 | 1 | L5 | low | - | Photo review additions: note chips | Weighed and Counts open the letter keyboard | reject | The note is free text |
| 2026-11-11 | 1 | I1 | improvement | - | Photo review additions: meal card | The offer, Size and fat question fill the review window | defer | Revisit with use. Eased by D50: the window now runs from the app bar to Log |
| 2026-11-11 | 1 | N1 | low | - | Photo review additions: usual sizes | Deleting a logged photo meal does not unlearn its size | defer | To ask the user |
| 2026-11-17 | 1 | U1 | medium | A6 | Food page at 200% | The fixed amount panel fills the page, and labels are cut | accept | Above 1.5x text the amount and the meal sit on the page after the food's summary, with only Add and the basket pinned; labels wrap or shrink (fd4451bd) |
| 2026-11-17 | 1 | L1 | low | A3 | Add food results | Add buttons are read with a stray comma before the source | accept | Read "Add Chicken breast, 60 g" |
| 2026-11-17 | 1 | L2 | low | H2 | Food page | The weight unit's chip is a lone "g" | accept | Says Grams |
| 2026-11-17 | 1 | L3 | low | - | Food page | The nutrient table's heading sits outside its card | accept | A fork table (S221): a "Per 100 g" heading in its card, rows read "Fat 21 g" |
| 2026-11-17 | 1 | L4 | low | A6, H4 | Food page at 200% | "Today after adding" does not follow the Diary's totals card | accept | One figure a line above 1.5x, as the Diary's totals |
| 2026-11-17 | 1 | L5 | low | H8 | Add food | Three bare icon buttons in the app bar | accept | One "More ways to add" menu |
| 2026-11-17 | 1 | L6 | low | - | + sheet | Its search looks like a second field to type in | accept | A button into Add food, with the field focused |
| 2026-11-17 | 1 | L7 | low | A5 | Food page | The header is read as one run of lines | accept | The header, a total and a row read as words |
| 2026-11-17 | 1 | L8 | low | H4 | Food page, Today after adding | A target passed shows in the error colour | accept | Not red, as in the Diary |
| 2026-11-18 | 2 | U1 | medium | H4 | Add food results | One list shows "+ 60 g", "+ 1 serving" and a bare +, and a + on a food missing its values opens its page instead of logging | accept | + shows the grams unless the serving is one counted thing; such a food shows "Choose ›" (D67) |
| 2026-11-18 | 2 | L1 | low | H8 | Add food results | A row repeats the source its section's header names | accept | Left out there, kept short elsewhere (D67) |
| 2026-11-18 | 2 | L2 | low | A6 | Add food results at 200% | The add button's wrapped "1 / serving" runs into the button's rounded ends | accept | A rounded rectangle at large text (50d5a13b) |
| 2026-11-18 | 2 | L3 | low | A5 | Food page | The macro split is read in one run | accept | Read one macro at a time (60e2c7df) |
| 2026-11-18 | 2 | L4 | low | - | Food page | The amount card loses its round corners | accept | The sheet is transparent on the amount part (S125) |
| 2026-11-18 | 2 | L5 | low | C5 | Food page | The nutrient table says "Fiber" | accept | "Fibre" |
| 2026-11-18 | 2 | L6 | low | H8 | Add food | More than one magnifier | accept | One (S223) |
| 2026-11-18 | 2 | L7 | low | A6 | Food page at 200% | The source chips do not wrap, and in "Today after adding" a name under its bar reads as the next figure's label | accept | The chips wrap, and each figure's name comes first |
| 2026-11-18 | 2 | U2 | medium | - | Settings | Show AI features sits under Appearance, away from AI meal assistance | accept | Moved to Food databases, beside AI meal assistance (D66) |
| 2026-11-18 | 2 | U3 | medium | H5 | Settings, Data | Clear cached items sits in Start Over, beside the red Reset | accept | Moved to Food databases, as the cache holds food search results (D66) |
| 2026-11-18 | 2 | L8 | low | H8 | Settings, About | The version shows on the index's footer and About's summary as well | accept | On the Updates row and About's footer only (D66) |
| 2026-11-18 | 2 | L9 | low | - | Settings, Goals | The rows are not grouped | accept | Calorie Target, Nutrition, then Diary (D66) |
| 2026-11-18 | 2 | L10 | low | A6 | Settings at 200% | A row's 40 dp icon and a switch leave the words under half the row | accept | Above 1.5x text rows drop their icon (60e2c7df) |
| 2026-11-18 | 2 | L11 | low | A6 | Macro split, Per-meal kcal share | A share lacks its "%", and at large text a "Name N%" breaks apart | accept | Each share carries its "%" and breaks only after a dot (60e2c7df, 50d5a13b) |
| 2026-11-18 | 2 | L12 | low | - | Settings search | Search does not find Show AI features | accept | Matches the start of words and finds it |
| 2026-11-18 | 2 | L13 | low | H4 | Settings, Food | The summary does not use the row names, and names AI while it is hidden | accept | Uses the row names and leaves AI out while hidden |
| 2026-11-18 | 2 | L14 | low | H8 | Settings, Reminders | Headings repeat | accept | Gone |
| 2026-11-18 | 2 | L15 | low | H4 | Settings | Group headings are not in Title Case | accept | Title Case; back to sentence case in the whole-app critique the same day (d78cfebf) |
| 2026-11-18 | 1 | U1 | medium | - | Add audit: Quick add | Closing Quick add closes more than its sheet | accept | Closes only its sheet (audit, 8618a567) |
| 2026-11-18 | 1 | U2 | medium | H3 | Add audit: Undo | The Undo bar goes before a TalkBack user reaches it | accept | Stays up under TalkBack (audit, 8618a567) |
| 2026-11-18 | 1 | L1 | low | - | Add audit: results | The keyboard stays over the results | accept | Results clear the keyboard (audit, 8618a567) |
| 2026-11-18 | 1 | L2 | low | - | Add audit: food page | The food page does not fit a landscape phone | accept | It fits (audit, 8618a567) |
| 2026-11-18 | 1 | L3 | low | A6 | Settings audit: privacy dialog | The dialog does not scroll at 200% | accept | It scrolls (audit, 8618a567) |
| 2026-11-18 | 1 | L4 | low | - | Settings audit: history import | The import reads its files on the UI isolate | accept | Read off the UI isolate (audit, 8618a567) |
| 2026-11-18 | 1 | L5 | low | - | Settings audit: search | A search result does not open at its row | accept | Opens at its row (audit, 8618a567) |
| 2026-11-19 | 1 | U1 | low | H1 | Home Goal tile | After "Mark completed and maintain" Home keeps "Maintain, No end date" while Trends and You say "Maintain since" | accept | Home's tiles also reload on PhaseStore and weigh-in changes, as the goal card and You tile do |
| 2026-11-19 | 1 | L1 | low | C5, H4 | Weight history, Edit | The edit dialog is titled "Add entry" | accept | Titled "Edit weigh-in" when editing |
| 2026-11-19 | 1 | L2 | low | H2 | Goal reached | A goal started and reached the same day reads "1 week" | reject | Edge case; the dates beside it are right |
| 2026-11-19 | 1 | L3 | low | H4 | Planner, step 1 | "-1.0 kg to go" with a hyphen sign, where the tiles say "1.0 kg to go" | accept | Shown without the sign |
| 2026-11-19 | 1 | L4 | low | C3 | Energy balance, 1W | "In surplus: 0 days" | reject | True and short |
| 2026-11-19 | 1 | L5 | low | H2 | Calories, 1Y | "Nov 20 – Nov 19" reads as a backwards range without years | defer | Needs a rule for when a range shows its years |
| 2026-11-19 | 1 | I1 | improvement | H6 | Edit plan after an overshoot | The goal's own target shows red and Save is off; a hint to "Complete or extend" would help | defer | Revisit with use |
| 2026-11-19 | 1 | I2 | improvement | H6 | Extend for more weeks | Extending drops the target without saying so | defer | Revisit with use |
| 2026-11-19 | 1 | I3 | improvement | A3 | Energy balance chart | Its spoken label gives no range, unlike Calories | defer | Revisit with use |
| 2026-11-19 | 2 | - | - | - | Home Goal tile, Weight history Edit, Planner step 1 | U1, L1 and L3 fixed on screen | - | - |
| 2026-11-19 | 2 | L1 | low | H1, H4 | Home Expenditure tile | One weigh-in behind until something else reloads it | defer | Cause unverified (the estimate may be read before it is recomputed); to debug |
| 2026-11-19 | 2 | L2 | low | C5 | Weight history, Weigh in | The Add dialog is titled "Add entry" | accept | Titled "Log a weigh-in", as Home's dialog |
| 2026-11-19 | 2 | I1 | improvement | H5 | Weight history, Weigh in | No warning that it replaces the day's weigh-in, as Home's dialog gives | defer | Revisit with use |
| 2026-11-20 | 1 | U1 | medium | - | Photo review, fat question | The answer adds sunflower oil beside the breakdown's own oil (emulator, 2026-11-19) | accept | Fixed 2026-11-20: the answer goes into the read's own oil or butter row (D48) |
| 2026-11-20 | 1 | L1 | low | - | Photo review row | 51 of 74 home dishes carry their alias lists in the name, cut off on the row (emulator, 2026-11-19) | accept | Fixed 2026-11-20: the row shows a home dish without its list. The amount sheet's title and the usual-sizes line still show the full name |
