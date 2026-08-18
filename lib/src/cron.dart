import 'package:meta/meta.dart';

sealed class CronField {
  /// The raw string representation of the cron field.
  ///
  /// This field is not validated when passed to the constructor, meaning it
  /// should not be trusted directly. Instead, use the [format] method to get a
  /// reconstructed string representation.
  final String raw;

  CronField(this.raw) {
    if (raw.isEmpty) {
      throw ArgumentError.value(raw, "raw", "Cron field cannot be empty.");
    }
  }

  CronField copyWith({String? raw}) => _parse(raw ?? this.raw);

  static CronField _parse(String raw) {
    if (raw.isEmpty) {
      throw ArgumentError.value(raw, "raw", "Cron field cannot be empty.");
    } else if (raw == "*") {
      return CronFieldWildcard(raw);
    } else if (raw.contains(",")) {
      final parts = raw.split(",");
      final fields = parts.map(_parse).toList();
      return CronFieldList(raw, fields);
    } else if (raw.contains("/")) {
      final parts = raw.split("/");
      if (parts.length != 2) {
        throw ArgumentError.value(
          raw,
          "raw",
          "Cron field with step must have exactly one '/' character.",
        );
      }
      final base = _parse(parts[0]);
      final step = int.tryParse(parts[1]);
      if (step == null) {
        throw ArgumentError.value(
          raw,
          "raw",
          "Cron field step must be an integer.",
        );
      }
      return CronFieldStep(raw, base, step);
    } else if (raw.contains("-")) {
      final parts = raw.split("-");
      if (parts.length != 2) {
        throw ArgumentError.value(
          raw,
          "raw",
          "Cron field range must have exactly one '-' character.",
        );
      }
      final start = _parse(parts[0]);
      final end = _parse(parts[1]);
      return CronFieldRange(raw, start, end);
    } else {
      final value = int.tryParse(raw);
      if (value == null) {
        throw ArgumentError.value(
          raw,
          "raw",
          "Cron field value must be an integer.",
        );
      }
      return CronFieldValue(raw, value);
    }
  }

  /// Returns the raw string representation of the cron field.
  ///
  /// This is different to [raw] as it is validated and reconstructed from the
  /// parsed representation of the cron field.
  @mustBeOverridden
  String format() => raw;

  @override
  @mustBeOverridden
  String toString() {
    final buffer = StringBuffer()
      ..write("CronField(")
      ..write("raw: $raw")
      ..write(")");
    return buffer.toString();
  }
}

/// A cron field that represents a list of values.
///
/// This class is used to represent a cron field that contains multiple values,
/// such as "1,2,3" or "1-5,7-9".
///
/// The values can be of any type that extends [CronField].
final class CronFieldList extends CronField {
  final List<CronField> fields;

  CronFieldList(super.raw, this.fields);

  @override
  String format() {
    final buffer = StringBuffer();
    for (var i = 0; i < fields.length; i++) {
      buffer.write(fields[i].format());
      if (i < fields.length - 1) {
        buffer.write(",");
      }
    }
    return buffer.toString();
  }

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronFieldList(")
      ..write("raw: $raw")
      ..write(", fields: $fields")
      ..write(")");
    return buffer.toString();
  }
}

/// A cron field that represents a range of values.
///
/// This class is used to represent a cron field that contains a range of
/// values, such as "1-5" or "10-20".
///
/// The start and end values must be of type [CronFieldValue], and the start
/// value must be less than the end value.
final class CronFieldRange extends CronField {
  final CronField start;
  final CronField end;

  CronFieldRange(super.raw, this.start, this.end)
    : assert(
        start is CronFieldValue && end is CronFieldValue,
        "Cron field range start and end must be values.",
      ),
      assert(
        (start as CronFieldValue).value < (end as CronFieldValue).value,
        "Cron field range start must be less than end.",
      ) {
    if (!(start is CronFieldValue && end is CronFieldValue)) {
      throw ArgumentError.value(
        start,
        "start",
        "Cron field range start and end must be values.",
      );
    } else if (!((start as CronFieldValue).value <
        (end as CronFieldValue).value)) {
      throw ArgumentError.value(
        start,
        "start",
        "Cron field range start must be less than end.",
      );
    }
  }

  @override
  String format() {
    final buffer = StringBuffer()
      ..write(start.format())
      ..write("-")
      ..write(end.format());
    return buffer.toString();
  }

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronFieldRange(")
      ..write("raw: $raw")
      ..write(", start: $start")
      ..write(", end: $end")
      ..write(")");
    return buffer.toString();
  }
}

/// A cron field that represents a step value.
///
/// This class is used to represent a cron field that contains a step value,
/// such as "*/5" or "1-10/2".
///
/// The base value must be of type [CronFieldWildcard] or [CronFieldRange], and
/// the step value must be a positive integer.
final class CronFieldStep extends CronField {
  final CronField base;
  final int step;

  CronFieldStep(super.raw, this.base, this.step)
    : assert(
        base is CronFieldWildcard || base is CronFieldRange,
        "Cron field step base must be a wildcard or a range.",
      ),
      assert(step > 0, "Cron field step must be a positive integer.") {
    if (!(base is CronFieldWildcard || base is CronFieldRange)) {
      throw ArgumentError.value(
        base,
        "base",
        "Cron field step base must be a wildcard or a range.",
      );
    } else if (!(step > 0)) {
      throw ArgumentError.value(
        step,
        "step",
        "Cron field step must be a positive integer.",
      );
    }
  }

  @override
  String format() {
    final buffer = StringBuffer()
      ..write(base.format())
      ..write("/")
      ..write(step);
    return buffer.toString();
  }

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronFieldStep(")
      ..write("raw: $raw")
      ..write(", base: $base")
      ..write(", step: $step")
      ..write(")");
    return buffer.toString();
  }
}

/// A cron field that represents a wildcard value.
///
/// This class is used to represent a cron field that contains a wildcard value,
/// such as "*". The wildcard value matches any value for the field.
final class CronFieldWildcard extends CronField {
  CronFieldWildcard(super.raw);

  @override
  String format() => "*";

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronFieldWildcard(")
      ..write("raw: $raw")
      ..write(")");
    return buffer.toString();
  }
}

final class CronFieldValue extends CronField {
  final int value;

  CronFieldValue(super.raw, this.value)
    : assert(value >= 0, "Cron field value must be non-negative.") {
    if (!(value >= 0)) {
      throw ArgumentError.value(
        value,
        "value",
        "Cron field value must be non-negative.",
      );
    }
  }

  @override
  String format() => value.toString();

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronFieldValue(")
      ..write("raw: $raw")
      ..write(", value: $value")
      ..write(")");
    return buffer.toString();
  }
}

/// A cron expression.
///
/// The cron expression consists of five fields: minute, hour, day of month,
/// month, and day of week. Each field can be a single value, a range of values,
/// a list of values, or a wildcard. The fields are separated by spaces.
class Cron {
  final CronField second;
  final CronField minute;
  final CronField hour;
  final CronField dayOfMonth;
  final CronField month;
  final CronField dayOfWeek;

  Cron({
    required this.second,
    required this.minute,
    required this.hour,
    required this.dayOfMonth,
    required this.month,
    required this.dayOfWeek,
  });

  /// Parses a cron expression string into a [Cron] object.
  ///
  /// {@template com.jhubi1.scheduler.Cron.parse}
  ///
  /// The expression must have 5 or 6 fields, separated by spaces. If the
  /// expression has 5 fields, the seconds field is assumed to be 0.
  ///
  /// {@endtemplate}
  static Cron parse(String expression) {
    var tmp = expression.trim();
    while (tmp.contains("  ")) {
      tmp = tmp.replaceAll("  ", " ");
    }
    final parts = tmp.split(" ");

    if (parts.length != 5 && parts.length != 6) {
      throw ArgumentError.value(
        expression,
        "expression",
        "Cron expression must have 5 or 6 fields.",
      );
    }

    final output = <CronField>[if (parts.length == 5) CronFieldValue("0", 0)];
    for (final part in parts) {
      output.add(CronField._parse(part));
    }

    return Cron(
      second: output[0],
      minute: output[1],
      hour: output[2],
      dayOfMonth: output[3],
      month: output[4],
      dayOfWeek: output[5],
    );
  }

  /// Tries to parse a cron expression string into a [Cron] object.
  ///
  /// {@macro com.jhubi1.scheduler.Cron.parse}
  ///
  /// If the expression is invalid, this method returns null instead of throwing
  /// any errors or exceptions.
  static Cron? tryParse(String expression) {
    try {
      return parse(expression);
      // errors are thrown in function above, so we catch them here and return
      // null instead of throwing an exception
      // ignore: avoid_catching_errors
    } on ArgumentError catch (_) {
      return null;
      // errors are thrown in function above, so we catch them here and return
      // null instead of throwing an exception
      // ignore: avoid_catching_errors
    } on AssertionError catch (_) {
      return null;
    } on Exception catch (_) {
      return null;
    }
  }

  /// Returns the next time this cron expression matches, strictly after
  /// [from], together with the [Duration] until it occurs.
  ///
  /// The result preserves whether [from] is in UTC or local time.
  ///
  /// If the expression can never match (e.g. day 31 of February), a[StateError]
  /// is thrown after searching through [maxYearsToSearch] years.
  ({DateTime next, Duration isIn}) next(
    DateTime from, {
    int maxYearsToSearch = 5,
  }) {
    final utc = from.isUtc;
    DateTime make(
      int year,
      int month,
      int day, [
      int hour = 0,
      int minute = 0,
      int second = 0,
    ]) => utc
        ? DateTime.utc(year, month, day, hour, minute, second)
        : DateTime(year, month, day, hour, minute, second);

    var candidate = make(
      from.year,
      from.month,
      from.day,
      from.hour,
      from.minute,
      from.second,
    ).add(const Duration(seconds: 1));

    // some expressions (e.g. day 31 of February) can never match, so bound
    // the search instead of looping forever
    final searchLimit = make(
      from.year + maxYearsToSearch,
      from.month,
      from.day,
    );

    while (candidate.isBefore(searchLimit)) {
      if (!_matches(month, candidate.month, min: 1)) {
        final nextMonth = candidate.month == 12 ? 1 : candidate.month + 1;
        final nextYear = candidate.month == 12
            ? candidate.year + 1
            : candidate.year;
        candidate = make(nextYear, nextMonth, 1);
        continue;
      }
      if (!_dayMatches(candidate)) {
        candidate = make(
          candidate.year,
          candidate.month,
          candidate.day,
        ).add(const Duration(days: 1));
        continue;
      }
      if (!_matches(hour, candidate.hour, min: 0)) {
        candidate = make(
          candidate.year,
          candidate.month,
          candidate.day,
          candidate.hour,
        ).add(const Duration(hours: 1));
        continue;
      }
      if (!_matches(minute, candidate.minute, min: 0)) {
        candidate = make(
          candidate.year,
          candidate.month,
          candidate.day,
          candidate.hour,
          candidate.minute,
        ).add(const Duration(minutes: 1));
        continue;
      }
      if (!_matches(second, candidate.second, min: 0)) {
        candidate = candidate.add(const Duration(seconds: 1));
        continue;
      }
      return (next: candidate, isIn: candidate.difference(from));
    }

    throw StateError(
      "No matching date found for cron expression '${format()}' within the search limit.",
    );
  }

  bool _dayMatches(DateTime dt) {
    final domIsWildcard = dayOfMonth is CronFieldWildcard;
    final dowIsWildcard = dayOfWeek is CronFieldWildcard;
    if (domIsWildcard && dowIsWildcard) return true;

    final domMatches = _matches(dayOfMonth, dt.day, min: 1);
    final dowMatches = _matches(dayOfWeek, dt.weekday % 7, min: 0);
    if (domIsWildcard) return dowMatches;
    if (dowIsWildcard) return domMatches;
    return domMatches || dowMatches;
  }

  static bool _matches(CronField field, int value, {required int min}) {
    switch (field) {
      case CronFieldWildcard():
        return true;
      case CronFieldValue(value: final fieldValue):
        return fieldValue == value;
      case CronFieldList(:final fields):
        return fields.any((f) => _matches(f, value, min: min));
      case CronFieldRange(:final start, :final end):
        final s = (start as CronFieldValue).value;
        final e = (end as CronFieldValue).value;
        return value >= s && value <= e;
      case CronFieldStep(:final base, :final step):
        final int baseMin;
        int? baseMax;
        switch (base) {
          case CronFieldWildcard():
            baseMin = min;
          case CronFieldRange(:final start, :final end):
            baseMin = (start as CronFieldValue).value;
            baseMax = (end as CronFieldValue).value;
          default:
            return false;
        }
        if (value < baseMin || (baseMax != null && value > baseMax)) {
          return false;
        }
        return (value - baseMin) % step == 0;
    }
  }

  Cron copyWith({
    CronField? second,
    CronField? minute,
    CronField? hour,
    CronField? dayOfMonth,
    CronField? month,
    CronField? dayOfWeek,
  }) => Cron(
    second: second ?? this.second,
    minute: minute ?? this.minute,
    hour: hour ?? this.hour,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    month: month ?? this.month,
    dayOfWeek: dayOfWeek ?? this.dayOfWeek,
  );

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("Cron(")
      ..write("second: $second")
      ..write(", minute: $minute")
      ..write(", hour: $hour")
      ..write(", dayOfMonth: $dayOfMonth")
      ..write(", month: $month")
      ..write(", dayOfWeek: $dayOfWeek")
      ..write(")");
    return buffer.toString();
  }

  /// Returns the raw string representation of the cron expression.
  ///
  /// This will always include the seconds field, even if it was not provided in
  /// the original expression. If the seconds field was not provided, it will be
  /// set to 0.
  String format() {
    final buffer = StringBuffer()
      ..write(second.format())
      ..write(" ")
      ..write(minute.format())
      ..write(" ")
      ..write(hour.format())
      ..write(" ")
      ..write(dayOfMonth.format())
      ..write(" ")
      ..write(month.format())
      ..write(" ")
      ..write(dayOfWeek.format());
    return buffer.toString();
  }

  /// Returns a pretty, human readable string representation of the cron
  /// expression.
  ///
  /// The [l10n] parameter can be used to provide localization for the output
  /// strings, with English being the default.
  ///
  /// The first day of the week (0) is Sunday, and the last day of the week (6)
  /// is Saturday, this uses the standard cron format.
  String toPrettyString({CronPrettyStringL10n? l10n}) {
    final lang = l10n ?? CronPrettyStringL10n.english;

    String listFormat(List<String> values) {
      if (values.isEmpty) {
        return "";
      } else if (values.length == 1) {
        return values.first;
      } else if (values.length == 2) {
        return "${values.first} ${lang.and} ${values.last}";
      } else {
        final last = values.removeLast();
        final oxfordComma =
            !lang.andOxfordComma || int.tryParse(values.last) != null
            ? ""
            : ",";
        return "${values.join(", ")}$oxfordComma ${lang.and} $last";
      }
    }

    String format(
      CronField value, {
      bool sub = false,
      String? prefix,
      bool ofPrefix = false,
      bool onPrefix = false,
      required CronUnitKind unit,
      bool unitOnFirst = true,
      bool connectsToLast = true,
      bool zeroHides = false,
      bool wildcardHides = true,
      String Function(int value)? valueFormatter,
    }) {
      final unitName = lang.unitName(unit);
      final parts = <String>[];
      String subFormat(CronField value) => format(
        value,
        sub: true,
        prefix: prefix,
        ofPrefix: ofPrefix,
        onPrefix: onPrefix,
        unit: unit,
        unitOnFirst: unitOnFirst,
        connectsToLast: false,
        wildcardHides: wildcardHides,
        valueFormatter: valueFormatter,
      );

      if (!sub) {
        if (ofPrefix) {
          parts.add(lang.of(unit));
        } else if (prefix != null) {
          parts.add(prefix);
        }
        if (unitOnFirst &&
            (value is CronFieldValue ||
                (value is CronFieldList &&
                    value.fields.firstOrNull is CronFieldValue))) {
          parts.add(unitName);
        }
      }

      var usedEvery = false;

      switch (value) {
        case CronFieldValue(:final value):
          if (zeroHides && value == 0) return "";
          parts.add(valueFormatter?.call(value) ?? value.toString());
        case CronFieldList(:final fields):
          parts.add(listFormat(fields.map(subFormat).toList()));
        case CronFieldRange(:final start, :final end):
          var suffix = "";
          if (!(unit == CronUnitKind.dayOfWeek &&
              start is CronFieldValue &&
              end is CronFieldValue &&
              start.value == 0 &&
              end.value == 6)) {
            suffix =
                " ${lang.from} ${subFormat(start)} ${lang.through} ${subFormat(end)}";
          }
          parts.add("${lang.every(unit)} $unitName$suffix");
          usedEvery = true;
        case CronFieldStep(:final base, :final step):
          if (step == 1) {
            parts.add(subFormat(base));
          } else {
            parts.add(
              "${lang.every(unit)} ${lang.ordinalFormatter.call(step)} $unitName",
            );
            usedEvery = true;
            if (base is CronFieldRange &&
                !(unit == CronUnitKind.dayOfWeek &&
                    base.start is CronFieldValue &&
                    base.end is CronFieldValue &&
                    (base.start as CronFieldValue).value == 0 &&
                    (base.end as CronFieldValue).value == 6)) {
              parts.add(
                "${lang.from} ${subFormat(base.start)} ${lang.through} ${subFormat(base.end)}",
              );
            }
          }
        case CronFieldWildcard():
          if (wildcardHides) {
            return "";
          } else {
            parts.add("${lang.every(unit)} $unitName");
            usedEvery = true;
          }
      }

      if (!sub && onPrefix) {
        parts.insert(0, lang.on(usedEvery));
      }

      return "${connectsToLast ? " " : ""}${parts.join(" ")}";
    }

    final dayOfMonthFormatted = format(
      dayOfMonth,
      onPrefix: true,
      unit: CronUnitKind.dayOfMonth,
    );
    final dayOfWeekFormatted = format(
      dayOfWeek,
      unitOnFirst: false,
      onPrefix: true,
      unit: CronUnitKind.dayOfWeek,
      valueFormatter: (value) => value >= 0 && value < lang.weekdays.length
          ? lang.weekdays[value]
          : value.toString(),
    );

    final secondIsZero =
        second is CronFieldValue && (second as CronFieldValue).value == 0;
    final buffer = StringBuffer()
      ..write(lang.at)
      ..write(
        format(
          second,
          unit: CronUnitKind.second,
          zeroHides: true,
          wildcardHides: false,
        ),
      )
      ..write(
        format(minute, ofPrefix: !secondIsZero, unit: CronUnitKind.minute),
      )
      ..write(format(hour, prefix: lang.past, unit: CronUnitKind.hour))
      ..write(dayOfMonthFormatted)
      ..write(
        dayOfMonthFormatted.isNotEmpty && dayOfWeekFormatted.isNotEmpty
            ? " ${lang.and}"
            : "",
      )
      ..write(dayOfWeekFormatted)
      ..write(
        format(
          month,
          unitOnFirst: false,
          prefix: lang.$in,
          unit: CronUnitKind.month,
          valueFormatter: (value) => value >= 1 && value <= lang.months.length
              ? lang.months[value - 1]
              : value.toString(),
        ),
      )
      ..write(".");

    return buffer.toString();
  }
}

/// The kind of field a piece of a cron expression represents.
///
/// Used by [CronPrettyStringL10n] callbacks to pick the correct grammatical
/// form for a unit without relying on comparing translated strings.
enum CronUnitKind { second, minute, hour, dayOfMonth, month, dayOfWeek }

/// Localization for the pretty string representation of a cron expression.
class CronPrettyStringL10n {
  final bool andOxfordComma;
  final String and;

  final String at;
  final String from;
  final String through;
  final String Function(CronUnitKind unit) every;
  final String Function(CronUnitKind unit) of;
  final String past;
  final String Function(bool isEvery) on;
  final String $in;

  /// Weekday names starting at Sunday (index 0) through Saturday (index 6),
  /// matching the standard cron day-of-week numbering.
  final List<String> weekdays;

  /// Month names starting at January (index 0) through December (index 11).
  final List<String> months;

  final String second;
  final String minute;
  final String hour;
  final String dayOfMonth;
  final String month;
  final String dayOfWeek;

  final String Function(int step) ordinalFormatter;

  const CronPrettyStringL10n({
    required this.andOxfordComma,
    required this.and,
    required this.at,
    required this.from,
    required this.through,
    required this.every,
    required this.of,
    required this.past,
    required this.on,
    required this.$in,
    required this.weekdays,
    required this.months,
    required this.second,
    required this.minute,
    required this.hour,
    required this.dayOfMonth,
    required this.month,
    required this.dayOfWeek,
    required this.ordinalFormatter,
  }) : assert(weekdays.length == 7, "weekdays must have exactly 7 entries."),
       assert(months.length == 12, "months must have exactly 12 entries.");

  /// Returns the display name for the given [kind] of field.
  String unitName(CronUnitKind kind) => switch (kind) {
    CronUnitKind.second => second,
    CronUnitKind.minute => minute,
    CronUnitKind.hour => hour,
    CronUnitKind.dayOfMonth => dayOfMonth,
    CronUnitKind.month => month,
    CronUnitKind.dayOfWeek => dayOfWeek,
  };

  static final english = CronPrettyStringL10n(
    andOxfordComma: true,
    and: "and",
    at: "At",
    from: "from",
    through: "through",
    every: (_) => "every",
    of: (_) => "of",
    past: "past",
    on: (_) => "on",
    $in: "in",
    weekdays: [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
    ],
    months: [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ],
    second: "second",
    minute: "minute",
    hour: "hour",
    dayOfMonth: "day of the month",
    month: "month",
    dayOfWeek: "day of the week",
    ordinalFormatter: (step) => switch (step) {
      1 => "${step}st",
      2 => "${step}nd",
      3 => "${step}rd",
      _ => "${step}th",
    },
  );

  static final german = CronPrettyStringL10n(
    andOxfordComma: false,
    and: "und",
    at: "In",
    from: "von",
    through: "bis",
    every: (unit) => switch (unit) {
      CronUnitKind.second => "jeder",
      CronUnitKind.minute => "jeder",
      CronUnitKind.hour => "jeder",
      CronUnitKind.dayOfMonth => "jedem",
      CronUnitKind.month => "jedem",
      CronUnitKind.dayOfWeek => "jedem",
    },
    of: (unit) => switch (unit) {
      CronUnitKind.second => "der",
      CronUnitKind.minute => "der",
      CronUnitKind.hour => "der",
      CronUnitKind.dayOfMonth => "des",
      CronUnitKind.month => "des",
      CronUnitKind.dayOfWeek => "des",
    },
    past: "nach",
    on: (isEvery) => isEvery ? "an" : "am",
    $in: "im",
    weekdays: [
      "Sonntag",
      "Montag",
      "Dienstag",
      "Mittwoch",
      "Donnerstag",
      "Freitag",
      "Samstag",
    ],
    months: [
      "Januar",
      "Februar",
      "März",
      "April",
      "Mai",
      "Juni",
      "Juli",
      "August",
      "September",
      "Oktober",
      "November",
      "Dezember",
    ],
    second: "Sekunde",
    minute: "Minute",
    hour: "Stunde",
    dayOfMonth: "Monatstag",
    month: "Monat",
    dayOfWeek: "Wochentag",
    ordinalFormatter: (step) => "$step.",
  );
}

void main(List<String> args) {
  final cron = Cron.parse("*/20 15,45 8-18/3 5 1,6,10 1-5");
  print(cron.toPrettyString());
  print(cron.next(DateTime.now()));
}
