import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/dbo/user_pal_dbo.dart';
import 'package:opennutritracker/generated/l10n.dart';
// [fork] S592 fork English for stale strings
import 'package:opennutritracker/fork/onboarding/onboarding_copy.dart'
    as fork_copy;
// [/fork]

enum UserPALEntity {
  sedentary,
  lowActive,
  active,
  veryActive;

  factory UserPALEntity.fromUserPALDBO(UserPALDBO palDBO) {
    UserPALEntity palEntity;
    switch (palDBO) {
      case UserPALDBO.sedentary:
        palEntity = UserPALEntity.sedentary;
        break;
      case UserPALDBO.lowActive:
        palEntity = UserPALEntity.lowActive;
        break;
      case UserPALDBO.active:
        palEntity = UserPALEntity.active;
        break;
      case UserPALDBO.veryActive:
        palEntity = UserPALEntity.veryActive;
        break;
    }
    return palEntity;
  }

  String getName(BuildContext context) {
    String name;
    switch (this) {
      case UserPALEntity.sedentary:
        name = S.of(context).palSedentaryLabel;
        break;
      case UserPALEntity.lowActive:
        // [fork] S592 pal-labels: sentence case
        // name = S.of(context).palLowLActiveLabel;
        name = fork_copy.palLowActiveLabel;
        // [/fork]
        break;
      case UserPALEntity.active:
        name = S.of(context).palActiveLabel;
        break;
      case UserPALEntity.veryActive:
        // [fork] S592 pal-labels
        // name = S.of(context).palVeryActiveLabel;
        name = fork_copy.palVeryActiveLabel;
        // [/fork]
        break;
    }
    return name;
  }
}
