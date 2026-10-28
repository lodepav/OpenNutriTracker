part of 'bulk_add_screen.dart';

/// The bulk-add screen's body for each bloc state: the list, the photo
/// and parse progress, and the messages.
extension _BulkAddBody on _BulkAddScreenState {
  Widget _buildBody(BuildContext context, BulkAddState state) {
    if (state is BulkAddLoadingState) {
      return FutureBuilder<bool>(
        future: _waitsOnOwnServer,
        // The bare spinner until the keystore answers, and for good on the
        // hosted three: they answer in seconds, and #1148 keys the richer
        // state on the one provider whose wait is legitimately long.
        // Keyed by attempt so a Search tapped mid-wait starts the count
        // again for the request now in flight, rather than carrying on
        // from the one it replaced.
        builder: (context, snapshot) => snapshot.data == true
            ? OwnServerWaitIndicator(
                key: ValueKey(state.attempt),
                onCancel: () => _bloc.add(const CancelBulkReadEvent()),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (state is BulkAddErrorState) {
      return _centeredMessage(context, S.of(context).bulkAddSearchFailedLabel);
    }
    if (state is BulkAddPhotoErrorState) {
      return _centeredMessage(
        context,
        switch (state.error) {
          BulkAddPhotoError.unavailable =>
            S.of(context).bulkAddPhotoUnavailableLabel,
          BulkAddPhotoError.auth => S.of(context).bulkAddPhotoKeyRejectedLabel,
          BulkAddPhotoError.transient => S.of(context).bulkAddPhotoFailedLabel,
          BulkAddPhotoError.camera =>
            S.of(context).bulkAddPhotoCameraFailedLabel,
          BulkAddPhotoError.unreadable =>
            S.of(context).bulkAddPhotoUnreadableLabel,
          BulkAddPhotoError.unsupported =>
            S.of(context).bulkAddPhotoUnsupportedLabel,
          BulkAddPhotoError.insecureDestination =>
            S.of(context).bulkAddModelInsecureServerLabel,
          BulkAddPhotoError.billing => S.of(context).bulkAddPhotoNoCreditLabel,
        },
        // #992. Three of these sentences send the user to Settings by name and
        // the fourth is answered there too, but only the *text* path ever
        // carried a way in — the photo path said "check it in Settings" and
        // left the user to find it, which is the hunt #852 already fixed once,
        // in the same dialog, for the same failures.
        // Exhaustive, and deliberately not a `_ => null` default: a ninth photo
        // failure has to say here whether Settings answers it, rather than
        // inheriting silence from a case nobody weighed it against.
        // The four that get nothing point somewhere else, and a Settings button
        // under them would send the user to fix the one thing that is not
        // broken: the camera case is a permission the OS holds, the unreadable
        // case wants a different photograph, the transient case wants the
        // connection or another attempt, and the billing case is settled on the
        // provider's own site — its sentence says so.
        action: switch (state.error) {
          BulkAddPhotoError.unavailable ||
          BulkAddPhotoError.auth ||
          BulkAddPhotoError.unsupported ||
          BulkAddPhotoError.insecureDestination => () => _openAiSettings(
            context,
          ),
          BulkAddPhotoError.transient ||
          BulkAddPhotoError.camera ||
          BulkAddPhotoError.unreadable ||
          BulkAddPhotoError.billing => null,
        },
      );
    }
    if (state is! BulkAddLoadedState) {
      // Scrollable because here the line *is* the body and takes a tight
      // height from the Expanded above: at 2x in German its two rows want
      // 112px more than this region has before anything has been parsed.
      // Scrolling rather than clipping, for the reason #777 settled — the
      // words are the point.
      return SingleChildScrollView(child: _buildModelHint(context));
    }
    if (state.rows.isEmpty) {
      return _withModelHint(
        context,
        _centeredMessage(context, switch (state) {
          // A bad segment explains itself; that outranks either generic line.
          _ when state.parseErrors.isNotEmpty => _parseErrorsText(
            context,
            state.parseErrors,
          ),
          // The model looked at a photograph and reported no food. "Nothing to
          // log yet" is true but reads as though nothing happened, and the
          // notice that would have said a photo was read is not drawn on this
          // branch — so the one screen where the user most needs to know a
          // machine answered was the one screen that never said so.
          _ when state.source == BulkAddReadSource.photo =>
            S.of(context).bulkAddPhotoNoFoodLabel,
          _ => S.of(context).bulkAddNothingToLogLabel,
        }),
      );
    }

    // The list is the labelled surface, not each child — row identifiers
    // would churn every time the row count changes.
    final list = Semantics(
      identifier: 'bulk-add-row-list',
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.rows.length + (state.parseErrors.isEmpty ? 0 : 1),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == state.rows.length) {
            return _buildParseErrors(context, state.parseErrors);
          }
          return _buildRow(context, state, index);
        },
      ),
    );

    // A model failure that will still be true tomorrow gets said out loud,
    // even though the rows below are perfectly usable parser output. The
    // alternative is what a Pixel 6 actually did with a mistyped key: a
    // plausible screen, a silent 401 on every request, and nothing anywhere
    // to suggest the feature was not running.
    final failure = state.modelFailure;
    if (failure != null) {
      return _noticeAbove(
        context,
        list,
        // The icon tracks the text. A key-off glyph beside "you are out of
        // credit" contradicts the sentence next to it, and the whole point
        // of telling these failures apart is not to send someone to fix the
        // one thing that is not broken.
        icon: switch (failure) {
          MealTextModelFailure.auth => Icons.key_off_rounded,
          MealTextModelFailure.unsupported => Icons.block_rounded,
          MealTextModelFailure.billing => Icons.credit_card_off_rounded,
          // Not a network glyph, for the same reason the sentence is not
          // about a network: the connection was fine and the clock ran out.
          MealTextModelFailure.timeout => Icons.timer_off_rounded,
          // A lock, not a broken plug. Nothing failed to connect — the app
          // declined to send in the clear.
          MealTextModelFailure.insecureDestination => Icons.lock_outline,
        },
        text: switch (failure) {
          MealTextModelFailure.auth =>
            S.of(context).bulkAddModelKeyRejectedLabel,
          MealTextModelFailure.unsupported =>
            S.of(context).bulkAddModelUnsupportedLabel,
          MealTextModelFailure.billing =>
            S.of(context).bulkAddModelNoCreditLabel,
          MealTextModelFailure.timeout =>
            S.of(context).bulkAddModelTimedOutLabel,
          MealTextModelFailure.insecureDestination =>
            S.of(context).bulkAddModelInsecureServerLabel,
        },
        // Coloured as a warning, unlike the neutral "read by AI" banner:
        // this one is asking the user to go and change something.
        emphasised: true,
        // #777: the advice used to be the tail of the sentence, and the tail
        // is what a three-line cap ate. It is a control now, so it cannot be
        // truncated at any text scale — and every one of these failures is
        // answered in the same place.
        // #852: which is why it asks for that place by name. Plain Settings
        // opens on Units & Energy and the AI row is four category groups
        // below it, so the recovery from "your server did not answer in
        // time" used to end in a hunt through a long list. The failure kind
        // does not appear here on purpose: the auth, unsupported, billing,
        // timeout and insecure-destination cases are all fixed in this one
        // dialog, so they all ask for the same thing.
        action: () => _openAiSettings(context),
      );
    }

    if (state.source == BulkAddReadSource.parser) return list;

    // Shown above the rows, not inside one. A model read the whole input, so
    // the caution belongs to the batch — and the confirmation step is only
    // meaningful if the user knows what did the reading.
    // The photo wording is stronger on purpose. Reading typed text, the user
    // can compare a row against what they wrote; reading a photograph there
    // is nothing to compare against, and the food itself may be misidentified
    // rather than merely mis-measured.
    final photo = state.source == BulkAddReadSource.photo;
    return _noticeAbove(
      context,
      list,
      icon: photo ? Icons.photo_camera_rounded : Icons.auto_awesome_rounded,
      text: photo
          ? S.of(context).bulkAddReadFromPhotoLabel
          : S.of(context).bulkAddReadByModelLabel,
      // a wrong dish name is the costliest photo error, and a note fixes it
      action: photo && _forkMealPhoto != null ? _rereadPhotoWithNote : null,
      actionLabel: 'Name the dish',
    );
  }

  /// A one-line banner above the rows. The caution belongs to the batch, not
  /// to any single row, so it sits above the list rather than inside it.
  Widget _noticeAbove(
    BuildContext context,
    Widget list, {
    required IconData icon,
    required String text,
    bool emphasised = false,
    VoidCallback? action,
    String? actionLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // The ceiling is a share of what this widget was actually given, not of
    // the screen: the screen includes the app bar and the input above, so a
    // fraction of it overflows the part that is left.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Semantics(
            identifier: 'bulk-add-model-notice',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: emphasised
                  ? scheme.errorContainer
                  : scheme.surfaceContainerHighest,
              // **Bounded, and scrollable rather than clipped.** Dropping the
              // cap on its own overflowed by 317px at 2x on a 320dp screen —
              // the notice sits above the rows in a `Column`, so its height
              // comes straight out of them. A ceiling gives the rows their
              // share back; scrolling is what stops the ceiling becoming a
              // second truncation, which is the bug this is fixing.
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.4,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            icon,
                            size: 16,
                            color: emphasised ? scheme.onErrorContainer : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              text,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: emphasised
                                        ? scheme.onErrorContainer
                                        : null,
                                  ),
                              // **No cap.** There used to be three lines, on the
                              // reasoning that these run long in German. Measured for
                              // #777, every one of them overran it — in English too —
                              // and no cap survives the combination that matters:
                              // German at 2x on a 320dp screen needed twenty lines,
                              // which is when the words are needed most. Now that the
                              // advice is a button, what is left is one sentence: two
                              // or three lines on a handset, up to eight at 2x on the
                              // narrowest screen, and never cut off.
                            ),
                          ),
                        ],
                      ),
                      // **Below the sentence, not beside it.** Sharing the row was
                      // measured first and is worse: a button takes about 120px,
                      // which on a 320dp screen leaves the text 144 and pushes
                      // German at 2x back up to twelve lines. Full width for the
                      // words, the control underneath.
                      if (action != null)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Semantics(
                            identifier: 'bulk-add-notice-action',
                            child: TextButton(
                              onPressed: action,
                              style: TextButton.styleFrom(
                                foregroundColor: emphasised
                                    ? scheme.onErrorContainer
                                    : null,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                actionLabel ?? S.of(context).settingsLabel,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: list),
        ],
      ),
    );
  }

  /// The one place every "change a setting" recovery on this screen goes.
  ///
  /// Shared rather than repeated so the two paths cannot drift: the photo
  /// failures are answered in the same dialog as the text ones, and the whole
  /// point of #852 is that the route carries *which* part of Settings to
  /// open. A second copy of these arguments is a second chance to lose them.
  /// Every route from this screen to the AI dialog, so all of them both
  /// deep-link (#852, #992) and re-resolve on the way back (#992).
  ///
  /// Delegating rather than pushing directly is the whole point: this had
  /// three call sites — the discovery hint, the text failure notice and the
  /// photo failure action — and only the ones that went through
  /// [_openSettings] noticed a provider configured while they were away.
  void _openAiSettings(BuildContext context) => unawaited(
    _openSettings(arguments: const SettingsScreenArguments(openAiAssist: true)),
  );

  /// A message that fills the body, optionally with something to do about it.
  ///
  /// [action] is optional because most callers have nothing to offer: a
  /// failed food search and an empty parse are not fixed anywhere in
  /// particular, so they stay a sentence and nothing else.
  Widget _centeredMessage(
    BuildContext context,
    String message, {
    VoidCallback? action,
  }) => Padding(
    padding: const EdgeInsets.all(24),
    // Scrollable rather than clipped, for the reason #777 settled: this
    // region takes a tight height from the `Expanded` above, and German at 2x
    // on a 320dp screen wants 484px more than it has. A bare `Column` there
    // paints its overflow past the bottom of the screen, and the button is
    // the last thing in it — so the control this change exists to add would
    // have been the first thing to go: in the tree, and untappable. Measured,
    // not assumed; the test pins it.
    child: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (action != null)
              Semantics(
                identifier: 'bulk-add-message-action',
                child: TextButton(
                  onPressed: action,
                  child: Text(S.of(context).settingsLabel),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  /// The parser reports *what* was wrong with *which* item; the sentence is
  /// built here, where there is a `BuildContext` to localize it with. See
  /// #631 — these read in English on every locale until they moved.
  String _parseErrorText(BuildContext context, MealTextParseError error) =>
      switch (error) {
        InvalidFoodNameError() =>
          S.of(context).bulkAddErrorInvalidName(error.itemNumber),
        QuantityTooSmallError() =>
          S.of(context).bulkAddErrorQuantityTooSmall(error.itemNumber),
        // `bound` is non-null here by construction, so there is nothing to
        // fall back to and no chance of telling the user their quantity has
        // to be "0 or less".
        QuantityTooLargeError(:final bound) =>
          S.of(context).bulkAddErrorQuantityTooLarge(error.itemNumber, bound),
      };

  String _parseErrorsText(
    BuildContext context,
    List<MealTextParseError> errors,
  ) => errors.map((e) => _parseErrorText(context, e)).join('\n');

  Widget _buildParseErrors(
    BuildContext context,
    List<MealTextParseError> errors,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Text(
      _parseErrorsText(context, errors),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.error,
      ),
    ),
  );
}
