import 'package:meta/meta.dart';

enum _CronFieldType {
  second(0, 59),
  minute(0, 59),
  hour(0, 23),
  dayOfMonth(1, 31),
  month(1, 12),
  dayOfWeek(0, 6);

  final int min;
  final int max;

  const _CronFieldType(this.min, this.max);
}

/// A single field of a cron expression.
sealed class CronField {
  static CronField _parse(String raw, _CronFieldType? type) {
    if (raw.isEmpty) {
      throw ArgumentError.value(raw, "raw", "Cron field cannot be empty");
    } else if (raw == "*") {
      return CronFieldWildcard();
    } else if (raw.contains(",")) {
      final parts = raw.split(",");
      final fields = parts.map((p) => _parse(p, type)).toList();
      return CronFieldList(fields);
    } else if (raw.contains("/")) {
      final parts = raw.split("/");
      if (parts.length != 2) {
        throw ArgumentError.value(
          raw,
          "raw",
          "Cron field with step must have exactly one '/' character",
        );
      }

      var base = _parse(parts[0], type);
      if (base is CronFieldValue && type != null) {
        base = CronFieldRange(base, CronFieldValue(type.max));
      }

      final step = int.tryParse(parts[1]);
      if (step == null) {
        throw ArgumentError.value(
          raw,
          "raw",
          "Cron field step must be an integer",
        );
      }
      return CronFieldStep(base, step);
    } else if (raw.contains("-")) {
      final parts = raw.split("-");
      if (parts.length != 2) {
        throw ArgumentError.value(
          raw,
          "raw",
          "Cron field range must have exactly one '-' character",
        );
      }
      final start = _parse(parts[0], type);
      final end = _parse(parts[1], type);
      return CronFieldRange(start, end);
    } else {
      var value = int.tryParse(raw);
      if (value == null) {
        if (type == .month) {
          value = {
            "jan": 1,
            "feb": 2,
            "mar": 3,
            "apr": 4,
            "may": 5,
            "jun": 6,
            "jul": 7,
            "aug": 8,
            "sep": 9,
            "oct": 10,
            "nov": 11,
            "dec": 12,
          }[raw.toLowerCase()];
        } else if (type == .dayOfWeek) {
          value = {
            "sun": 0,
            "mon": 1,
            "tue": 2,
            "wed": 3,
            "thu": 4,
            "fri": 5,
            "sat": 6,
          }[raw.toLowerCase()];
        }
        if ((type == .dayOfMonth || type == .dayOfWeek) &&
            raw.toLowerCase() == "?") {
          return CronFieldWildcard();
        }
        if (value == null) {
          throw ArgumentError.value(
            raw,
            "raw",
            "Cron field value must be an integer",
          );
        }
      }

      if (type == .dayOfWeek && value == 7) {
        value = 0; // Sunday can be represented as 0 or 7
      }
      if (type != null && (value < type.min || value > type.max)) {
        throw ArgumentError.value(
          value,
          "raw",
          "Cron field value of type '${type.name}' must be between ${type.min} and ${type.max}",
        );
      }
      return CronFieldValue(value);
    }
  }

  bool _validateSizeOfValues(_CronFieldType type);

  /// Returns the raw string representation of the cron field.
  ///
  /// This is different to [raw] as it is validated and reconstructed from the
  /// parsed representation of the cron field.
  @mustBeOverridden
  String format();

  /// Create a copy of the current [CronField] with the given [raw] string.
  CronField copyWith();

  @override
  @mustBeOverridden
  String toString() {
    final buffer = StringBuffer()
      ..write("CronField(")
      ..write(")");
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CronField &&
          runtimeType == other.runtimeType &&
          format() == other.format();

  @override
  int get hashCode => format().hashCode;
}

/// A cron field that represents a list of values.
///
/// This class is used to represent a cron field that contains multiple values,
/// such as "1,2,3" or "1-5,7-9".
///
/// The values can be of any type that extends [CronField].
final class CronFieldList extends CronField {
  final List<CronField> fields;

  CronFieldList(this.fields);

  @override
  bool _validateSizeOfValues(_CronFieldType type) {
    for (final field in fields) {
      field._validateSizeOfValues(type);
    }
    return true;
  }

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
  CronFieldList copyWith({List<CronField>? fields}) =>
      CronFieldList(fields ?? this.fields);

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronFieldList(")
      ..write("fields: $fields")
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

  CronFieldRange(this.start, this.end) {
    if (start is! CronFieldValue || end is! CronFieldValue) {
      throw ArgumentError.value(
        start.toString(),
        "start",
        "Cron field range start and end must be values",
      );
    } else if ((start as CronFieldValue).value >
        (end as CronFieldValue).value) {
      throw ArgumentError.value(
        start.toString(),
        "start",
        "Cron field range start must be less than end",
      );
    }
  }

  @override
  bool _validateSizeOfValues(_CronFieldType type) {
    start._validateSizeOfValues(type);
    end._validateSizeOfValues(type);
    return true;
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
  CronFieldRange copyWith({CronField? start, CronField? end}) =>
      CronFieldRange(start ?? this.start, end ?? this.end);

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronFieldRange(")
      ..write("start: $start")
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

  CronFieldStep(this.base, this.step) {
    if (base is! CronFieldWildcard && base is! CronFieldRange) {
      throw ArgumentError.value(
        base.toString(),
        "base",
        "Cron field step base must be a wildcard or a range",
      );
    } else if (step <= 0) {
      throw ArgumentError.value(
        step,
        "step",
        "Cron field step must be a positive integer",
      );
    }
  }

  @override
  bool _validateSizeOfValues(_CronFieldType type) {
    base._validateSizeOfValues(type);
    return true;
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
  CronFieldStep copyWith({CronField? base, int? step}) =>
      CronFieldStep(base ?? this.base, step ?? this.step);

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronFieldStep(")
      ..write("base: $base")
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
  @override
  bool _validateSizeOfValues(_CronFieldType type) => true;

  @override
  String format() => "*";

  @override
  CronFieldWildcard copyWith() => CronFieldWildcard();

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronFieldWildcard(")
      ..write(")");
    return buffer.toString();
  }
}

/// A cron field that represents a single value.
final class CronFieldValue extends CronField {
  final int value;

  CronFieldValue(this.value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        "value",
        "Cron field value must be non-negative",
      );
    }
  }

  @override
  bool _validateSizeOfValues(_CronFieldType type) =>
      value >= type.min && value <= type.max
      ? true
      : throw ArgumentError.value(
          value,
          "value",
          "Cron field value of type '${type.name}' must be between ${type.min} and ${type.max}",
        );

  @override
  String format() => value.toString();

  @override
  CronFieldValue copyWith({int? value}) => CronFieldValue(value ?? this.value);

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("CronFieldValue(")
      ..write("value: $value")
      ..write(")");
    return buffer.toString();
  }
}

/// A cron expression.
///
/// The cron expression consists of six fields: seconds, minute, hour, day of
/// month, month, and day of week. Each field is a [CronField].
///
/// See [parse] for details on the supported input syntax.
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
  }) {
    second._validateSizeOfValues(.second);
    minute._validateSizeOfValues(.minute);
    hour._validateSizeOfValues(.hour);
    dayOfMonth._validateSizeOfValues(.dayOfMonth);
    month._validateSizeOfValues(.month);
    dayOfWeek._validateSizeOfValues(.dayOfWeek);
  }

  /// Parses a cron expression string into a [Cron] object.
  ///
  /// {@template com.jhubi1.scheduler.Cron.parse}
  ///
  /// The expression must have 5 or 6 fields, separated by spaces. If the
  /// expression has 5 fields, the seconds field is assumed to be 0.
  ///
  /// Each field can be a single value, a range of values, a list of values, a
  /// step value, or a wildcard. The supported syntax is as follows:
  ///
  /// - `*` - matches any value
  /// - `[i]` - matches a single value
  /// - `[i]-[i]` - matches a range of values
  /// - `[i],[i]` - matches a list of values
  /// - `[i]/[s]` - matches a step value, `s` being an integer not a [CronField]
  /// - `?` is supported for compatibility, but is treated as a wildcard
  ///
  /// The values can be between the following ranges:
  ///
  /// - Seconds: 0-59
  /// - Minutes: 0-59
  /// - Hours: 0-23
  /// - Day of Month: 1-31
  /// - Month: 1-12 or JAN-DEC
  /// - Day of Week: 0-7 (0 and 7 are Sunday, others are 1 to 6) or SUN-SAT
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
        "Cron expression must have 5 or 6 fields",
      );
    }

    final output = <CronField>[if (parts.length != 6) CronFieldValue(0)];
    for (final part in parts) {
      output.add(CronField._parse(part, .values[output.length]));
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
  /// If the expression is invalid, this method returns null instead of throwing
  /// any errors or exceptions.
  ///
  /// {@macro com.jhubi1.scheduler.Cron.parse}
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
  ///
  /// The function works for both UTC and local DateTime objects, and will
  /// return a DateTime object in the same timezone as [from].
  ({DateTime next, Duration delay}) next(
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
      return (next: candidate, delay: candidate.difference(from));
    }

    throw SchedulerOutOfReachException(
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
          prefix: lang.inWord,
          unit: CronUnitKind.month,
          valueFormatter: (value) => value >= 1 && value <= lang.months.length
              ? lang.months[value - 1]
              : value.toString(),
        ),
      )
      ..write(".");

    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Cron &&
          runtimeType == other.runtimeType &&
          second == other.second &&
          minute == other.minute &&
          hour == other.hour &&
          dayOfMonth == other.dayOfMonth &&
          month == other.month &&
          dayOfWeek == other.dayOfWeek;

  @override
  int get hashCode =>
      Object.hash(second, minute, hour, dayOfMonth, month, dayOfWeek);
}

/// Exception thrown when the scheduler is unable to find a matching date
/// for a cron expression within the search limit.
final class SchedulerOutOfReachException implements Exception {
  final String message;
  SchedulerOutOfReachException(this.message);

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write("SchedulerOutOfReachException(")
      ..write("message: $message")
      ..write(")");
    return buffer.toString();
  }
}

/// The kind of field a piece of a cron expression represents.
///
/// Used as the key for [CronPrettyStringL10n]'s per-unit lookups to pick the
/// correct grammatical form for a unit without relying on comparing translated
/// strings.
enum CronUnitKind { second, minute, hour, dayOfMonth, month, dayOfWeek }

/// Localization for the pretty string representation of a cron expression.
///
/// Every per-unit lookup ([every], [of] and the unit names themselves) is
/// backed by a [Map] keyed by [CronUnitKind], validated at construction time to
/// contain an entry for every unit. This keeps translations declarative (no
/// manually written `switch` per language) while still failing fast, with a
/// clear message, if a translation is incomplete.
class CronPrettyStringL10n {
  final bool andOxfordComma;
  final String and;

  final String at;
  final String from;
  final String through;
  final String past;
  final String Function(bool isEvery) on;

  /// The preposition used before a month name, e.g. "in" in "in January".
  final String inWord;

  /// Weekday names starting at Sunday (index 0) through Saturday (index 6),
  /// matching the standard cron day-of-week numbering.
  final List<String> weekdays;

  /// Month names starting at January (index 0) through December (index 11).
  final List<String> months;

  final Map<CronUnitKind, String> _every;
  final Map<CronUnitKind, String> _of;
  final Map<CronUnitKind, String> _unitNames;

  final String Function(int step) ordinalFormatter;

  CronPrettyStringL10n({
    required this.andOxfordComma,
    required this.and,
    required this.at,
    required this.from,
    required this.through,
    required Map<CronUnitKind, String> every,
    required Map<CronUnitKind, String> of,
    required this.past,
    required this.on,
    required this.inWord,
    required this.weekdays,
    required this.months,
    required Map<CronUnitKind, String> unitNames,
    required this.ordinalFormatter,
  }) : _every = every,
       _of = of,
       _unitNames = unitNames {
    if (weekdays.length != 7) {
      throw ArgumentError.value(
        weekdays,
        "weekdays",
        "weekdays must have exactly 7 entries",
      );
    } else if (months.length != 12) {
      throw ArgumentError.value(
        months,
        "months",
        "months must have exactly 12 entries",
      );
    } else if (!_hasAllUnits(every)) {
      throw ArgumentError.value(
        every,
        "every",
        "every must have an entry for every CronUnitKind",
      );
    } else if (!_hasAllUnits(of)) {
      throw ArgumentError.value(
        of,
        "of",
        "of must have an entry for every CronUnitKind",
      );
    } else if (!_hasAllUnits(unitNames)) {
      throw ArgumentError.value(
        unitNames,
        "unitNames",
        "unitNames must have an entry for every CronUnitKind",
      );
    }
  }

  static bool _hasAllUnits(Map<CronUnitKind, String> map) =>
      CronUnitKind.values.every(map.containsKey);

  /// Returns the word used before the unit name for an "every" expression,
  /// e.g. "every" in "every 2nd minute".
  String every(CronUnitKind kind) => _every[kind]!;

  /// Returns the preposition used before the unit name, e.g. "of" in
  /// "5 minutes past the hour".
  String of(CronUnitKind kind) => _of[kind]!;

  /// Returns the display name for the given [kind] of field.
  String unitName(CronUnitKind kind) => _unitNames[kind]!;

  factory CronPrettyStringL10n.fromLocale(String locale) =>
      switch (locale.split("_").first.toLowerCase()) {
        "de" => german,
        _ => english,
      };

  static final english = CronPrettyStringL10n(
    andOxfordComma: true,
    and: "and",
    at: "At",
    from: "from",
    through: "through",
    every: _uniform("every"),
    of: _uniform("of"),
    past: "past",
    on: (_) => "on",
    inWord: "in",
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
    unitNames: const {
      CronUnitKind.second: "second",
      CronUnitKind.minute: "minute",
      CronUnitKind.hour: "hour",
      CronUnitKind.dayOfMonth: "day of the month",
      CronUnitKind.month: "month",
      CronUnitKind.dayOfWeek: "day of the week",
    },
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
    every: const {
      CronUnitKind.second: "jeder",
      CronUnitKind.minute: "jeder",
      CronUnitKind.hour: "jeder",
      CronUnitKind.dayOfMonth: "jedem",
      CronUnitKind.month: "jedem",
      CronUnitKind.dayOfWeek: "jedem",
    },
    of: const {
      CronUnitKind.second: "der",
      CronUnitKind.minute: "der",
      CronUnitKind.hour: "der",
      CronUnitKind.dayOfMonth: "des",
      CronUnitKind.month: "des",
      CronUnitKind.dayOfWeek: "des",
    },
    past: "nach",
    on: (isEvery) => isEvery ? "an" : "am",
    inWord: "im",
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
    unitNames: const {
      CronUnitKind.second: "Sekunde",
      CronUnitKind.minute: "Minute",
      CronUnitKind.hour: "Stunde",
      CronUnitKind.dayOfMonth: "Monatstag",
      CronUnitKind.month: "Monat",
      CronUnitKind.dayOfWeek: "Wochentag",
    },
    ordinalFormatter: (step) => "$step.",
  );

  static Map<CronUnitKind, String> _uniform(String value) => {
    for (final kind in CronUnitKind.values) kind: value,
  };
}
