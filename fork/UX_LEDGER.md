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
| 2026-11-01 | 1 | U7 | medium | A8 | Arrange Home | Reorder has no tap path | defer | ReorderableListView gives TalkBack move actions; occasional setting; a fix costs more |
| 2026-11-01 | 1 | U8 | medium | A7 | Plan card, Meal plan | Sections have no headings for screen readers | accept | Planned and Recurring meals are headers |
| 2026-11-01 | 1 | U9 | medium | A1 | Nutrient panel | Reference intake target is 40 dp | defer | Upstream's panel, deliberately compact |
| 2026-11-01 | 1 | U10 | low | - | Nutrient goals | Potassium shows 3400 and 3500 | defer | Upstream default |
| 2026-11-01 | 1 | U11 | low | - | Arrange Home | Reset has no Undo | reject | It resets layout only; nothing is lost |
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
| 2026-11-11 | 1 | U3 | low | A6, H1 | Photo review at 200% | The review scrolls in a short window and the Log button drops the energy | defer | The fixed entry block is an earlier choice (#820); nothing is cut off |
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
| 2026-11-11 | 1 | L2 | low | - | Photo review additions: fat question | Answering for butter adds sunflower oil | reject | The row is ordinary and can be changed; oil is the commoner case |
| 2026-11-11 | 1 | L3 | low | - | Photo review additions: fat question | The oil row lands at the bottom, away from the question | defer | Revisit with use |
| 2026-11-11 | 1 | L4 | low | - | Photo review additions: fat question | None closes the question for good | defer | Revisit with use |
| 2026-11-11 | 1 | L5 | low | - | Photo review additions: note chips | Weighed and Counts open the letter keyboard | reject | The note is free text |
| 2026-11-11 | 1 | I1 | improvement | - | Photo review additions: meal card | The offer, Size and fat question fill the review window | defer | Revisit with use |
| 2026-11-11 | 1 | N1 | low | - | Photo review additions: usual sizes | Deleting a logged photo meal does not unlearn its size | defer | To ask the user |
