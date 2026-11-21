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
| 2026-11-21 | 1 | U1 | medium | H1 | Home, check-in card | A first, goal or settings check-in held by a partly logged day reads "ready to check" and does not go on after the answer | accept | The card says it waits for any check-in and runs it again after the answer |
| 2026-11-21 | 1 | U2 | medium | A2 | Target weight ruler | The package's grey labels (about 2.7:1), blue value and faint red cursor fail contrast; the wheel can rest off the cursor | accept | Theme colours (S285). Resting off the cursor is the package's scroll physics: left as is |
| 2026-11-21 | 1 | U3 | medium | A1 | Log with AI, dictation language | The "EN" button is 40×40 dp and touches the mic button | defer | Upstream's voice input: an upstream PR |
| 2026-11-21 | 1 | L1 | low | H5 | Check-in screen | Accept is live while the partly logged day is unanswered | reject | Accepting by hand is the user's choice; only the automatic one waits |
| 2026-11-21 | 1 | L2 | low | H3 | Check-in screen | Leave out and Keep give no confirmation or Undo | defer | Days left out › Count again undoes it; revisit with use |
| 2026-11-21 | 1 | L3 | low | H4 | Check-in screen | "Keep" (the day) and "Keep current target" share a word; the screen is "Weekly check-in" for a first target | defer | Revisit with use |
| 2026-11-21 | 1 | L4 | low | C5 | Photo review | "This meal · 4 foods", "Meal · 3 foods" and "Log 2 items" on one screen | defer | Revisit with use |
| 2026-11-21 | 1 | L5 | low | H4 | You › Plan | "lb a week" beside the ruler's "lbs" | reject | Upstream's strings |
| 2026-11-21 | 1 | I1 | improvement | H3, H6, H1 | Check-in screen, Home card | Undo after an answer; say which choice the proposal assumes; name the day on the card | defer | Revisit with use |
| 2026-11-21 | 2 | U1 | medium | H1 | Home, check-in card | After a goal change under the "target set" banner, the due check-in neither runs nor shows until the app resumes | accept | Home's rebuild runs the automatic check-in behind the banner too, and dismissing the banner reads what is due |
| 2026-11-21 | 2 | U2 | medium | H1 | Home, 7-day bars | Bars keep old totals after a past day is edited in the Diary | defer | Same cause family as 11-19 L1 (Home not reloaded after a past-day edit): to debug together |
| 2026-11-21 | 2 | L1 | low | A2, A6, H4, H8 | Target weight ruler | Cursor drawn at 30% opacity, labels don't grow at 200%, the centred label opens grey, lb labels nearly touch | reject | The package's drawing; the field below shows the value at full contrast and size |
| 2026-11-21 | C1 | G2-1 | P1 | H3, H5 | Log with AI | Find foods silently discards every correction | accept | Becomes a secondary "Find again" and asks before replacing edited rows (critique G2) |
| 2026-11-21 | C1 | G2-2 | P1 | H5, H6 | Log with AI, Other match | Wrong matches; the candidate list shows no energy | accept | Candidates show their energy; search, a row swap icon and weak-match flags rejected as larger than the gain (critique G2) |
| 2026-11-21 | C1 | G2-3 | P1 | A6 | Fasting | History header overflows at 200% | accept | Fits at 200% (critique G2) |
| 2026-11-21 | C1 | G2-4 | P1 | A3, H1 | Barcode scanner | Torch and camera buttons unlabelled; blank preview | accept | Tooltips and a loading indicator; aiming frame left out (critique G2) |
| 2026-11-21 | C1 | G2-5 | P2 | A8 | Log with AI | Leave out is swipe-only | accept | A visible Leave out button per row (critique G2) |
| 2026-11-21 | C1 | G2-6 | P2 | A6, H8 | Log with AI | Two stacked primaries; little room for rows at 200% | accept in part | Find again is secondary once rows exist; collapsing the entry block deferred (critique G2) |
| 2026-11-21 | C1 | G2-7 | P2 | H1, H9 | Log with AI | "Log 0 items" with no reason | accept | "Check N rows to log" (critique G2) |
| 2026-11-21 | C1 | G2-8 | P2 | H3, C1 | Log water | Reset is ambiguous; "fl.oz" | accept in part | "Clear"; "fl.oz" is upstream's string, pinned by its test (upstream PR candidate); Undo last kept as upstream designed it (critique G2) |
| 2026-11-21 | C1 | G2-9 | P2 | A6, H5 | Custom activity | Black system bars; Add enabled at 0 | accept in part | Scaffold outside SafeArea, Add disabled at 0; hero circle kept (upstream look) (critique G2) |
| 2026-11-21 | C1 | G2-10 | P2 | C1, H2 | Activity picker | Raw lowercase Compendium names; unexplained + | accept in part | Names capitalised in the picker (Home and Diary cards are upstream's ActivityCard, left); + already had a tooltip; MET values not changed without a source check (critique G2) |
| 2026-11-21 | C1 | G2-11 | P2 | C5, H9 | New custom food | "Meal name" on a food; extra confirm; snackbar error | accept in part | "Food name"; confirm and inline errors deferred as upstream's flow (critique G2) |
| 2026-11-21 | C1 | G2-12 | P2 | - | Fasting | Notification permission asked on open | defer | A behaviour change to upstream's fasting; an upstream PR candidate (critique G2) |
| 2026-11-21 | C1 | G2-13-16 | P3 | A1, A2 | Amount sheet, fasting chips, warning links, EN chip | Duplicate portions, weak selected chips, small links, 40 dp chip | defer | Lows; revisit if a later round raises them again (critique G2) |
| 2026-11-21 | C1 | G3-1 | P1 | H9 | Recipe, meal and workout import scanners | A refused camera is a black dead end | accept | Allow camera and Paste a code instead on all three (critique G3) |
| 2026-11-21 | C1 | G3-2 | P1 | H5, H9 | Ingredient amount sheet | An empty amount drops the pick silently; no default, no preview | accept in part | The serving is prefilled and energy shown as typed; Add on an emptied field still closes with nothing, as upstream's test pins (critique G3) |
| 2026-11-21 | C1 | G3-3 | P1 | H3, H5 | Manage profiles | Delete profile is generic and styled like Cancel | accept in part | Names the profile and what goes, Delete in the error colour; type-the-name rejected as more than the risk needs (critique G3) |
| 2026-11-21 | C1 | G3-4 | P2 | H1, H9, H10 | Share dialog, paste dialog, import confirm | Copy feedback hidden, wrong paste hint, a bad code closes the dialog, "OK" | accept in part | "Copied" in the dialog, where-to-scan line, own hints, inline error keeps the text, "Import"; kcal and duplicate warning deferred (critique G3) |
| 2026-11-21 | C1 | G3-5 | P2 | C1, C5, H4 | Recipes, builder, detail | Title Case strings, three ingredient pictures, custom meals/foods, no Copy to profile for recipes | accept in part | One picture resolver for builder and detail; the Title Case and "custom meals" strings are upstream's (PR candidate); Copy to profile deferred (critique G3) |
| 2026-11-21 | C1 | G3-6 | P3 | C4, H5 | Manage profiles, Add profile | "1 days logged"; empty profile name accepted | accept | Singular; create waits for a name (critique G3) |
| 2026-11-21 | C1 | G3-7 | P3 | A6, H1, H9, H6, H8 | Recipes footer at 200%, new profile "— kcal", recipe name error, Duplicate save, Copy to profile wording, Log another amount, unit dropdown, scanner title | Lows | defer | Revisit if raised again (critique G3) |
| 2026-11-21 | C1 | G4-1 | P1 | H1, H2 | Goal progress | "On plan" beside a recent-pace arrival 3 months late | accept | The verdict weighs the recent pace: Too early to tell, Behind, Ahead or On plan (pure, tested) (critique G4) |
| 2026-11-21 | C1 | G4-2 | P2 | H6, H4 | Check-in screen | Title differs from the card; today's goal not shown; "Keep current target" has no number; proposal shown twice | accept | Same title as the card, today's goal line with activity, "Keep N kcal", one place for the proposal (critique G4) |
| 2026-11-21 | C1 | G4-3 | P2 | H8 | Goal progress | 3.5 screens of overlapping figures | accept in part | Empty "Since the start" hidden, Edit plan is the main button; one hero block deferred (critique G4) |
| 2026-11-21 | C1 | G4-4 | P2 | C3 | Phase reports, Completed goals, Goal reached | Day-one zeros, "-0.0", unused legend, "1 week" for a day | accept | Rows wait for data, no negative zero, empty sentence, legend of shown kinds, days under a week (critique G4) |
| 2026-11-21 | C1 | G4-5 | P2 | H6 | Macros dialog | g/kg choices with no grams | accept in part | Live grams line as in the planner; style row and a page instead of a dialog deferred (critique G4) |
| 2026-11-21 | C1 | G4-6 | P3 | H4, H1 | Goal pages | Hyphen and true minus mixed; completing a goal has no acknowledgement | accept | One minus; a snackbar names the completed goal (critique G4) |
| 2026-11-21 | C1 | G4-7 | P3 | H2, H4, A2 | Calendar day sheet, plan grid month label, edited plan timing, completed rows, card placement, button heights, chart labels at 200% | Lows | defer | Revisit if raised again (critique G4) |
| 2026-11-21 | C1 | G5-1 | P1 | A6 | Waist to height, Left and right, Progress photos, Compare photos | At 200% axis labels overlap, the photo strip overflows, titles cut | accept | Axis space from the scaled labels, tiles grow with text, title fits; the BMI page's title is upstream's (critique G5) |
| 2026-11-21 | C1 | G5-2 | P1 | H4 | Nutrients explorer, Nutrient goals | The same averages red on one, green on the other; progress bar spoken first | accept | One shared colour rule and key; bar left out of semantics (critique G5) |
| 2026-11-21 | C1 | G5-3 | P2 | H6 | Body measurements card, Thighs | Waist to height and left vs right unreachable after measuring | accept in part | The card links to them once their data exists; the empty side page can add measurements; showing Trends tiles automatically deferred (critique G5) |
| 2026-11-21 | C1 | G5-4 | P2 | H1, H4 | Body measurements card | Chart without scale or dates; range unnamed; hyphen | accept | First and last values with dates, the range named, true minus (critique G5) |
| 2026-11-21 | C1 | G5-5 | P2 | H9, H5 | Add measurements | Crowded fields; one error far from its field with no range; units hidden | accept | Spaced fields, an error with the range on each field, units from the start (critique G5) |
| 2026-11-21 | C1 | G5-6 | P3 | A1, C3 | Steps card, by-food lists | 32 dp goal button; zero rows | accept in part | Foods that gave nothing left out; the goal button already measures 48 dp in the theme (the 32 dp was a node clipped by the banner) (critique G5) |
| 2026-11-21 | C1 | G5-7 | P3 | H2, A5 | BMI page names and colour-only band, photo date default, viewer, steps chart key, chips at 200% | Lows | defer | BMI page is upstream's; revisit if raised again (critique G5) |
| 2026-11-21 | C1 | G6-1 | P1 | A6 | Export / import | At 200% the overwrite warning runs under the buttons; no Cancel | accept | Scrollable dialog with Cancel (critique G6) |
| 2026-11-21 | C1 | G6-2 | P1 | H3, H5 | Health Connect sync | Weight in, Body fat in, Nutrition out act on one tap without disclosure | accept in part | The Workouts in disclosure on each card before the first sync; Undo after an import deferred (critique G6) |
| 2026-11-21 | C1 | G6-3 | P2 | H4 | Nutrients, Nutrient goals editor, overview | Names, case and potassium default differ | accept in part | Sentence case and one spelling (iron pinned by an upstream test); potassium default from the DRI; other micronutrient defaults and merging the screens deferred (critique G6) |
| 2026-11-21 | C1 | G6-4 | P2 | H10, H2 | Workout calorie credit, Sources | Info lands at the top; title cut at 200%; slider spoken twice | accept in part | Sources opens at the entry; what opt-in sets said before it; one spoken value; the one-line title is pinned by an upstream test, upstream PR candidate (critique G6) |
| 2026-11-21 | C1 | G6-5 | P2 | H2, H9 | AI dialog, AI consent | Address wording for a key, caps button, unnamed features, key wiped on decline, lone Cancel | accept in part | On the Gemini row: key wording, feature names, a Google title; "I understand"; "Key not saved" on decline (upstream test pins the cleared field); Close when unchanged (critique G6) |
| 2026-11-21 | C1 | G6-6 | P2 | A5, A1, A4, A7 | Goal dialog sliders, Macro split, Sources | Sliders speak position; macro fields unlabelled; 32 dp View source; titles not headings | accept | Spoken values, labels, 48 dp, headings (critique G6) |
| 2026-11-21 | C1 | G6-7 | P3 | H4, H2 | Day starts at, Per-meal share, Export wording, Sources intro, OFF account, dark slider tracks, Support unreachable | Lows | defer | Revisit if raised again; Support is upstream's screen, unlinked by the fork's About (critique G6) |
| 2026-11-21 | C1 | G1-1 | P1 | A2, A10 | Onboarding footer | The ready Start/Next label is 2.2:1 light, 1.4:1 dark | accept | The label takes the button's foreground (critique G1) |
| 2026-11-21 | C1 | G1-2 | P1 | H3 | Onboarding | System Back exits and drops every answer | accept | Back goes to the previous page past page 1 (critique G1) |
| 2026-11-21 | C1 | G1-3 | P1 | A3, A1 | Onboarding | Unlabelled checkboxes, back arrow and swatches; small targets | accept | Merged rows, labels, 48 dp (critique G1) |
| 2026-11-21 | C1 | G1-4 | P2 | A2, A6 | Activity level, Personalize | Faint radio rings; "System default" breaks at 200% | accept | 3:1 rings; the segment fits at 200% (critique G1) |
| 2026-11-21 | C1 | G1-5 | P2 | H4, C5 | Onboarding Overview | Macros 1 g off Home; three unit toggle styles; Lose weight vs Lose fat | accept in part | One macro computation; toggles and goal names deferred (critique G1) |
| 2026-11-21 | C1 | G1-6 | P3 | H2, H9, H8 | Onboarding copy, errors, splash, recovery screen theme | Lows | defer | Revisit if raised again (critique G1) |
| 2026-11-21 | C2 | G2-12 | P1 | A9 | Custom activity | Add sits under the 3-button navigation bar (regression from G2-9) | accept | The sheet clears the system inset in both modes (critique G2 r2) |
| 2026-11-21 | C2 | G2-13 | P1 | H3, H8 | Log with AI | The keyboard returns after every sheet or dialog | accept | Focus is dropped again when each one closes (critique G2 r2) |
| 2026-11-21 | C2 | G2-14 | P2 | H4 | Log with AI | Find again still looks like Log (the theme fills tonal buttons) | accept | Outlined button; "edited" instead of "checked" (critique G2 r2) |
| 2026-11-21 | C2 | G2-15 | P2 | H6, H8 | Photo review | Asks to check foods without the photo; three amount controls | accept in part | A thumbnail that opens the photo; folding the amount controls deferred (critique G2 r2) |
| 2026-11-21 | C2 | G2-16 | P2 | H1, H5 | Log water | Undo last is silent and OK re-adds the drink | accept | Undo closes the dialog with a snackbar giving today's total; new evidence beyond C1 (critique G2 r2) |
| 2026-11-21 | C2 | G2-17 | P2 | A6 | Duration sheet, Log water, scanner titles | "3(", titles cut at 200% | accept | No check mark on the chips; titles fit (critique G2 r2) |
| 2026-11-21 | C2 | G2-18 | P3 | H9, A6, H10 | Manual barcode, Custom activity | A bad code loses the digits; description cut; leading 0 | accept | Error in the dialog; description wraps; field text selected or empty (critique G2 r2) |
| 2026-11-21 | C2 | G2-19 | P3 | C5, H4 | Custom food error, End fast dialog, leftovers name, ⇄ icon, steppers, disclosure sheet | Lows | defer | Revisit if raised again (critique G2 r2) |
| 2026-11-21 | C2 | G3-8 | P2 | C2, H4 | Meal paste dialog | Still "Parse" with its own error wording | accept | The meal path uses the shared paste dialog; "Import workout" (critique G3 r2) |
| 2026-11-21 | C2 | G3-9 | P2 | H9, H1 | Paste dialogs | The error stays after the text is fixed, with no next step | accept | Cleared on change; the error says where to copy the code (critique G3 r2) |
| 2026-11-21 | C2 | G3-10 | P2 | H6, H10 | Import scanners | A bare feed; paste is an unlabelled icon | accept | A line saying what to scan and a "Paste a code instead" button (critique G3 r2) |
| 2026-11-21 | C2 | G3-11 | P3 | H6, A3, H1 | Ingredient picker, share QR, recipe builder | No kcal on recent ingredients; QR read as "qr code"; OK on share; stale name snackbar | accept in part | kcal per 100 g, a QR label, the snackbar hidden on the way to the picker; "Done" pinned by an upstream test (critique G3 r2) |
| 2026-11-21 | C2 | G3-12 | P3 | P5, H2, C2 | Food pictures, "since Oct 2026", Total weight 0, prefill without a serving, delete-profile confirm unseen | Lows | defer | Revisit if raised again (critique G3 r2) |
| 2026-11-21 | C2 | G4-8 | P1 | H1, H5 | Check-in | "Change −193 kcal" is measured from the formula base, not today's goal (−443 with activity dropped) | accept | Change from the goal shown today, saying when activity stops counting; parts and total from one rounding (critique G4 r2) |
| 2026-11-21 | C2 | G4-9 | P2 | H1 | Planner, goal plan | The Adaptive target is shown before it is in force | accept | A line saying it starts at the first check-in (critique G4 r2) |
| 2026-11-21 | C2 | G4-10 | P2 | H4 | Goal progress, check-in, Edit plan | Three arrival dates for one goal; Leave asked with no edit | accept | One date function; ask only after a change (critique G4 r2) |
| 2026-11-21 | C2 | G4-11 | P3 | H10, H4 | Plan explainer, planner | The sheet contradicts the editor on when a pace change applies; two deficits for one pace; 7700 switch shows off | accept | Wording matches the code; the Adaptive figure explained; switch shows the value in use; new evidence beyond G4-7 (critique G4 r2) |
| 2026-11-21 | C2 | G4-12 | P3 | H8, A6 | Phase reports, completed goals, macros dialog, milestones | Day-one arrows, no date axis, 200% wraps | defer in part | Day-one arrows and one pace format if cheap; the rest deferred (critique G4 r2) |
| 2026-11-21 | C2 | G5-8 | P2 | H2, H4 | Nutrients explorer, Nutrient goals overview | Green means "a target", not "reached"; Energy over goal shows a full green bar | accept | Colour by standing with "reached" shown; Energy, Carbs and Fat as ±10% bands (Home already says "over" for fat and carbs), Protein a target; full bars reach the end (critique G5 r2) |
| 2026-11-21 | C2 | G5-9 | P2 | H5, H9 | Add measurements | 0-400 cm lets a dropped digit save; errors stay after a fix | accept | Plausible range per metric; errors clear on typing; body fat change in points; chip rows spaced (critique G5 r2) |
| 2026-11-21 | C2 | G5-10 | P2 | H9, H1 | Step goal dialog | Save is silent on 0 | accept | An error with the range (critique G5 r2) |
| 2026-11-21 | C2 | G5-11 | P2 | H8 | Compare photos, photo strip | Pickers at the screen edge, small photos; dates run together at 200% | accept | Gutter, separate pickers, photos fill the page; dates stay in their tiles (critique G5 r2) |
| 2026-11-21 | C2 | G5-12 | P2 | H2, H6 | By-food list, Nutrients explorer | Grams of what; which range | accept | The nutrient named in each line; a dated range line; "average" (critique G5 r2) |
| 2026-11-21 | C2 | G5-13 | P3 | H4, H7 | Two "Nutrient goals" titles, Edit vs Edit goals, single-day chart, photo delete path, entry editing | Lows | defer | Revisit if raised again (critique G5 r2) |
| 2026-11-21 | C2 | G6-8 | P2 | H4, C5 | Nutrient overview, editor, visibility; Health Connect disclosures | Three orders, Salt vs Sodium, two spellings and voices in the disclosures | accept | One ordered list for all three; salt row names sodium; disclosure wording matched; new evidence beyond G6-3 (critique G6 r2) |
| 2026-11-21 | C2 | G6-9 | P2 | H5, H3, H1 | AI assist dialog | Any string saves as a hosted key and AI reads On; Remove key has no undo | accept | The key is checked on OK (offline saves unchecked, said so); Undo after Remove (critique G6 r2) |
| 2026-11-21 | C2 | G6-10 | P2 | H5, C5 | Reset profile data | The shared AI key's removal is buried mid-paragraph | accept | Said first and in the row subtitle; "logged foods"; what reset deletes unchanged (critique G6 r2) |
| 2026-11-21 | C2 | G6-11 | P2 | H5 | Day starts at | A minute on a 70 dp slider; new evidence beyond G6-7 | accept | Quarter-hour choices or a time picker; intro matches (critique G6 r2) |
| 2026-11-21 | C2 | G6-12 | P3 | H4, H6, H2 | Search sources title, OFF dialog, water goal placement, editor unit spacing, hosted AI wording, raw model ids, per-meal rescale note | Lows | defer | Revisit if raised again (critique G6 r2) |
| 2026-11-21 | C2 | G1-8 | P2 | A6 | Other options | Theme control still clips "System default" at 200%; last swatch half cut | accept | G1-4's fix did not hold: rounded-rectangle shape when vertical, end padding on the swatch row (critique G1 r2) |
| 2026-11-21 | C2 | G1-9 | P2 | H9, H5 | About you, Body | Errors never say the range or the reason; height error before inches are typed | accept | Reason and range in the user's unit, inches 0-11, snackbar names the wrong field (critique G1 r2) |
| 2026-11-21 | C2 | G1-10 | P2 | H4, H2, C5 | Healthy range, The equations | lbs vs lb; derivation in cm/kg for an imperial user | accept | The equations shows the user's units with metric in brackets. "lbs" kept: it is upstream's lbsLabel on the whole onboarding page, unit chip included (upstream PR candidate). Overview repeat, "Your TDEE" and lowercase macros are pinned by onboarding_overview_page_body_test, kept (critique G1 r2) |
| 2026-11-21 | C2 | G1-11 | P3 | H2, H3 | Planner from onboarding | Leave dialog talks of a goal that doesn't exist; preset ignores the chosen goal | accept | No dialog when unchanged; first-run wording; start on the chosen goal (critique G1 r2) |
| 2026-11-21 | C2 | G1-12 | P3 | H4, H8 | Overview, The equations | Link and title differ; 1819 kcal twice; TDEE unexplained; lowercase macros | accept | Title matches the link, one total, "daily burn (TDEE)", capitalised macros (critique G1 r2) |
| 2026-11-21 | C2 | G1-13 | P3 | H6, C1, C3 | Intro, Activity, Other options, recovery screen | Lows: stale policy hint, repeated policy label, demo seed spinner, title case, "Personalize", Suggested badge drawn like a chip, gender check over symbol, "contact support" with no link | defer | Revisit if raised again (critique G1 r2) |
