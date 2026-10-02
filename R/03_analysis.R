# =============================================================================
# 03_analysis.R
# Menghitung seluruh data turunan untuk dasbor.
#
# Dipisahkan dari index.qmd supaya perhitungan dapat diperiksa dan direproduksi
# sendiri, dan supaya proses render dasbor tetap ringan.
#
# Input : data/processed/brs_docs.csv, brs_tokens.csv
# Output: data/viz/*.csv
# =============================================================================

pkgs <- c("dplyr", "readr", "stringr", "tidyr", "tidytext", "igraph")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  stop("Paket belum terpasang: ", paste(missing, collapse = ", "), "\n",
       'install.packages(c("', paste(missing, collapse = '", "'), '"))',
       call. = FALSE)
}

suppressPackageStartupMessages({
  library(dplyr); library(readr); library(stringr); library(tidyr)
  library(tidytext); library(igraph)
})

dir.create("data/viz", recursive = TRUE, showWarnings = FALSE)

docs   <- read_csv("data/processed/brs_docs.csv",   show_col_types = FALSE)
tokens <- read_csv("data/processed/brs_tokens.csv", show_col_types = FALSE)

message("Dokumen: ", nrow(docs), " | Token: ", nrow(tokens))

# =============================================================================
# A. TOPIK TEKS
# =============================================================================

# A1. Frekuensi kata, dirinci per domain dan tahun supaya dasbor bisa memfilter
freq_kata <- tokens |>
  count(domain, tahun, kata_dasar, name = "n") |>
  group_by(kata_dasar) |>
  mutate(n_total = sum(n)) |>
  ungroup() |>
  arrange(desc(n_total), kata_dasar)

write_csv(freq_kata, "data/viz/freq_kata.csv")

# A2. TF-IDF: kata paling khas tiap subjek.
# Dipakai karena korpus sangat templatik, sehingga frekuensi mentah hanya
# memunculkan kata umum yang sama di semua subjek.
tfidf <- tokens |>
  count(subjek, kata_dasar, name = "n") |>
  bind_tf_idf(kata_dasar, subjek, n) |>
  group_by(subjek) |>
  slice_max(tf_idf, n = 15, with_ties = FALSE) |>
  ungroup() |>
  arrange(subjek, desc(tf_idf))

write_csv(tfidf, "data/viz/tfidf_subjek.csv")

# A3. Tren terbitan per tahun dan domain
tren_dokumen <- docs |>
  count(tahun, domain, name = "n_dokumen") |>
  complete(tahun, domain, fill = list(n_dokumen = 0))

write_csv(tren_dokumen, "data/viz/tren_dokumen.csv")

# A4. Arah perubahan yang dilaporkan BPS.
# Ini temuan utama proyek, jadi dihitung dari keluarga kata, bukan satu kata.
KEL_NAIK  <- c("naik","kenaikan","meningkat","peningkatan","tumbuh",
               "pertumbuhan","tambah","kuat","penguatan","ekspansi")
KEL_TURUN <- c("turun","penurunan","menurun","kurang","pengurangan",
               "lambat","perlambatan","kontraksi","lemah","rosot")

arah <- tokens |>
  mutate(arah = case_when(
    kata_dasar %in% KEL_NAIK  ~ "Naik",
    kata_dasar %in% KEL_TURUN ~ "Turun",
    TRUE ~ NA_character_
  )) |>
  filter(!is.na(arah)) |>
  count(tahun, domain, arah, name = "n")

write_csv(arah, "data/viz/arah_perubahan.csv")

# A5. Indeks dokumen untuk tabel pencarian kata kunci
indeks_dokumen <- docs |>
  mutate(cuplikan = str_trunc(teks, 300)) |>
  select(brs_id, tanggal, tahun, kode_csa, domain, divisi, subjek,
         judul = title, cuplikan, n_kata)

write_csv(indeks_dokumen, "data/viz/indeks_dokumen.csv")

# =============================================================================
# B. TOPIK JARINGAN  (ko-okurensi kata bersebelahan)
# =============================================================================
# Pasangan dibentuk dari token yang BERSEBELAHAN setelah penyaringan stopword,
# sehingga sisi menghubungkan kata isi, bukan kata fungsi.

AMBANG <- c(50, 100, 200)   # tiga ambang bobot sisi, jadi filter di dasbor

pasangan <- tokens |>
  arrange(brs_id) |>
  group_by(brs_id) |>
  mutate(kata2 = lead(kata_dasar)) |>
  ungroup() |>
  filter(!is.na(kata2), kata_dasar != kata2) |>
  mutate(
    dari = pmin(kata_dasar, kata2),
    ke   = pmax(kata_dasar, kata2)
  ) |>
  count(dari, ke, name = "bobot") |>
  filter(bobot >= min(AMBANG)) |>
  arrange(desc(bobot))

write_csv(pasangan, "data/viz/jaringan_sisi.csv")
message("Sisi jaringan (bobot >= ", min(AMBANG), "): ", nrow(pasangan))

# Simpul: sentralitas dan komunitas dihitung per ambang
simpul_list <- lapply(AMBANG, function(amb) {

  e <- filter(pasangan, bobot >= amb)
  if (nrow(e) == 0) return(NULL)

  g <- graph_from_data_frame(select(e, dari, ke, weight = bobot),
                             directed = FALSE)

  kom <- cluster_louvain(g, weights = E(g)$weight)

  tibble(
    ambang      = amb,
    kata        = V(g)$name,
    derajat     = as.integer(degree(g)),
    kekuatan    = as.numeric(strength(g, weights = E(g)$weight)),
    keantaraan  = as.numeric(betweenness(g, weights = 1 / E(g)$weight,
                                         normalized = TRUE)),
    komunitas   = as.integer(membership(kom))
  )
})

simpul <- bind_rows(simpul_list)
write_csv(simpul, "data/viz/jaringan_simpul.csv")

for (amb in AMBANG) {
  s <- filter(simpul, ambang == amb)
  message("  ambang ", amb, ": ", nrow(s), " simpul, ",
          sum(pasangan$bobot >= amb), " sisi, ",
          n_distinct(s$komunitas), " komunitas")
}

# Matriks ketetanggaan: representasi kedua, dibatasi 40 kata berderajat
# tertinggi agar tetap terbaca.
inti <- simpul |>
  filter(ambang == 100) |>
  slice_max(kekuatan, n = 40, with_ties = FALSE) |>
  pull(kata)

matriks <- pasangan |>
  filter(dari %in% inti, ke %in% inti)

# Dilengkapi arah kebalikannya supaya matriks tampil simetris
matriks <- bind_rows(
  matriks,
  rename(matriks, dari = ke, ke = dari)
) |>
  distinct(dari, ke, .keep_all = TRUE)

write_csv(matriks, "data/viz/jaringan_matriks.csv")

# =============================================================================
# C. TOPIK HIERARKI  (Domain -> Divisi -> Subjek -> Dokumen)
# =============================================================================
# Ukuran  = jumlah dokumen
# Warna   = rata-rata panjang dokumen (variabel BERBEDA dari ukuran,
#           sesuai ketentuan Lampiran A)

hierarki <- docs |>
  group_by(domain, divisi, subjek) |>
  summarise(
    n_dokumen   = n(),
    rata_kata   = round(mean(n_kata)),
    kode_csa    = first(kode_csa),
    tahun_awal  = min(tahun, na.rm = TRUE),
    tahun_akhir = max(tahun, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(domain, divisi, desc(n_dokumen))

write_csv(hierarki, "data/viz/hierarki.csv")

# Bentuk sunburst/treemap plotly: id - label - parent
simpul_akar <- tibble(
  id = "BRS", label = "Seluruh BRS", parent = "",
  nilai = nrow(docs), warna = round(mean(docs$n_kata))
)

simpul_domain <- hierarki |>
  group_by(domain) |>
  summarise(nilai = sum(n_dokumen),
            warna = round(weighted.mean(rata_kata, n_dokumen)), .groups = "drop") |>
  transmute(id = domain, label = domain, parent = "BRS", nilai, warna)

simpul_divisi <- hierarki |>
  group_by(domain, divisi) |>
  summarise(nilai = sum(n_dokumen),
            warna = round(weighted.mean(rata_kata, n_dokumen)), .groups = "drop") |>
  transmute(id = paste(domain, divisi, sep = " | "),
            label = divisi, parent = domain, nilai, warna)

simpul_subjek <- hierarki |>
  transmute(id = paste(domain, divisi, subjek, sep = " | "),
            label = str_trunc(subjek, 45),
            parent = paste(domain, divisi, sep = " | "),
            nilai = n_dokumen, warna = rata_kata)

pohon <- bind_rows(simpul_akar, simpul_domain, simpul_divisi, simpul_subjek) |>
  distinct(id, .keep_all = TRUE)

write_csv(pohon, "data/viz/hierarki_pohon.csv")

# =============================================================================
# Ringkasan
# =============================================================================

cat("\n================= RINGKASAN DATA VISUALISASI =================\n")
cat("freq_kata.csv        :", nrow(freq_kata), "baris\n")
cat("tfidf_subjek.csv     :", nrow(tfidf), "baris,",
    n_distinct(tfidf$subjek), "subjek\n")
cat("tren_dokumen.csv     :", nrow(tren_dokumen), "baris\n")
cat("arah_perubahan.csv   :", nrow(arah), "baris\n")
cat("jaringan_sisi.csv    :", nrow(pasangan), "sisi\n")
cat("jaringan_simpul.csv  :", nrow(simpul), "baris (3 ambang)\n")
cat("jaringan_matriks.csv :", nrow(matriks), "sel\n")
cat("hierarki_pohon.csv   :", nrow(pohon), "simpul pohon\n\n")

cat("Arah perubahan, total korpus:\n")
print(as.data.frame(count(arah, arah, wt = n)))

cat("\n10 sisi jaringan terkuat:\n")
print(as.data.frame(head(pasangan, 10)))
cat("=============================================================\n")
