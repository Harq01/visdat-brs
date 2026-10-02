# Bahasa Statistik Resmi

Analisis teks, jaringan ko-okurensi, dan hierarki subjek pada korpus **Berita
Resmi Statistik (BRS) Badan Pusat Statistik, 2015–2025**.

Proyek ini tidak menganalisis angka yang dirilis BPS, melainkan **teks
rilisnya**: apa yang dipilih untuk diberitakan, kata apa yang dipakai, dan
bagaimana subjek-subjeknya tersusun.

**Laman proyek:** https://harq01.github.io/visdat-brs/

UAS Visualisasi Data dan Informasi (K203407), Program Studi Komputasi
Statistik, Politeknik Statistika STIS.
M. Faruq Hafidzullah Erfaringga — 222313186.

---

## Topik visualisasi

Memenuhi tiga dari enam topik pada soal:

| Topik | Visualisasi |
|---|---|
| **Data teks** | frekuensi kata, TF-IDF per subjek (panel kecil), tren kata arah, rasio naik–turun, tabel dokumen dengan pencarian |
| **Data berjaring** | jaringan ko-okurensi *force-directed* (3 ambang bobot) dan matriks ketetanggaan |
| **Data berhierarki** | sunburst dan treemap atas taksonomi CSA, empat tingkat |

## Temuan utama

1. **89,5% BRS adalah statistik ekonomi.** Statistik demografi dan sosial
   hanya 4,3%. Apa yang rutin dikomunikasikan BPS ke publik jauh lebih sempit
   daripada apa yang diukurnya.
2. **Rasio kata kenaikan terhadap penurunan bergerak mengikuti siklus
   ekonomi.** Terendah pada 2020 (1,17:1), tertinggi pada 2022 (2,73:1).
3. **Pandemi hampir tidak disebut namanya.** Sepanjang 2020 kata *pandemi*
   muncul satu kali di seluruh korpus; jejaknya ada pada rasio arah, bukan
   pada kosakatanya.
4. **Komunitas jaringan memetakan subjek statistik tanpa diberi tahu
   subjeknya** — tiap subjek BRS punya rumus kalimat sendiri yang berulang.

## Data

- **Sumber:** Berita Resmi Statistik, BPS, domain nasional (kode `0000`),
  tahun terbit 2015–2025.
- **Cara akses:** [WebAPI BPS](https://webapi.bps.go.id), model
  `pressrelease`, diakses 2 Oktober 2026.
- **Jumlah:** 1.121 dokumen, 96.611 token setelah pra-pemrosesan, 764
  kosakata, 682 kata dasar.
- Seluruh dokumen yang dikembalikan API dipakai; tidak ada yang dibuang.

Taksonomi hierarki mengikuti *Classification of Statistical Activities* (CSA)
v1.1 yang dikelola UNECE dan dipakai BPS. Nilai `subj_id` pada WebAPI
mengikuti urutan kode CSA, sehingga hierarki direkonstruksi dari data, bukan
dikelompokkan sendiri.

## Struktur repositori

```
visdat-brs/
├── R/
│   ├── 01_fetch_brs.R      # tarik korpus dari WebAPI BPS
│   ├── 02_preprocess.R     # bersihkan HTML, tokenisasi, stopword, stemming
│   └── 03_analysis.R       # hitung data turunan untuk tiap visualisasi
├── data/
│   ├── raw/                # korpus mentah apa adanya dari API
│   ├── processed/          # dokumen bersih, token, kamus stemming
│   └── viz/                # data siap pakai per visualisasi
├── index.qmd               # dasbor
├── custom.scss             # tema tampilan
├── _quarto.yml
└── docs/                   # hasil render, dilayani GitHub Pages
```

## Cara menjalankan ulang

**Prasyarat:** R (≥ 4.1), Quarto, dan token WebAPI BPS gratis dari
https://webapi.bps.go.id.

```r
install.packages(c("jsonlite", "dplyr", "readr", "purrr", "stringr", "tidyr",
                   "tidytext", "stopwords", "igraph", "ggplot2",
                   "plotly", "DT", "crosstalk", "visNetwork"))
remotes::install_github("nurandi/katadasaR")
```

Buat berkas `.Renviron` di akar proyek:

```
BPS_TOKEN=token_anda
```

Lalu dari akar proyek:

```r
source("R/01_fetch_brs.R")    # menulis data/raw/brs_raw.csv
source("R/02_preprocess.R")   # menulis data/processed/
source("R/03_analysis.R")     # menulis data/viz/
```

```
quarto render                 # menulis docs/
```

Token tidak pernah ditulis di dalam skrip dan `.Renviron` diabaikan oleh
`.gitignore`.

## Catatan pra-pemrosesan

Beberapa keputusan yang memengaruhi hasil dan sengaja didokumentasikan:

- **Pembersihan HTML membedakan tag blok dan tag inline.** Abstrak BRS adalah
  hasil ekspor Microsoft Word. Menghapus semua tag tanpa spasi menyambungkan
  kata antar paragraf; menggantinya dengan spasi membelah kata yang terpotong
  `<span>`. Keduanya ditangani terpisah.
- **Istilah terlindungi.** Algoritma stemming Nazief & Andriani tidak
  mengenali nama diri (*Bali* → *bal*, *ASEAN* → *ase*). Daftar nama wilayah,
  negara, dan akronim di `data/processed/istilah_terlindungi.csv`
  dikecualikan dari stemming.
- **Kata arah dikembalikan dari daftar stopword.** Daftar `stopwords-iso`
  Bahasa Indonesia membuang *naik*, *tinggi*, *besar*, *kecil* tetapi
  membiarkan *turun*, *rendah*, *tumbuh*. Ketimpangan itu membalik kesimpulan
  pada korpus yang isinya laporan perubahan angka, sehingga 15 kata arah dan
  besaran dikembalikan secara eksplisit.
- **Ambang frekuensi lima.** Membuang salah ketik pada sumber (*febuari*,
  *okober*) dengan konsekuensi kata langka yang sahih ikut terbuang.

## Pilihan rancangan visual

- **Diagram batang, bukan word cloud.** Posisi pada skala bersama adalah
  saluran persepsi paling akurat dalam hierarki Cleveland–McGill; luas area
  dan ukuran huruf termasuk paling tidak akurat.
- **Panel kecil untuk TF-IDF.** Skor TF-IDF antar subjek tidak sebanding
  besarannya, sehingga satu sumbu bersama akan menyesatkan.
- **Palet Okabe-Ito** untuk kategori dan **Viridis** untuk skala berurutan,
  keduanya tetap terbaca pada deuteranopia, protanopia, dan tritanopia.
- **Ukuran dan warna mengkodekan variabel berbeda** pada sunburst dan treemap:
  jumlah dokumen dan rata-rata panjang dokumen.

## Penggunaan alat bantu AI

Sesuai ketentuan integritas akademik pada soal, penggunaan alat bantu berbasis
AI dideklarasikan. Claude (Anthropic) dipakai sebagai alat bantu untuk
perancangan struktur kode, penulisan skrip R, dan audit kualitas
pra-pemrosesan. Seluruh keputusan analitis, pemilihan tema, interpretasi
temuan, dan verifikasi hasil dilakukan dan dipertanggungjawabkan oleh penulis.
Rincian lebih lanjut ada pada bagian Metodologi makalah.

## Lisensi

Kode di repositori ini boleh dipakai ulang untuk keperluan pendidikan. Data
Berita Resmi Statistik adalah milik Badan Pusat Statistik dan tunduk pada
ketentuan penggunaan BPS.

**Sumber data: BPS — Badan Pusat Statistik.**
