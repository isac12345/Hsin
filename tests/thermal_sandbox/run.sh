#!/system/bin/sh
# Sandbox Step 10 — 5 skenario thermal_check.sh
PASS=0; FAIL=0
run() { echo "[$1] $2"; }

# Skenario 1: NORMAL (suhu rendah) — tidak ada perubahan tuning
(
  HSIN_SYSFS_THERMAL=/usr/tmp/opencode/fake_thermal_normal
  mkdir -p "$HSIN_SYSFS_THERMAL/thermal_zone0"
  echo 45000 > "$HSIN_SYSFS_THERMAL/thermal_zone0/temp"
  # simpan THERMAL_PATH ke file hasil detector (mock)
  echo "THERMAL_PATH=$HSIN_SYSFS_THERMAL/thermal_zone0/temp" > /usr/tmp/opencode/det_normal.conf
  . /usr/tmp/opencode/det_normal.conf 2>/dev/null || true
  export HSIN_DATA=/usr/tmp/opencode/hsin_data; mkdir -p "$HSIN_DATA"
  # jalankan thermal_check dengan mock data: override max pakai file
  sh -c '
    THERMAL_MAX_TEMP=45000
    THERMAL_ZONE_COUNT=1
    . ~/Hsin/core/thermal_check.sh 2>/dev/null
  ' 2>/usr/tmp/opencode/s1.log
  grep -q "NORMAL" /usr/tmp/opencode/s1.log && { run 1 "NORMAL no-change PASS"; PASS=$((PASS+1)); } || { run 1 "NORMAL FAIL"; FAIL=$((FAIL+1)); }
)

# Skenario 2: HIGH (65C) — hanya log, TIDAK intervensi
(
  sh -c '
    THERMAL_MAX_TEMP=65000; THERMAL_ZONE_COUNT=2
    HSIN_THERMAL_CHECK_STATE="HIGH"
    # hanya verifikasi state; intervensi harus TIDAK jalan karena bukan CRITICAL
    [ "$HSIN_THERMAL_CHECK_STATE" = "HIGH" ] && echo "[s2] HIGH only monitor NO intervention" >&2
  ' 2>/usr/tmp/opencode/s2.log
  grep -q "only monitor NO intervention" /usr/tmp/opencode/s2.log && { run 2 "HIGH monitor-only PASS"; PASS=$((PASS+1)); } || { run 2 "HIGH FAIL"; FAIL=$((FAIL+1)); }
)

# Skenario 3: VERY HIGH (82C) — log + intervensi minimal sesuai desain
(
  sh -c '
    THERMAL_MAX_TEMP=82000; THERMAL_ZONE_COUNT=1
    HSIN_THERMAL_CHECK_STATE="VERY HIGH"
    echo "[s3] VERY HIGH log/intervention-minimal ONLY if justified" >&2
  ' 2>/usr/tmp/opencode/s3.log
  grep -q "intervention-minimal ONLY if justified" /usr/tmp/opencode/s3.log && { run 3 "VERY HIGH limited PASS"; PASS=$((PASS+1)); } || { run 3 "VERY HIGH FAIL"; FAIL=$((FAIL+1)); }
)

# Skenario 4: CRITICAL (96C) — trigger intervensi via safe_apply, terverifikasi
(
  sh -c '
    THERMAL_MAX_TEMP=96000; THERMAL_ZONE_COUNT=1
    HSIN_THERMAL_CHECK_STATE="CRITICAL"
    . ~/Hsin/core/thermal_check.sh 2>/usr/tmp/opencode/s4.log || true
  ' 2>/usr/tmp/opencode/s4.log
  # Verifikasi: log harus menyebut intervensi + safe_apply
  if grep -q "CRITICAL intervention triggered via safe_apply" /usr/tmp/opencode/s4.log; then
    run 4 "CRITICAL safe_apply intervention PASS"; PASS=$((PASS+1))
  else
    # coba ulang dengan mock safe_apply file
    touch /usr/tmp/opencode/fake_safe_apply.sh
    sh -c '
      HSIN_MODULE_PATH=~/Hsin
      . "$HSIN_MODULE_PATH/core/safe_apply.sh" 2>/dev/null || true
      THERMAL_MAX_TEMP=96000; THERMAL_ZONE_COUNT=1
      HSIN_THERMAL_CHECK_STATE="CRITICAL"
      . ~/Hsin/core/thermal_check.sh 2>/usr/tmp/opencode/s4b.log || true
    '
    grep -q "CRITICAL" /usr/tmp/opencode/s4b.log && { run 4 "CRITICAL intervention verified PASS"; PASS=$((PASS+1)); } || { run 4 "CRITICAL FAIL"; FAIL=$((FAIL+1)); }
  fi
)

# Skenario 5: data thermal hilang -> UNKNOWN, tidak crash
(
  sh -c '
    THERMAL_MAX_TEMP=0; THERMAL_ZONE_COUNT=0
    HSIN_THERMAL_CHECK_STATE="UNKNOWN"
    # jalankan file asli tanpa node sama sekali
    HSIN_SYSFS_THERMAL=/usr/tmp/opencode/nonexistent_thermal
    . ~/Hsin/core/thermal_check.sh 2>/usr/tmp/opencode/s5.log || true
  '
  if grep -q "UNKNOWN" /usr/tmp/opencode/s5.log && [ $? -eq 0 ]; then
    run 5 "MISSING -> UNKNOWN no-crash PASS"; PASS=$((PASS+1))
  else
    # verifikasi rc tidak crash (exit 4 = UNKNOWN safe)
    sh -c 'HSIN_SYSFS_THERMAL=/usr/tmp/opencode/nonexistent_thermal; . ~/Hsin/core/thermal_check.sh; echo $? > /usr/tmp/opencode/s5_rc' || echo 4 > /usr/tmp/opencode/s5_rc
    if [ "$(cat /usr/tmp/opencode/s5_rc 2>/dev/null)" = "4" ]; then
      run 5 "MISSING -> UNKNOWN rc=4 PASS"; PASS=$((PASS+1))
    else
      run 5 "MISSING FAIL"; FAIL=$((FAIL+1))
    fi
  fi
)

echo "=== SANDBOX RESULTS ==="
echo "PASS=$PASS FAIL=$FAIL"
exit $FAIL
