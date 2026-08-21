import 'package:scheduler/src/cron.dart';
import 'package:test/test.dart';

CronPrettyStringL10n _makeL10n({
  List<String>? weekdays,
  List<String>? months,
  Map<CronUnitKind, String>? every,
  Map<CronUnitKind, String>? of,
  Map<CronUnitKind, String>? unitNames,
}) {
  return CronPrettyStringL10n(
    andOxfordComma: true,
    and: "and",
    at: "At",
    from: "from",
    through: "through",
    every: every ?? {for (final k in CronUnitKind.values) k: "every"},
    of: of ?? {for (final k in CronUnitKind.values) k: "of"},
    past: "past",
    on: (_) => "on",
    inWord: "in",
    weekdays:
        weekdays ??
        const [
          "Sunday",
          "Monday",
          "Tuesday",
          "Wednesday",
          "Thursday",
          "Friday",
          "Saturday",
        ],
    months: months ?? List.generate(12, (i) => "Month${i + 1}"),
    unitNames:
        unitNames ??
        const {
          CronUnitKind.second: "second",
          CronUnitKind.minute: "minute",
          CronUnitKind.hour: "hour",
          CronUnitKind.dayOfMonth: "day of the month",
          CronUnitKind.month: "month",
          CronUnitKind.dayOfWeek: "day of the week",
        },
    ordinalFormatter: (step) => "${step}th",
  );
}

void main() {
  group("CronField parsing (via Cron.parse)", () {
    test("wildcard", () {
      final cron = Cron.parse("* * * * * *");
      expect(cron.second, isA<CronFieldWildcard>());
    });

    test("single value", () {
      final cron = Cron.parse("* 10 * * * *");
      final minute = cron.minute as CronFieldValue;
      expect(minute.value, 10);
    });

    test("list of values", () {
      final cron = Cron.parse("* 1,2,3 * * * *");
      final minute = cron.minute as CronFieldList;
      expect(minute.fields.map((f) => (f as CronFieldValue).value).toList(), [
        1,
        2,
        3,
      ]);
    });

    test("range", () {
      final cron = Cron.parse("* * 1-5 * * *");
      final hour = cron.hour as CronFieldRange;
      expect((hour.start as CronFieldValue).value, 1);
      expect((hour.end as CronFieldValue).value, 5);
    });

    test("step with wildcard base", () {
      final cron = Cron.parse("*/15 * * * * *");
      final second = cron.second as CronFieldStep;
      expect(second.base, isA<CronFieldWildcard>());
      expect(second.step, 15);
    });

    test("step with range base", () {
      final cron = Cron.parse("* * 1-10/2 * * *");
      final hour = cron.hour as CronFieldStep;
      expect(hour.base, isA<CronFieldRange>());
      expect(hour.step, 2);
    });

    test("list of ranges", () {
      final cron = Cron.parse("* * 1-5,10-15 * * *");
      final hour = cron.hour as CronFieldList;
      expect(hour.fields, everyElement(isA<CronFieldRange>()));
    });
  });

  group("CronField.format", () {
    test("reconstructs from parsed value, ignoring raw padding", () {
      final cron = Cron.parse("007 * * * * *");
      expect(cron.second.format(), "7");
    });

    test("wildcard formats as '*'", () {
      expect(CronFieldWildcard().format(), "*");
    });

    test("list joins fields with commas", () {
      final cron = Cron.parse("* 1,2,3 * * * *");
      expect(cron.minute.format(), "1,2,3");
    });

    test("range formats as 'start-end'", () {
      final cron = Cron.parse("* * 1-5 * * *");
      expect(cron.hour.format(), "1-5");
    });

    test("step formats as 'base/step'", () {
      final cron = Cron.parse("*/5 1-10/2 * * * *");
      expect(cron.second.format(), "*/5");
      expect(cron.minute.format(), "1-10/2");
    });
  });

  group("CronField.copyWith", () {
    test("creates a copy with a new value", () {
      final field = CronFieldValue(5);
      final updated = field.copyWith(value: 10);
      expect(updated.value, 10);
    });

    test("keeps the existing value when none is given", () {
      final field = CronFieldValue(5);
      final updated = field.copyWith();
      expect(updated.value, 5);
    });
  });

  group("CronField.toString", () {
    test("CronFieldWildcard", () {
      expect(CronFieldWildcard().toString(), "CronFieldWildcard()");
    });

    test("CronFieldValue", () {
      expect(CronFieldValue(5).toString(), "CronFieldValue(value: 5)");
    });

    test("CronFieldList", () {
      final list = CronFieldList([CronFieldValue(1), CronFieldValue(2)]);
      expect(list.toString(), contains("CronFieldList("));
      expect(list.toString(), contains("fields:"));
    });

    test("CronFieldRange", () {
      final range = CronFieldRange(CronFieldValue(1), CronFieldValue(5));
      expect(range.toString(), contains("CronFieldRange("));
      expect(range.toString(), contains("start:"));
      expect(range.toString(), contains("end:"));
    });

    test("CronFieldStep", () {
      final step = CronFieldStep(CronFieldWildcard(), 5);
      expect(step.toString(), contains("CronFieldStep("));
      expect(step.toString(), contains("base:"));
      expect(step.toString(), contains("step: 5"));
    });
  });

  group("CronField construction errors", () {
    test("empty field within a list throws ArgumentError", () {
      expect(() => Cron.parse("* , * * * *"), throwsArgumentError);
    });

    test("non-integer value throws ArgumentError", () {
      expect(() => Cron.parse("abc * * * * *"), throwsArgumentError);
    });

    test("step with more than one '/' throws ArgumentError", () {
      expect(() => Cron.parse("1/2/3 * * * * *"), throwsArgumentError);
    });

    test("non-integer step throws ArgumentError", () {
      expect(() => Cron.parse("*/abc * * * * *"), throwsArgumentError);
    });

    test("range with more than one '-' throws ArgumentError", () {
      expect(() => Cron.parse("1-2-3 * * * * *"), throwsArgumentError);
    });

    test("wrong number of expression fields throws ArgumentError", () {
      expect(() => Cron.parse("* * * *"), throwsArgumentError);
      expect(() => Cron.parse("* * * * * * *"), throwsArgumentError);
    });
  });

  group("Cron() validates field ranges when constructed directly", () {
    // Cron.parse validates each leaf value while parsing, so these
    // out-of-range values can only surface via the Cron() constructor itself,
    // which re-validates every field tree (including lists/ranges/steps).
    test("a CronFieldList with an out-of-range value throws ArgumentError", () {
      expect(
        () => Cron(
          second: CronFieldValue(0),
          minute: CronFieldValue(0),
          hour: CronFieldList([CronFieldValue(0), CronFieldValue(99)]),
          dayOfMonth: CronFieldValue(1),
          month: CronFieldValue(1),
          dayOfWeek: CronFieldWildcard(),
        ),
        throwsArgumentError,
      );
    });

    test(
      "a CronFieldRange with an out-of-range bound throws ArgumentError",
      () {
        expect(
          () => Cron(
            second: CronFieldValue(0),
            minute: CronFieldValue(0),
            hour: CronFieldRange(CronFieldValue(0), CronFieldValue(99)),
            dayOfMonth: CronFieldValue(1),
            month: CronFieldValue(1),
            dayOfWeek: CronFieldWildcard(),
          ),
          throwsArgumentError,
        );
      },
    );

    test("a CronFieldStep with an out-of-range base throws ArgumentError", () {
      expect(
        () => Cron(
          second: CronFieldValue(0),
          minute: CronFieldValue(0),
          hour: CronFieldStep(
            CronFieldRange(CronFieldValue(0), CronFieldValue(99)),
            2,
          ),
          dayOfMonth: CronFieldValue(1),
          month: CronFieldValue(1),
          dayOfWeek: CronFieldWildcard(),
        ),
        throwsArgumentError,
      );
    });
  });

  group("CronField invalid combinations", () {
    test("negative CronFieldValue", () {
      expect(() => CronFieldValue(-1), throwsArgumentError);
    });

    test("CronFieldRange requires CronFieldValue start/end", () {
      expect(
        () => CronFieldRange(CronFieldWildcard(), CronFieldValue(5)),
        throwsArgumentError,
      );
    });

    test("CronFieldRange requires start < end", () {
      expect(
        () => CronFieldRange(CronFieldValue(5), CronFieldValue(1)),
        throwsArgumentError,
      );
    });

    test("CronFieldStep requires a wildcard or range base", () {
      expect(() => CronFieldStep(CronFieldValue(5), 2), throwsArgumentError);
    });

    test("CronFieldStep requires a positive step", () {
      expect(() => CronFieldStep(CronFieldWildcard(), 0), throwsArgumentError);
      expect(() => Cron.parse("*/0 * * * * *"), throwsArgumentError);
    });
  });

  group("Cron.parse", () {
    test("assumes a 0 seconds field when given 5 fields", () {
      final cron = Cron.parse("* * * * *");
      expect(cron.second, isA<CronFieldValue>());
      expect((cron.second as CronFieldValue).value, 0);
    });

    test("uses the given seconds field when given 6 fields", () {
      final cron = Cron.parse("30 * * * * *");
      expect((cron.second as CronFieldValue).value, 30);
    });

    test("collapses repeated whitespace between fields", () {
      final cron = Cron.parse("*   *  *    * *   *");
      expect(cron.format(), "* * * * * *");
    });

    test("trims surrounding whitespace", () {
      final cron = Cron.parse("  * * * * * *  ");
      expect(cron.format(), "* * * * * *");
    });
  });

  group("Cron.tryParse", () {
    test("returns a Cron for a valid expression", () {
      expect(Cron.tryParse("* * * * * *"), isA<Cron>());
    });

    test("returns null for the wrong number of fields", () {
      expect(Cron.tryParse("* * * *"), isNull);
    });

    test("returns null for a non-integer value", () {
      expect(Cron.tryParse("abc * * * * *"), isNull);
    });

    test("returns null for malformed step syntax", () {
      expect(Cron.tryParse("1/2/3 * * * * *"), isNull);
    });

    test("returns null for malformed range syntax", () {
      expect(Cron.tryParse("1-2-3 * * * * *"), isNull);
    });

    test("returns null when a field's assertion fails (e.g. bad range)", () {
      expect(Cron.tryParse("5-1 * * * * *"), isNull);
    });
  });

  group("Cron.format", () {
    test("always includes the seconds field", () {
      final cron = Cron.parse("* * * * *");
      expect(cron.format(), "0 * * * * *");
    });

    test("round-trips a full expression", () {
      const expression = "*/20 15,45 8-18/3 5 1,6,10 1-5";
      final cron = Cron.parse(expression);
      expect(cron.format(), expression);
    });
  });

  group("Cron.copyWith", () {
    test("replaces only the given fields", () {
      final cron = Cron.parse("0 0 * * *");
      final updated = cron.copyWith(hour: CronFieldValue(5));
      expect(updated.format(), "0 0 5 * * *");
      expect(updated.minute, same(cron.minute));
      expect(updated.dayOfMonth, same(cron.dayOfMonth));
    });

    test("keeps all fields when nothing is given", () {
      final cron = Cron.parse("0 0 * * *");
      final updated = cron.copyWith();
      expect(updated.format(), cron.format());
    });
  });

  group("Cron.toString", () {
    test("includes all field values", () {
      final cron = Cron.parse("1 2 3 4 5 6");
      final result = cron.toString();
      expect(result, startsWith("Cron("));
      expect(result, contains("second:"));
      expect(result, contains("dayOfWeek:"));
    });
  });

  group("Cron.toPrettyString", () {
    test("single minute value", () {
      final cron = Cron.parse("0 30 * * * *");
      expect(cron.toPrettyString(), "At minute 30.");
    });

    test("all wildcards", () {
      final cron = Cron.parse("* * * * * *");
      expect(cron.toPrettyString(), "At every second.");
    });

    test("hour range", () {
      final cron = Cron.parse("0 0 9-17 * * *");
      expect(
        cron.toPrettyString(),
        "At minute 0 past every hour from 9 through 17.",
      );
    });

    test("a step of 1 collapses to the base range", () {
      final cron = Cron.parse("0 0 9-17/1 * * *");
      expect(
        cron.toPrettyString(),
        "At minute 0 past every hour from 9 through 17.",
      );
    });

    test("full 0-6 day of week range hides the 'from...through' suffix", () {
      final cron = Cron.parse("0 0 12 * * 0-6");
      expect(
        cron.toPrettyString(),
        "At minute 0 past hour 12 on every day of the week.",
      );
    });

    test("month list uses named months with an Oxford comma", () {
      final cron = Cron.parse("0 0 0 1 1,6,12 *");
      expect(
        cron.toPrettyString(),
        "At minute 0 past hour 0 on day of the month 1 in January, June, and December.",
      );
    });

    test("full expression in English", () {
      final cron = Cron.parse("*/20 15,45 8-18/3 5 1,6,10 1-5");
      expect(
        cron.toPrettyString(),
        "At every 20th second of minute 15 and 45 past every 3rd hour from 8 "
        "through 18 on day of the month 5 and on every day of the week from "
        "Monday through Friday in January, June, and October.",
      );
    });

    test("full expression in German", () {
      final cron = Cron.parse("*/20 15,45 8-18/3 5 1,6,10 1-5");
      expect(
        cron.toPrettyString(l10n: CronPrettyStringL10n.german),
        "In jeder 20. Sekunde der Minute 15 und 45 nach jeder 3. Stunde von 8 "
        "bis 18 am Monatstag 5 und an jedem Wochentag von Montag bis Freitag "
        "im Januar, Juni und Oktober.",
      );
    });

    test("a list with a single field formats like the field alone", () {
      final cron = Cron(
        second: CronFieldValue(0),
        minute: CronFieldList([CronFieldValue(5)]),
        hour: CronFieldWildcard(),
        dayOfMonth: CronFieldWildcard(),
        month: CronFieldWildcard(),
        dayOfWeek: CronFieldWildcard(),
      );
      expect(cron.toPrettyString(), "At minute 5.");
    });

    test("day of week step with a full 0-6 range base hides the suffix", () {
      final cron = Cron.parse("0 0 12 * * 0-6/2");
      expect(
        cron.toPrettyString(),
        "At minute 0 past hour 12 on every 2nd day of the week.",
      );
    });

    test("day of week step with a partial range base shows the suffix", () {
      final cron = Cron.parse("0 0 12 * * 1-5/2");
      expect(
        cron.toPrettyString(),
        "At minute 0 past hour 12 on every 2nd day of the week from Monday "
        "through Friday.",
      );
    });

    test("an out-of-range day of week value throws ArgumentError", () {
      expect(() => Cron.parse("0 0 12 * * 7"), throwsArgumentError);
    });

    test("an out-of-range month value throws ArgumentError", () {
      expect(() => Cron.parse("0 0 0 1 13 *"), throwsArgumentError);
    });
  });

  group("Cron.next", () {
    test("finds the next matching time later the same day", () {
      final cron = Cron.parse("0 12 * * *");
      final from = DateTime(2026, 8, 18, 6, 0, 0);
      final result = cron.next(from);
      expect(result.next, DateTime(2026, 8, 18, 12, 0, 0));
      expect(result.delay, const Duration(hours: 6));
    });

    test("rolls over to the next day", () {
      final cron = Cron.parse("30 5 * * *");
      final from = DateTime(2026, 8, 18, 6, 0, 0);
      final result = cron.next(from);
      expect(result.next, DateTime(2026, 8, 19, 5, 30, 0));
    });

    test("is strictly after 'from', excluding an exact match", () {
      final cron = Cron.parse("0 6 * * *");
      final from = DateTime(2026, 8, 18, 6, 0, 0);
      final result = cron.next(from);
      expect(result.next, DateTime(2026, 8, 19, 6, 0, 0));
    });

    test("matches a day of week field", () {
      final cron = Cron.parse("0 0 * * 1"); // every Monday
      final from = DateTime(2026, 8, 18); // a Tuesday
      final result = cron.next(from);
      expect(result.next, DateTime(2026, 8, 24));
      expect(result.next.weekday, DateTime.monday);
    });

    test(
      "combines dayOfMonth and dayOfWeek with OR when both are restricted",
      () {
        final cron = Cron.parse("0 0 1 * 1"); // 1st of month OR any Monday
        final from = DateTime(2026, 8, 18); // Tuesday; next Monday is closer
        final result = cron.next(from);
        expect(result.next, DateTime(2026, 8, 24));
      },
    );

    test("matches a '*/step' field anchored to the field minimum", () {
      final cron = Cron.parse("*/15 * * * *");
      final from = DateTime(2026, 8, 18, 6, 7, 0);
      final result = cron.next(from);
      expect(result.next, DateTime(2026, 8, 18, 6, 15, 0));
    });

    test("matches a list field", () {
      final cron = Cron.parse("0,30 * * * *");
      final from = DateTime(2026, 8, 18, 6, 10, 0);
      final result = cron.next(from);
      expect(result.next, DateTime(2026, 8, 18, 6, 30, 0));
    });

    test("matches a range field", () {
      final cron = Cron.parse("0 9-17 * * *");
      final from = DateTime(2026, 8, 18, 20, 0, 0);
      final result = cron.next(from);
      expect(result.next, DateTime(2026, 8, 19, 9, 0, 0));
    });

    test("matches a '*/step' field with a range base", () {
      final cron = Cron.parse("0 9-17/2 * * *");
      final from = DateTime(2026, 8, 18, 8, 0, 0);
      final result = cron.next(from);
      expect(result.next, DateTime(2026, 8, 18, 9, 0, 0));
    });

    test("preserves UTC when 'from' is UTC", () {
      final cron = Cron.parse("0 0 * * *");
      final from = DateTime.utc(2026, 8, 18, 6, 0, 0);
      final result = cron.next(from);
      expect(result.next.isUtc, isTrue);
      expect(result.next, DateTime.utc(2026, 8, 19));
    });

    test("finds a leap day within the default search window", () {
      final cron = Cron.parse("0 0 29 2 *");
      final from = DateTime(2026, 3, 1);
      final result = cron.next(from);
      expect(result.next, DateTime(2028, 2, 29));
    });

    test("respects a custom maxYearsToSearch when a match exists", () {
      final cron = Cron.parse("0 0 1 1 *");
      final from = DateTime(2026, 6, 1);
      final result = cron.next(from, maxYearsToSearch: 1);
      expect(result.next, DateTime(2027));
    });

    test(
      "throws SchedulerOutOfReachException when no match exists in range",
      () {
        final cron = Cron.parse("0 0 31 2 *"); // Feb never has 31 days
        expect(
          () => cron.next(DateTime(2026, 1, 1)),
          throwsA(isA<SchedulerOutOfReachException>()),
        );
      },
    );

    test(
      "throws SchedulerOutOfReachException when maxYearsToSearch is too small to find a match",
      () {
        final cron = Cron.parse("0 0 29 2 *"); // next leap day is 2028
        final from = DateTime(2026, 3, 1);
        expect(
          () => cron.next(from, maxYearsToSearch: 1),
          throwsA(isA<SchedulerOutOfReachException>()),
        );
      },
    );
  });

  group("CronPrettyStringL10n", () {
    test("unitName returns the matching field name for each unit", () {
      final l10n = _makeL10n();
      expect(l10n.unitName(CronUnitKind.second), "second");
      expect(l10n.unitName(CronUnitKind.dayOfWeek), "day of the week");
    });

    test("german .of returns the correct article for every unit", () {
      final l10n = CronPrettyStringL10n.german;
      expect(l10n.of(CronUnitKind.second), "der");
      expect(l10n.of(CronUnitKind.minute), "der");
      expect(l10n.of(CronUnitKind.hour), "der");
      expect(l10n.of(CronUnitKind.dayOfMonth), "des");
      expect(l10n.of(CronUnitKind.month), "des");
      expect(l10n.of(CronUnitKind.dayOfWeek), "des");
    });

    test("requires exactly 7 weekdays", () {
      expect(() => _makeL10n(weekdays: const ["Sunday"]), throwsArgumentError);
    });

    test("requires exactly 12 months", () {
      expect(() => _makeL10n(months: const ["January"]), throwsArgumentError);
    });

    test("requires an 'every' entry for every CronUnitKind", () {
      expect(
        () => _makeL10n(every: const {CronUnitKind.second: "every"}),
        throwsArgumentError,
      );
    });

    test("requires an 'of' entry for every CronUnitKind", () {
      expect(
        () => _makeL10n(of: const {CronUnitKind.second: "of"}),
        throwsArgumentError,
      );
    });

    test("requires a unitNames entry for every CronUnitKind", () {
      expect(
        () => _makeL10n(unitNames: const {CronUnitKind.second: "second"}),
        throwsArgumentError,
      );
    });
  });
}
