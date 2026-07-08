#!/usr/bin/env bash
# Katman bağımlılık kuralı denetimi — TEKNIK-MIMARI.md §2
#   1) domain/ katmanı flutter import edemez (saf Dart)
#   2) domain/ katmanı data/ veya presentation/ import edemez
#   3) core/, features/ import edemez
set -euo pipefail

fail=0

# 1) domain saf Dart olmalı
if grep -rn "package:flutter" lib/features/*/domain 2>/dev/null; then
  echo "HATA: domain katmanında flutter import'u var (saf Dart olmalı)." >&2
  fail=1
fi

# 2) domain → data/presentation yasak
if grep -rnE "import .*(\/data\/|\/presentation\/)" lib/features/*/domain 2>/dev/null; then
  echo "HATA: domain katmanı data/presentation import edemez." >&2
  fail=1
fi

# 3) core → features yasak
if grep -rn "package:karar_veriyorum/features" lib/core 2>/dev/null; then
  echo "HATA: core katmanı features import edemez." >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "Katman kuralları: OK"
fi
exit "$fail"
