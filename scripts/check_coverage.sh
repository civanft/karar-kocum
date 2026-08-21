#!/usr/bin/env bash
# Kapsam kapısı — TEKNIK-MIMARI.md §10
#
# Kullanım:
#   flutter test --coverage          # önce lcov.info üret
#   bash scripts/check_coverage.sh [eşik]   # varsayılan eşik: 80
#
# Üretilen kod (*.g.dart, *.freezed.dart, firebase_options) kapsam
# hesabından HARİÇ tutulur — el yazması kodun kapsamı ölçülür.
set -euo pipefail

THRESHOLD="${1:-80}"
LCOV_FILE="coverage/lcov.info"

if [ ! -f "$LCOV_FILE" ]; then
  echo "HATA: $LCOV_FILE bulunamadı. Önce 'flutter test --coverage' çalıştırın." >&2
  exit 2
fi

read -r TOTAL_LINES HIT_LINES < <(awk '
  /^SF:/ {
    file = substr($0, 4)
    skip = (file ~ /\.g\.dart$/ || file ~ /\.freezed\.dart$/ || file ~ /firebase_options/)
  }
  /^LF:/ { if (!skip) total += substr($0, 4) }
  /^LH:/ { if (!skip) hit   += substr($0, 4) }
  END { printf "%d %d\n", total, hit }
' "$LCOV_FILE")

if [ "$TOTAL_LINES" -eq 0 ]; then
  echo "HATA: lcov.info içinde ölçülebilir satır yok." >&2
  exit 2
fi

COVERAGE=$(awk -v h="$HIT_LINES" -v t="$TOTAL_LINES" 'BEGIN { printf "%.1f", (h/t)*100 }')

echo "Kapsam: ${COVERAGE}%  (${HIT_LINES}/${TOTAL_LINES} satır)  — eşik: ${THRESHOLD}%"

# En düşük kapsamlı 5 dosyayı göster (iyileştirme rehberi)
echo "--- En düşük kapsamlı dosyalar ---"
# sed tüm girdiyi tüketir; head + pipefail SIGPIPE üretebilir.
awk '
  /^SF:/ {
    file = substr($0, 4)
    skip = (file ~ /\.g\.dart$/ || file ~ /\.freezed\.dart$/ || file ~ /firebase_options/)
  }
  /^LF:/ { lf = substr($0, 4) }
  /^LH:/ {
    if (!skip && lf > 0) printf "%6.1f%%  %s\n", (substr($0, 4)/lf)*100, file
  }
' "$LCOV_FILE" | sort -n | sed -n '1,5p'

PASS=$(awk -v c="$COVERAGE" -v t="$THRESHOLD" 'BEGIN { print (c >= t) ? 1 : 0 }')
if [ "$PASS" -eq 1 ]; then
  echo "SONUÇ: GEÇTİ ✅"
else
  echo "SONUÇ: KALDI ❌ — kapsam ${COVERAGE}% < ${THRESHOLD}%" >&2
  exit 1
fi
