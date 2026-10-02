# =============================================================================
# 02_preprocess.R
# Pra-pemrosesan korpus Berita Resmi Statistik BPS
#
# Tahapan:
#   1. Pembersihan markup HTML/Word dari abstrak, membedakan tag blok dan
#      tag inline agar kata tidak tersambung maupun terbelah.
#   2. Pelekatan taksonomi CSA v1.1 berdasarkan subj_id.
#   3. Case folding dan tokenisasi.
#   4. Penyaringan stopword Bahasa Indonesia dan Bahasa Inggris, stopword
#      khusus korpus, serta ambang frekuensi minimum.
#   5. Stemming Nazief & Andriani atas kosakata unik, dengan daftar istilah
#      terlindungi untuk nama diri dan akronim.
#
# Input : data/raw/brs_raw.csv
# Output: data/processed/brs_docs.csv
#         data/processed/brs_tokens.csv
#         data/processed/kamus_stem.csv
#         data/processed/istilah_terlindungi.csv
# =============================================================================

pkgs <- c("dplyr", "readr", "stringr", "tidyr", "tidytext", "stopwords", "katadasaR")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  stop("Paket belum terpasang: ", paste(missing, collapse = ", "), call. = FALSE)
}

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(tidyr)
  library(tidytext); library(stopwords); library(katadasaR)
})

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

FREK_MIN <- 5   # kata dengan frekuensi di bawah ini dibuang

# =============================================================================
# 1. Pembersihan markup, sadar-blok
# =============================================================================

TAG_BLOK <- "p|div|br|li|ul|ol|tr|td|th|table|h[1-6]|section|article|blockquote"

bersihkan_html <- function(x) {
  x <- as.character(x); x[is.na(x)] <- ""

  # Komentar kondisional MSO dan blok non-teks
  x <- str_remove_all(x, regex("<!--.*?-->", dotall = TRUE))
  x <- str_remove_all(x, regex("<xml.*?</xml>", dotall = TRUE, ignore_case = TRUE))
  x <- str_remove_all(x, regex("<style.*?</style>", dotall = TRUE, ignore_case = TRUE))
  x <- str_remove_all(x, regex("<script.*?</script>", dotall = TRUE, ignore_case = TRUE))

  # Tag BLOK -> spasi (memisahkan kata antar paragraf/sel tabel)
  x <- str_replace_all(x, regex(paste0("</?(?:", TAG_BLOK, ")\\b[^>]*>"),
                                ignore_case = TRUE), " ")
  # Tag INLINE -> dihapus (menyambung kata yang terbelah <span>)
  x <- str_remove_all(x, "<[^>]+>")

  # Entitas HTML yang umum muncul
  x <- str_replace_all(x, c(
    "&nbsp;" = " ", "&amp;" = "&", "&lt;" = "<", "&gt;" = ">",
    "&quot;" = "\"", "&#39;" = "'", "&rsquo;" = "'", "&lsquo;" = "'",
    "&ldquo;" = "\"", "&rdquo;" = "\"", "&ndash;" = "-", "&mdash;" = "-"
  ))
  x <- str_remove_all(x, "&[a-zA-Z#0-9]+;")
  x <- str_replace_all(x, " ", " ")
  str_squish(x)
}

# =============================================================================
# 2. Taksonomi CSA v1.1
# =============================================================================
# subj_id dari WebAPI BPS mengikuti urutan kode Classification of Statistical
# Activities (CSA) v1.1, sehingga hierarki direkonstruksi, bukan dikarang.
# Level: Domain -> Divisi -> Subjek -> Dokumen

csa <- tribble(
  ~subj_id, ~kode_csa, ~domain,                                     ~divisi,
  519, "1.1",   "Statistik Demografi dan Sosial",              "Populasi dan Migrasi",
  520, "1.2",   "Statistik Demografi dan Sosial",              "Ketenagakerjaan",
  523, "1.5",   "Statistik Demografi dan Sosial",              "Pendapatan dan Konsumsi",
  526, "1.8",   "Statistik Demografi dan Sosial",              "Hukum dan Kriminal",
  527, "1.9",   "Statistik Demografi dan Sosial",              "Budaya",
  528, "1.10",  "Statistik Demografi dan Sosial",              "Aktivitas Politik dan Komunitas",
  531, "2.1",   "Statistik Ekonomi",                           "Statistik Makroekonomi",
  532, "2.3",   "Statistik Ekonomi",                           "Statistik Bisnis",
  533, "2.4",   "Statistik Ekonomi",                           "Statistik Sektoral",
  557, "2.4.1", "Statistik Ekonomi",                           "Statistik Sektoral",
  559, "2.4.3", "Statistik Ekonomi",                           "Statistik Sektoral",
  560, "2.4.4", "Statistik Ekonomi",                           "Statistik Sektoral",
  561, "2.4.5", "Statistik Ekonomi",                           "Statistik Sektoral",
  562, "2.4.6", "Statistik Ekonomi",                           "Statistik Sektoral",
  535, "2.6",   "Statistik Ekonomi",                           "Perdagangan Internasional",
  536, "2.7",   "Statistik Ekonomi",                           "Harga",
  537, "2.8",   "Statistik Ekonomi",                           "Biaya Tenaga Kerja",
  538, "2.9",   "Statistik Ekonomi",                           "IPTEK dan Inovasi",
  563, "3.3.1", "Statistik Lingkungan Hidup dan Multi-domain", "Statistik Multi-domain",
  564, "3.3.2", "Statistik Lingkungan Hidup dan Multi-domain", "Statistik Multi-domain",
  568, "3.3.5", "Statistik Lingkungan Hidup dan Multi-domain", "Statistik Multi-domain"
)

# =============================================================================
# 3. Tabel dokumen
# =============================================================================

message("Membaca korpus mentah ...")
raw <- read_csv("data/raw/brs_raw.csv", show_col_types = FALSE)

message("Membersihkan markup ...")
docs <- raw |>
  mutate(teks_bersih = bersihkan_html(abstract)) |>
  left_join(csa, by = "subj_id") |>
  mutate(
    domain   = replace_na(domain,   "Tidak Berkategori"),
    divisi   = replace_na(divisi,   "Tidak Berkategori"),
    subjek   = replace_na(subj,     "Tidak Berkategori"),
    kode_csa = replace_na(kode_csa, "-"),
    tanggal  = as.Date(rl_date),
    tahun    = as.integer(format(tanggal, "%Y")),
    bulan    = as.integer(format(tanggal, "%m")),
    teks     = str_squish(paste(title, teks_bersih)),
    n_kata   = str_count(teks, "\\S+")
  ) |>
  select(brs_id, tanggal, tahun, bulan, kode_csa, domain, divisi, subjek,
         title, teks, n_kata, pdf)

write_csv(docs, "data/processed/brs_docs.csv")
message("  ", nrow(docs), " dokumen.")

# =============================================================================
# 4. Istilah terlindungi (tidak di-stem)
# =============================================================================

wilayah <- c(
  "aceh","ambon","balikpapan","bandung","bangka","banjarmasin","banten",
  "banyuwangi","batam","baubau","bekasi","belitung","bengkulu","bima","bogor",
  "bukittinggi","bulukumba","bungo","cilacap","cilegon","cirebon","denpasar",
  "depok","dumai","gorontalo","gunungsitoli","halmahera","jakarta","jambi",
  "jawa","jayapura","jayawijaya","jember","kalimantan","karimun","kediri",
  "kendari","kerinci","kotabaru","kotamobagu","kudus","kupang","lampung",
  "lhokseumawe","luwuk","madiun","majene","makassar","malang","maluku","mamuju",
  "manado","manokwari","maumere","medan","merauke","meulaboh","minahasa",
  "mukomuko","nabire","nanggroe","padang","padangsidimpuan","palangkaraya",
  "palembang","palopo","palu","pangkalpinang","papua","pasaman","pekanbaru",
  "pematangsiantar","pontianak","probolinggo","purwokerto","riau","samarinda",
  "sampit","semarang","serang","serdang","siantar","sibolga","singaraja",
  "singkawang","sintang","sorong","sukabumi","sulawesi","sumatera","sumenep",
  "surabaya","surakarta","tangerang","tanjung","tarakan","tasikmalaya","tegal",
  "ternate","timika","timor","tual","waingapu","watampone","yogyakarta",
  "bali","selor","toli","metro","karo","deli","enim","pare","muara",
  "nusa","nusantara","indonesia"
)

negara <- c("amerika","arab","asean","australia","eropa","india","jepang",
            "korea","malaysia","saudi","singapura","thailand","tiongkok",
            "darussalam","madinah","makkah","mekkah","arafah")

akronim <- c("adhb","adhk","gini","ihpb","ihk","ikjhi","ikrt","ipak","iptik",
             "kbli","lnprt","mppt","ntp","ntup","pdrb","pmtb","podes","poldis",
             "ppkm","rtup","sakernas","skjhi","slta","sltp","sphpn","sptk",
             "supas","susenas","tpak","wisman","wisnas","wisnus","covid",
             "migas","nonmigas","ratio")

# Nama diri yang rusak bila dilewatkan stemmer
salah_stem <- c("pelaku","peluang","pelayanan","perasaan","pengadaan",
                "penduduk","negeri","petani","pegawai","bersekolah",
                "dipertahankan","memuaskan","kepuasan","kekerasan","kesiapan",
                "pergudangan","terapung","pengurangan","diperoleh","dibedakan",
                "perda","mengunjungi")

terlindungi <- unique(c(wilayah, negara, akronim, salah_stem))
write_csv(tibble(istilah = terlindungi), "data/processed/istilah_terlindungi.csv")

# =============================================================================
# 5. Tokenisasi dan penyaringan
# =============================================================================

sw_id    <- stopwords::stopwords("id", source = "stopwords-iso")
sw_en    <- stopwords::stopwords("en", source = "snowball")
sw_bulan <- c("januari","februari","maret","april","mei","juni","juli",
              "agustus","september","oktober","november","desember")
sw_satuan <- c("persen","miliar","juta","triliun","ribu","rupiah","dolar",
               "indeks","nilai","sebesar","mencapai","tercatat","dibanding",
               "dibandingkan","mengalami","sedangkan","yoy","mtm","ytd")

# Daftar stopwords-iso Bahasa Indonesia tidak simetris untuk korpus ini: ia
# membuang "naik", "tinggi", "besar", "kecil", "tambah", "kurang" tetapi
# membiarkan "turun", "rendah", "tumbuh". Pada korpus yang isinya laporan
# perubahan angka, ketimpangan itu membalik kesimpulan (keluarga kata naik
# 7.991 vs turun 4.186 pada teks mentah). Kata arah dan besaran dikembalikan.
kata_dipertahankan <- c("naik","turun","tinggi","rendah","besar","kecil",
                        "tambah","kurang","tumbuh","kuat","lemah","cepat",
                        "lambat","baik","buruk")

sw_semua <- setdiff(
  unique(c(sw_id, sw_en, sw_bulan, sw_satuan)),
  kata_dipertahankan
)

message("Tokenisasi ...")
tokens <- docs |>
  select(brs_id, tahun, bulan, kode_csa, domain, divisi, subjek, teks) |>
  mutate(teks = str_to_lower(teks),
         teks = str_replace_all(teks, "[^a-z\\s]", " ")) |>
  unnest_tokens(kata, teks, token = "words") |>
  filter(str_length(kata) > 3, !kata %in% sw_semua)

n_sebelum <- n_distinct(tokens$kata)

# Penyaringan frekuensi: membuang salah ketik sumber dan sisa token gabungan
frek <- count(tokens, kata, name = "frek")
tokens <- tokens |>
  semi_join(filter(frek, frek >= FREK_MIN), by = "kata")

message("  ", nrow(tokens), " token; kosakata ", n_sebelum, " -> ",
        n_distinct(tokens$kata), " setelah saring frekuensi >= ", FREK_MIN)

# =============================================================================
# 6. Stemming Nazief & Andriani, atas kosakata unik saja
# =============================================================================

vocab <- sort(unique(tokens$kata))
message("Stemming ", length(vocab), " kata unik ...")

kamus_stem <- tibble(
  kata = vocab,
  dilindungi = vocab %in% terlindungi
) |>
  mutate(
    kata_dasar = if_else(
      dilindungi,
      kata,
      vapply(kata, function(w) {
        tryCatch(as.character(katadasaR::katadasaR(w)), error = function(e) w)
      }, character(1), USE.NAMES = FALSE)
    ),
    # Stem yang menyisakan kurang dari empat huruf dibatalkan
    kata_dasar = if_else(str_length(kata_dasar) < 4, kata, kata_dasar)
  )

write_csv(kamus_stem, "data/processed/kamus_stem.csv")

tokens <- tokens |>
  left_join(select(kamus_stem, kata, kata_dasar), by = "kata") |>
  mutate(kata_dasar = coalesce(kata_dasar, kata))

write_csv(tokens, "data/processed/brs_tokens.csv")

# =============================================================================
# Ringkasan
# =============================================================================

cat("\n================= RINGKASAN PRA-PEMROSESAN =================\n")
cat("Dokumen                 :", nrow(docs), "\n")
cat("Token final             :", nrow(tokens), "\n")
cat("Kosakata (asli)         :", length(vocab), "\n")
cat("Kosakata (kata dasar)   :", n_distinct(kamus_stem$kata_dasar), "\n")
cat("Istilah terlindungi     :", sum(kamus_stem$dilindungi), "dari",
    length(terlindungi), "yang terdaftar\n")
cat("Token gabungan tersisa  :", sum(str_length(vocab) >= 15), "\n\n")

cat("Dokumen per domain CSA:\n")
print(as.data.frame(count(docs, domain, sort = TRUE)))

cat("\n15 kata dasar paling sering:\n")
print(as.data.frame(head(count(tokens, kata_dasar, sort = TRUE), 15)))

cat("\nCek nama diri (harus utuh, tidak terpotong):\n")
print(as.data.frame(
  filter(kamus_stem, kata %in% c("bali","bekasi","asean","gini","maluku",
                                 "penduduk","petani","makkah"))
))

cat("\nCek keluarga kata arah (naik harus jauh di atas turun):\n")
print(as.data.frame(
  filter(count(tokens, kata_dasar), kata_dasar %in% c("naik","turun","tingkat","tumbuh"))
))
cat("===============================================================\n")
