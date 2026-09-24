import 'dart:io';

// Keep a small raw parse-size allowance while the tighter transferred-size
// budget below remains the primary production network guard. The 50 kB
// allowance above the pre-PostHog ceiling covers the typed analytics runtime.
// A further 50 kB covers the approved audit investigation/detail/export flow;
// its isolated artifact measured 10,177,884 raw / 2,747,966 gzip bytes. The
// final 50 kB covers the same candidate with every approved staging rollout
// enabled; that artifact measured 10,205,890 raw / 2,714,714 gzip bytes.
// The approved MR post-approval editor adds a named-grant dialog and role-safe
// recovery copy; its staged artifact measured 10,255,834 raw / 2,767,999
// gzip bytes. Allow 15 kB for that slice and keep the transfer ceiling unchanged.
const _mainDartJsRawBudget = 10265000;
const _mainDartJsGzipBudget = 2900000;
const _indexHtmlRawBudget = 40000;

Never _fail(String message) {
  stderr.writeln('Startup performance budget failed: $message');
  exit(1);
}

void main(List<String> arguments) {
  final directory = Directory(arguments.isEmpty ? 'build/web' : arguments[0]);
  if (!directory.existsSync()) {
    _fail('${directory.path} does not exist');
  }

  final mainDartJs = File('${directory.path}/main.dart.js');
  final indexHtml = File('${directory.path}/index.html');
  final bootstrap = File('${directory.path}/flutter_bootstrap.js');
  for (final file in [mainDartJs, indexHtml, bootstrap]) {
    if (!file.existsSync()) _fail('${file.path} is missing');
  }

  final mainBytes = mainDartJs.readAsBytesSync();
  final mainGzipBytes = gzip.encode(mainBytes).length;
  final indexBytes = indexHtml.lengthSync();
  final bootstrapSource = bootstrap.readAsStringSync();
  final indexSource = indexHtml.readAsStringSync();
  final launchCallStart = bootstrapSource.lastIndexOf('_flutter.loader.load({');

  if (mainBytes.length > _mainDartJsRawBudget) {
    _fail(
      'main.dart.js is ${mainBytes.length} bytes; '
      'budget is $_mainDartJsRawBudget',
    );
  }
  if (mainGzipBytes > _mainDartJsGzipBudget) {
    _fail(
      'main.dart.js gzip is $mainGzipBytes bytes; '
      'budget is $_mainDartJsGzipBudget',
    );
  }
  if (indexBytes > _indexHtmlRawBudget) {
    _fail('index.html is $indexBytes bytes; budget is $_indexHtmlRawBudget');
  }
  if (launchCallStart < 0) {
    _fail('the explicit Flutter launch call is missing');
  }
  final launchCall = bootstrapSource.substring(launchCallStart);
  if (launchCall.contains('serviceWorkerSettings')) {
    _fail('Flutter entrypoint is blocked behind service-worker startup');
  }
  if (!indexSource.contains('data-yorks-boot-status') ||
      !indexSource.contains('flutter-first-frame')) {
    _fail('the immediate web launch surface is missing');
  }

  stdout.writeln(
    'Startup budget passed: main.dart.js=${mainBytes.length} bytes '
    '(gzip=$mainGzipBytes), index.html=$indexBytes bytes.',
  );
}
