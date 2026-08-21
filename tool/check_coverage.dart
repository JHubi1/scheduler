// Parses an lcov.info report and enforces a minimum per-file line coverage,
// printing a Markdown table (also published to $GITHUB_STEP_SUMMARY in CI).
library;

import 'dart:io';

void main(List<String> args) {
  final lcovPath = args.isNotEmpty ? args[0] : "coverage/lcov.info";
  final threshold = args.length > 1 ? double.parse(args[1]) : 90.0;

  final lcovFile = File(lcovPath);
  if (!lcovFile.existsSync()) {
    stderr.writeln("Coverage file not found: $lcovPath");
    exit(2);
  }

  final results = <_FileCoverage>[];
  String? path;
  int? linesFound;
  int? linesHit;

  for (final line in lcovFile.readAsLinesSync()) {
    if (line.startsWith("SF:")) {
      path = line.substring(3).trim();
    } else if (line.startsWith("LF:")) {
      linesFound = int.parse(line.substring(3));
    } else if (line.startsWith("LH:")) {
      linesHit = int.parse(line.substring(3));
    } else if (line == "end_of_record") {
      if (path != null && linesFound != null && linesHit != null) {
        results.add(_FileCoverage(path, linesHit, linesFound));
      }
      path = null;
      linesFound = null;
      linesHit = null;
    }
  }

  if (results.isEmpty) {
    stderr.writeln("No coverage records found in $lcovPath");
    exit(2);
  }

  results.sort((a, b) => a.percent.compareTo(b.percent));

  final failing = results.where((r) => r.percent < threshold).toList();

  final summary = StringBuffer()
    ..writeln("## Coverage report")
    ..writeln()
    ..writeln(
      "Minimum required per-file line coverage: ${threshold.toStringAsFixed(1)}%",
    )
    ..writeln()
    ..writeln("| File | Lines | Coverage |")
    ..writeln("| --- | --- | --- |");
  for (final result in results) {
    final status = result.percent >= threshold ? "✅" : "❌";
    summary.writeln(
      "| ${result.displayPath} | ${result.hit}/${result.found} | "
      "$status ${result.percent.toStringAsFixed(1)}% |",
    );
  }
  if (failing.isNotEmpty) {
    summary
      ..writeln()
      ..writeln(
        "**${failing.length} file(s) are below the ${threshold.toStringAsFixed(1)}% "
        "threshold.**",
      );
  }

  print(summary);

  final summaryPath = Platform.environment["GITHUB_STEP_SUMMARY"];
  if (summaryPath != null) {
    File(summaryPath).writeAsStringSync("$summary\n", mode: FileMode.append);
  }

  if (failing.isNotEmpty) {
    stderr.writeln(
      "Coverage check failed: ${failing.map((r) => r.displayPath).join(", ")} "
      "are below ${threshold.toStringAsFixed(1)}%.",
    );
    exit(1);
  }
}

class _FileCoverage {
  final String path;
  final int hit;
  final int found;

  _FileCoverage(this.path, this.hit, this.found);

  double get percent => found == 0 ? 100.0 : hit / found * 100.0;

  String get displayPath {
    final normalized = path.replaceAll("\\", "/");
    final index = normalized.indexOf("/lib/");
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }
}
