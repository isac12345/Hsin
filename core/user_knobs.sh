#!/system/bin/sh
# HSIN User Knob Overrides - lapisan SIMPAN pilihan knob milik user.
#
# MENGAPA file ini ada: core/knobs.sh itu READ-ONLY. Ia melaporkan knob
# apa yang benar-benar ada di device ini (nilai live, daftar yang bisa
# ditulis), dan aksi config-set hanya menerima 7 key hsin.conf. Dua-duanya
# read-only, jadi tidak ada tempat untuk "pilihan user" - aplikasi bisa
# menampilkan knob, tapi tidak bisa menyimpan atau memakainya. File ini
# adalah sisi tulisnya: apa pun yang lolos validasi di sini dianggap
# aman disimpan.
#
# Tiga aksi di atas murni menyimpan. Bagian BAWAH file ini (hsin_uk_get &
# aksesornya) adalah sisi bacanya, dipakai engine saat apply supaya pilihan
# user benar-benar dipakai - apply tanpa override tetap persis sama seperti
# sebelumnya, karena semua jalur tulis engine masih memakai nilai profil
# kalau tidak ada override yang cocok (dan yang tidak didukung device).
#
# Kontrak:
#   - Bentuk file: flat KEY=VALUE, satu key per baris, tanpa spasi - pola
#     yang sama seperti core/scan_cache.sh, supaya file ini bisa dibaca
#     tanpa eval/source.
#   - Input dari luar (WebUI/aplikasi) tidak pernah dipercaya. Nama key
#     berasal dari daftar tertutup dan karakter di luar [A-Za-z0-9_.]
#     ditolak, sehingga newline, '=', ';', dan backtick tidak bisa masuk
#     dan menyuntik baris lain. Nilai juga harus cocok dengan TIPE key
#     (angka vs token), bukan sekadar " bukan kosong".
#   - Tulis selalu atomic (file tmp + mv) supaya pembaca yang kebaca di
#     tengah penulisan tidak pernah melihat file setengah jadi.
#   - Hanya key yang lolos validasi boleh tinggal di file. Baris lain
#     dibuang saat rewrite dan dilaporkan ke log (pertahanan kedua kalau
#     file ini pernah diisi dari luar modul).
#   - Tidak ada satu pun akses node kernel di file ini: murni storage.
#   - stdout hanya untuk pesan yang memang diminta (JSON list, atau pesan
#     error). Diagnostik lain masuk log modul lewat hsin_log_warn.

[ -z "$HSIN_MODULE_PATH" ] && HSIN_MODULE_PATH="/data/adb/modules/hsin"
HSIN_DATA="${HSIN_DATA:-/data/adb/hsin}"

# Batas jumlah key. File ini dibaca tiap apply dan dikirim ke aplikasi
# sebagai JSON, jadi tidak boleh tumbuh tanpa batas. 64 jauh di atas
# kebutuhan nyata (jumlah policy CPU + node GPU + block device di satu
# device) tapi cukup kecil untuk tetap murah diparse.
HSIN_USER_KNOBS_MAX_KEYS=64
# Nama policy/devfreq/block terpanjang di device nyata masih di bawah ini.
HSIN_USER_KNOBS_MAX_KEYLEN=48

_uk_file="$HSIN_DATA/user_knobs.env"

# _kn_e milik core/knobs.sh (escaper di sana), di-defaultkan di sini
# supaya jelas file ini memakainya, bukan memilikinya - pola yang sama
# dipakai _hgo_avail/_sc_r di core/knobs.sh. Kosong kalau knobs.sh belum
# termuat, lalu _uk_esc pakai loop fallback-nya sendiri.
_kn_e=""

# Diagnostik ke log modul kalau logger sudah termuat (pola yang sama
# dengan hsin_scan_log di core/scan_cache.sh). Tidak pernah ke stdout,
# supaya baris JSON dan pesan aksi tidak tercampur.
_uk_log() {
    command -v hsin_log_warn >/dev/null 2>&1 && hsin_log_warn "user_knobs" "$1"
    return 0
}

# Escape satu string jadi badan string JSON (tanpa tanda kutip). Memakai
# escaper milik core/knobs.sh kalau sudah termuat - yang itu sudah
# menangani kutip, backslash, dan CR dari file node. Fallback-nya adalah
# loop per-karakter yang sama, supaya file ini tetap bisa dipakai sendiri
# tanpa urutan source tertentu. Nilai yang lolos validasi tidak mungkin
# mengandung ketiganya, jadi ini lapisan kedua, bukan yang pertama.
_uk_esc() {
    if command -v _kn_esc >/dev/null 2>&1; then
        _kn_esc "$1"
        _uk_e="$_kn_e"
        return 0
    fi
    _uk_e=""
    _uk_s="$1"
    while [ -n "$_uk_s" ]; do
        _uk_c="${_uk_s%"${_uk_s#?}"}"
        _uk_s="${_uk_s#?}"
        case "$_uk_c" in
            '"') _uk_e="${_uk_e}\\\"" ;;
            \\) _uk_e="${_uk_e}\\\\" ;;
            *) _uk_e="${_uk_e}${_uk_c}" ;;
        esac
    done
    return 0
}

# Klasifikasi satu key -> _uk_kind (cpu|gpu|io|fixed) dan _uk_num (1 kalau
# nilainya WAJIB angka). _uk_kind kosong = key tidak dikenal, return 1.
#
# Bentuk yang sah, semua tertutup:
#   cpu_policy_<id>_(gov|max_khz|min_khz|sched)
#   gpu_node_<nama>_(gov|max_khz|min_khz|sched)
#   io_block_<nama>_(gov|max_khz|min_khz|sched)
#   zram_algo | swappiness | tcp_cc | tfo
#
# Field diambil dari BELAKANG key, jadi nama node boleh mengandung '_'
# (mis. gpu_node_mali0_gov, io_block_sda_sched). Key dan nilainya dinilai
# lewat fungsi yang sama ini supaya tidak ada daftar key di dua tempat.
_uk_class() {
    _uk_kind=""
    _uk_num=0
    _uk_tk="$1"
    [ -n "$_uk_tk" ] || return 1
    _uk_len="${#_uk_tk}"
    [ "$_uk_len" -le "$HSIN_USER_KNOBS_MAX_KEYLEN" ] || return 1
    # Satu-satunya karakter yang boleh: huruf, angka, '_', '.'. Inilah
    # yang menutup injeksi baris config (spasi, '=', newline, ';', '`').
    case "$_uk_tk" in
        *[!A-Za-z0-9_.]*) return 1 ;;
    esac
    case "$_uk_tk" in
        zram_algo|tcp_cc) _uk_kind="fixed" ;;
        swappiness|tfo)
            _uk_kind="fixed"
            _uk_num=1
            ;;
    esac
    [ -n "$_uk_kind" ] && return 0

    _uk_tfield=""
    case "$_uk_tk" in
        *_gov) _uk_tfield="gov" ;;
        *_max_khz) _uk_tfield="max_khz" ;;
        *_min_khz) _uk_tfield="min_khz" ;;
        *_sched) _uk_tfield="sched" ;;
        *) return 1 ;;
    esac
    # _uk_tfield dari daftar tertutup tanpa karakter glob, tapi tetap
    # dikunci terpisah supaya suatu saat tidak tanpa sengaja jadi pola.
    _uk_tid="${_uk_tk%_"$_uk_tfield"}"
    case "$_uk_tid" in
        cpu_policy_*)
            case "${_uk_tid#cpu_policy_}" in
                ''|*[!0-9]*) return 1 ;;
            esac
            _uk_kind="cpu"
            ;;
        gpu_node_*)
            [ -n "${_uk_tid#gpu_node_}" ] || return 1
            _uk_kind="gpu"
            ;;
        io_block_*)
            [ -n "${_uk_tid#io_block_}" ] || return 1
            _uk_kind="io"
            ;;
        *) return 1 ;;
    esac
    case "$_uk_tfield" in
        max_khz|min_khz) _uk_num=1 ;;
    esac
    return 0
}

# $1 = key. 0 kalau key ada di daftar tertutup dan bentuknya benar.
hsin_uk_key_ok() {
    _uk_class "$1"
}

# $1 = key, $2 = value. 0 kalau value cocok dengan TIPE key-nya.
# Key angka (frekuensi kHz, swappiness, tfo) hanya menerima digit dan
# harus dalam rentang yang benar-benar diterima kernel, jadi tidak ada
# angka yang bisa membuat apply nanti gagal atau di-clamp kernel. Key token
# (governor, scheduler, algo zram, TCP CC) hanya menerima nama tanpa
# spasi supaya tidak mungkin menyuntik baris lain ke file.
hsin_uk_val_ok() {
    _uk_v="$2"
    _uk_class "$1" || return 1
    [ -n "$_uk_v" ] || return 1
    if [ "$_uk_num" = "1" ]; then
        case "$_uk_v" in
            *[!0-9]*) return 1 ;;
        esac
        # Panjang digit dibatasi supaya perbandingan shell tidak overflow
        # dan file tidak menyimpan angka tak berarti.
        [ "${#_uk_v}" -le 10 ] || return 1
        case "$1" in
            *_khz)
                # 100 kHz..5 GHz: di bawah slowest OPP device mana pun
                # dan di atas plafon kernel. 5 GHz = batas atas yang
                # jauh di atas semua SoC shipping sekarang.
                [ "$_uk_v" -ge 100000 ] 2>/dev/null || return 1
                [ "$_uk_v" -le 5000000 ] 2>/dev/null || return 1
                ;;
            swappiness) [ "$_uk_v" -le 200 ] 2>/dev/null || return 1 ;;
            tfo) [ "$_uk_v" -le 3 ] 2>/dev/null || return 1 ;;
        esac
        return 0
    fi
    case "$_uk_v" in
        *[!A-Za-z0-9_.-]*) return 1 ;;
    esac
    [ "${#_uk_v}" -le 32 ] || return 1
    return 0
}

# Cari satu key di file -> _uk_val. 0 kalau ketemu. Kunci "$1=" ditulis
# literal supaya karakter glob di key tidak pernah dicocokkan sebagai pola.
_uk_find() {
    _uk_val=""
    [ -f "$_uk_file" ] || return 1
    while IFS= read -r _uk_l || [ -n "$_uk_l" ]; do
        case "$_uk_l" in
            "$1="*) _uk_val="${_uk_l#*=}"; return 0 ;;
        esac
    done < "$_uk_file"
    return 1
}

# Tulis ulang file dengan SATU perubahan, atomic. set dan drop sengaja
# berbagi implementasi supaya tidak ada dua cara parse/filter yang bisa
# berbeda. Hasil di _uk_rw: ok | full (batas key tercapai) | err (tidak
# bisa menulis). _uk_found = 1 kalau key yang diminta ada di file lama,
# _uk_count = jumlah key valid yang akan tersisa.
_uk_rewrite() {
    _uk_mode="$1"
    _uk_wkey="$2"
    _uk_wval="$3"
    _uk_count=0
    _uk_found=0
    _uk_bad=0
    # Satu key satu baris. Key yang sudah ditulis dilewati, jadi rewrite
    # sekaligus menormalkan file yang punya baris kembar - file ini sendiri
    # tidak pernah membuatnya, jadi kembar hanya bisa datang dari luar.
    _uk_seen=" "
    _uk_rw="err"
    mkdir -p "$HSIN_DATA" 2>/dev/null
    _uk_tmp="$_uk_file.tmp.$$"
    : > "$_uk_tmp" 2>/dev/null || return 1
    if [ -f "$_uk_file" ]; then
        while IFS= read -r _uk_l || [ -n "$_uk_l" ]; do
            case "$_uk_l" in
                ''|'#'*) continue ;;
                *=*) ;;
                *) _uk_bad=$((_uk_bad + 1)); continue ;;
            esac
            _uk_lk="${_uk_l%%=*}"
            _uk_lv="${_uk_l#*=}"
            # Baris yang tidak lolos validasi TIDAK ditulis ulang: file
            # ini hanya boleh berisi key yang sah.
            if ! hsin_uk_val_ok "$_uk_lk" "$_uk_lv"; then
                _uk_bad=$((_uk_bad + 1))
                continue
            fi
            case "$_uk_seen" in
                *" $_uk_lk "*) _uk_bad=$((_uk_bad + 1)); continue ;;
            esac
            _uk_seen="$_uk_seen$_uk_lk "
            if [ "$_uk_lk" = "$_uk_wkey" ]; then
                _uk_found=1
                [ "$_uk_mode" = "drop" ] && continue
                printf '%s=%s\n' "$_uk_lk" "$_uk_wval" >> "$_uk_tmp"
            else
                printf '%s=%s\n' "$_uk_lk" "$_uk_lv" >> "$_uk_tmp"
            fi
            _uk_count=$((_uk_count + 1))
        done < "$_uk_file"
    fi
    if [ "$_uk_mode" = "set" ] && [ "$_uk_found" -eq 0 ]; then
        # Key baru. Melewati batas = TOLAK, bukan diam-diam menimpa
        # key lain: user harus tahu file-nya penuh.
        if [ "$_uk_count" -ge "$HSIN_USER_KNOBS_MAX_KEYS" ]; then
            rm -f "$_uk_tmp" 2>/dev/null
            _uk_rw="full"
            return 1
        fi
        printf '%s=%s\n' "$_uk_wkey" "$_uk_wval" >> "$_uk_tmp"
        _uk_count=$((_uk_count + 1))
    fi
    mv -f "$_uk_tmp" "$_uk_file" 2>/dev/null || {
        rm -f "$_uk_tmp" 2>/dev/null
        return 1
    }
    chmod 600 "$_uk_file" 2>/dev/null
    [ "$_uk_bad" -eq 0 ] || _uk_log "baris tidak valid/kembar dibuang dari user_knobs.env: $_uk_bad"
    _uk_rw="ok"
    return 0
}

# $1 = key, $2 = value. Nilai kosong berarti HAPUS key itu (bukan menyimpan
# string kosong) - ini cara aplikasi mengosongkan satu override tanpa
# kehilangan override lain.
hsin_uk_set() {
    [ "$#" -ge 2 ] || { echo "ERROR: hsin_uk_set butuh <key> <value>"; return 1; }
    if ! hsin_uk_key_ok "$1"; then
        # Key tidak dicetak di pesan error: input ini belum tervalidasi
        # dan bisa saja berisi karakter yang merusak baris output.
        echo "ERROR: key knob tidak dikenal (pola: cpu_policy_<id>_(gov|max_khz|min_khz|sched), gpu_node_<nama>_..., io_block_<nama>_..., zram_algo, swappiness, tcp_cc, tfo)"
        return 1
    fi
    _uk_k="$1"
    _uk_want=1
    if [ -z "$2" ]; then
        _uk_want=0
    elif ! hsin_uk_val_ok "$_uk_k" "$2"; then
        if [ "$_uk_num" = "1" ]; then
            echo "ERROR: $_uk_k: nilai harus angka (kHz 100000-5000000, swappiness 0-200, tfo 0-3)"
        else
            echo "ERROR: $_uk_k: nilai harus token 1-32 karakter huruf/angka"
        fi
        return 1
    fi
    if [ "$_uk_want" = "1" ]; then
        _uk_rewrite "set" "$_uk_k" "$2"
    else
        _uk_rewrite "drop" "$_uk_k" ""
    fi
    if [ "$_uk_rw" != "ok" ]; then
        if [ "$_uk_rw" = "full" ]; then
            echo "ERROR: batas $HSIN_USER_KNOBS_MAX_KEYS key override tercapai; hapus key lain dulu (knob-reset untuk kosongkan)"
        else
            echo "ERROR: $_uk_k gagal disimpan (tidak bisa menulis $HSIN_DATA)"
        fi
        return 1
    fi
    [ "$_uk_want" = "1" ] || return 0
    # Read back. "diterima" != "tersimpan": mv bisa gagal diam-diam di
    # filesystem yang tidak bisa ditulis, jadi nilai dicek ulang dari file.
    if _uk_find "$_uk_k" && [ "$_uk_val" = "$2" ]; then
        return 0
    fi
    echo "ERROR: $_uk_k tidak tersimpan (readback gagal)"
    return 1
}

# $1 = key. Menghapus satu override; idempoten (key yang memang tidak ada
# tetap 0, supaya aplikasi tidak perlu cek dulu sebelum menghapus).
hsin_uk_del() {
    [ "$#" -ge 1 ] || { echo "ERROR: hsin_uk_del butuh <key>"; return 1; }
    if ! hsin_uk_key_ok "$1"; then
        echo "ERROR: key knob tidak dikenal (pola: cpu_policy_<id>_(gov|max_khz|min_khz|sched), gpu_node_<nama>_..., io_block_<nama>_..., zram_algo, swappiness, tcp_cc, tfo)"
        return 1
    fi
    _uk_rewrite "drop" "$1" ""
    if [ "$_uk_rw" != "ok" ]; then
        echo "ERROR: gagal menghapus override $1"
        return 1
    fi
    return 0
}

# Hapus SEMUA override. Cetak jumlah key yang dihapus (dipakai aksi
# knob-reset untuk lapor ke user); 0 kalau memang tidak ada apa-apa.
hsin_uk_reset() {
    _uk_n=0
    if [ -f "$_uk_file" ]; then
        while IFS= read -r _uk_l || [ -n "$_uk_l" ]; do
            case "$_uk_l" in
                ''|'#'*) continue ;;
                *=*) ;;
                *) continue ;;
            esac
            _uk_lk="${_uk_l%%=*}"
            hsin_uk_key_ok "$_uk_lk" && _uk_n=$((_uk_n + 1))
        done < "$_uk_file"
    fi
    if [ -e "$_uk_file" ] && ! rm -f "$_uk_file" 2>/dev/null; then
        echo "ERROR: tidak bisa menghapus override ($_uk_file)"
        return 1
    fi
    printf '%s\n' "$_uk_n"
    return 0
}

# Cetak SATU BARIS JSON: {"count":N,"overrides":{"key":"value",...}}
# Nilai ikut dicetak karena inilah satu-satunya jalan aplikasi untuk tahu
# override yang tersimpan - aksi knobs hanya melaporkan nilai LIVE, bukan
# pilihan user. Baris yang tidak valid dilewati supaya output tetap JSON
# valid walau file pernah rusak atau diisi dari luar modul.
hsin_uk_list() {
    _uk_n=0
    _uk_obj=""
    # Spasi di depan/sesudah supaya pencocokan key jadi utuh (key sah
    # tidak pernah mengandung spasi). Dipakai supaya key kembar - yang
    # hanya mungkin kalau file diisi dari luar modul - dihitung sekali:
    # count harus jujur dan JSON tidak boleh punya kunci kembar.
    _uk_seen=" "
    if [ -f "$_uk_file" ]; then
        while IFS= read -r _uk_l || [ -n "$_uk_l" ]; do
            case "$_uk_l" in
                ''|'#'*) continue ;;
                *=*) ;;
                *) continue ;;
            esac
            _uk_lk="${_uk_l%%=*}"
            _uk_lv="${_uk_l#*=}"
            hsin_uk_val_ok "$_uk_lk" "$_uk_lv" || continue
            case "$_uk_seen" in
                *" $_uk_lk "*) continue ;;
            esac
            _uk_seen="$_uk_seen$_uk_lk "
            _uk_esc "$_uk_lk"
            _uk_ke="$_uk_e"
            _uk_esc "$_uk_lv"
            _uk_ve="$_uk_e"
            [ "$_uk_n" -eq 0 ] || _uk_obj="${_uk_obj},"
            _uk_obj="${_uk_obj}\"${_uk_ke}\":\"${_uk_ve}\""
            _uk_n=$((_uk_n + 1))
        done < "$_uk_file"
    fi
    printf '{"count":%s,"overrides":{%s}}\n' "$_uk_n" "$_uk_obj"
    return 0
}

# ============================================================
# SISI BACA (dipakai engine saat apply)
# ============================================================
# MENGAPA perlu: aksi knob-set/knob-reset/knob-list sudah bisa menyimpan
# pilihan user, tapi tanpa pembaca di jalur apply pilihan itu tidak
# berefek sama sekali. Engine TIDAK lewat hsin_profile_get (nilai profil
# diturunkan dari `case "$_profile"` = nama profil), jadi override harus
# disisipkan di titik engine menulis tiap node - accessor di bawah
# hanya provide "ada/tidak + nilai", keputusan tulis tetap milik engine
# (supaya governor/scheduler/algo tetap divalidasi ke daftar node).
#
# Init hanya sekali per proses: file ini di-source oleh beberapa engine
# dalam satu apply, dan cache harus bertahan di antara source-source itu.
if [ -z "$_uk_inited" ]; then
    _uk_inited=1
    _uk_cache=""
    _uk_cache_done=""
    _uk_used_n=0
    _uk_sum_done=""
fi

# Cache per-proses: file override dibaca SATU kali, lalu disimpan dipisah
# spasi ("key=val key=val"). Nilai yang lolos hsin_uk_val_ok tidak pernah
# mengandung spasi (key angka = digit, key token = [A-Za-z0-9_.-]), jadi
# pemecahan spasi ini identik dengan isi file dan tidak butuh eval/source.
# Satu apply menulis puluhan node; satu baca file per node itu biaya
# yang tidak perlu.
_uk_load() {
    [ -n "$_uk_cache_done" ] && return 0
    _uk_cache_done=1
    _uk_cache=""
    [ -f "$_uk_file" ] || return 0
    while IFS= read -r _uk_l || [ -n "$_uk_l" ]; do
        case "$_uk_l" in
            ''|'#'*) continue ;;
            *=*) ;;
            *) continue ;;
        esac
        _uk_lk="${_uk_l%%=*}"
        _uk_lv="${_uk_l#*=}"
        # Baris yang tidak lolos validasi diabaikan, sama seperti di list:
        # file ini secara teori bisa diisi dari luar modul.
        hsin_uk_val_ok "$_uk_lk" "$_uk_lv" || continue
        _uk_cache="${_uk_cache:+$_uk_cache }$_uk_lk=$_uk_lv"
    done < "$_uk_file"
    return 0
}

# $1 = key. Cetak nilai override, atau return 1 kalau key itu tidak ada
# (tanpa output). Kunci ditulis literal supaya karakter glob di key tidak
# pernah dicocokkan sebagai pola.
hsin_uk_get() {
    [ "$#" -ge 1 ] || return 1
    _uk_load
    _uk_ifs="$IFS"
    IFS=' '
    for _uk_item in $_uk_cache; do
        case "$_uk_item" in
            "$1="*)
                IFS="$_uk_ifs"
                printf '%s\n' "${_uk_item#*=}"
                return 0
                ;;
        esac
    done
    IFS="$_uk_ifs"
    return 1
}

# Nama node (devfreq/block) -> _uk_sn. WAJIB identik dengan sanitizeNode()
# di aplikasi (app/.../ui/knobs/KnobsRowBuilder.kt): huruf dan angka ASCII
# dipertahankan, karakter lain jadi '_', maksimum 40 karakter. Kalau
# berbeda, kunci yang ditulis aplikasi tidak akan pernah ketemu di sini.
_uk_sanitize() {
    _uk_sn=""
    _uk_sr="$1"
    _uk_si=0
    while [ -n "$_uk_sr" ] && [ "$_uk_si" -lt 40 ]; do
        _uk_sc="${_uk_sr%"${_uk_sr#?}"}"
        _uk_sr="${_uk_sr#?}"
        case "$_uk_sc" in
            [A-Za-z0-9]) _uk_sn="${_uk_sn}${_uk_sc}" ;;
            *)           _uk_sn="${_uk_sn}_" ;;
        esac
        _uk_si=$((_uk_si + 1))
    done
    return 0
}

# $1 = id policy CPU, $2 = gov|max_khz|min_khz (daftar tertutup: nama node
# dari device, jadi field-nya ikut ditutup supaya key tak sengaja tidak
# mungkin terbentuk).
hsin_uk_cpu_field() {
    [ "$#" -ge 2 ] || return 1
    case "$2" in
        gov|max_khz|min_khz) ;;
        *) return 1 ;;
    esac
    hsin_uk_get "cpu_policy_$1_$2"
}

# $1 = node devfreq (path penuh atau basename), $2 = gov|max_khz
hsin_uk_gpu_field() {
    [ "$#" -ge 2 ] || return 1
    case "$2" in
        gov|max_khz) ;;
        *) return 1 ;;
    esac
    _uk_sanitize "${1##*/}"
    hsin_uk_get "gpu_node_${_uk_sn}_$2"
}

# $1 = block device (path penuh atau basename), $2 = sched
hsin_uk_io_field() {
    [ "$#" -ge 2 ] || return 1
    [ "$2" = "sched" ] || return 1
    _uk_sanitize "${1##*/}"
    hsin_uk_get "io_block_${_uk_sn}_sched"
}

# $1 = tag engine, $2 = key, $3 = nilai. Dipanggil engine tepat setelah
# override diterima dan jadi nilai yang ditulis, jadi ini satu-satunya
# tempat yang menghitung override "dipakai" (yang ditolak tidak di sini).
hsin_uk_used() {
    _uk_used_n=$((_uk_used_n + 1))
    command -v hsin_log_info >/dev/null 2>&1 && \
        hsin_log_info "$1" "override: $2=$3 dipakai"
    return 0
}

# Ringkasan SATU baris ke apply.log. Dipanggil dari langkah terakhir
# pipeline apply yang punya-knob (engine network, lihat
# core/apply_engines.sh) supaya $_uk_used_n sudah final. Kalau apply
# berhenti sebelum titik itu, tidak ada ringkasan - baris "override:"
# per engine di boot.log tetap jadi jejaknya, jadi tidak ada yang hilang.
hsin_uk_log_summary() {
    [ -n "$_uk_sum_done" ] && return 0
    _uk_sum_done=1
    [ "$_uk_used_n" -gt 0 ] 2>/dev/null || return 0
    command -v hsin_log_apply >/dev/null 2>&1 && \
        hsin_log_apply "knobs" "override: $_uk_used_n key dipakai"
    return 0
}

# Cache diisi di parent saat file ini di-source, bukan lazily di accessor:
# accessor dipanggil di dalam $( ) (= subshell), jadi cache yang baru
# dibangun di dalam subshell hilang lagi dan file akan dibaca ulang untuk
# tiap node.
_uk_load

return 0 2>/dev/null || true
