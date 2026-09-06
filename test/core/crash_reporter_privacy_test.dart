import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karar_veriyorum/core/services/crash_reporter.dart';

void main() {
  test('external crash diagnostics exclude messages and collectors', () {
    const secret = 'private-diagnostic-sentinel';
    final details = safeFlutterErrorDetails(
      FlutterErrorDetails(
        exception: StateError(secret),
        stack: StackTrace.fromString('safeFrame'),
        context: ErrorDescription(secret),
        informationCollector: () => [ErrorDescription(secret)],
        library: secret,
      ),
    );
    expect(details.exceptionAsString(), isNot(contains(secret)));
    expect(details.exceptionAsString(), contains('StateError'));
    expect(details.informationCollector, isNull);
    expect(details.context, isNull);
    expect(details.library, 'application');
    expect(details.stack.toString(), 'safeFrame');
  });
}
