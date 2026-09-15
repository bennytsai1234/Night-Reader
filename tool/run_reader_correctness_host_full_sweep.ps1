if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw 'C5 host full sweep must run under PowerShell 7: use pwsh -NoProfile.'
}

# The Dart test has a fixed five-minute test timeout and the generator has a
# fixed 4,308-case count. Keep this route independent from the default flutter
# test path; do not turn it into an unbounded soak or add a fixed sleep.
& flutter test tool/reader_correctness_host_full_sweep_test.dart --reporter expanded
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
