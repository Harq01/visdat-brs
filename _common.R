# =============================================================================
# _common.R
# Pengaturan bersama untuk seluruh halaman dasbor: paket, palet, pemuatan
# data, dan tema grafik. Dipanggil di awal tiap berkas .qmd agar tidak ada
# kode yang terduplikasi antar halaman.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(tidyr)
  library(ggplot2)
  library(tidytext)
  library(plotly)
  library(DT)
  library(crosstalk)
  library(visNetwork)
})

knitr::opts_chunk$set(echo = FALSE, warning = FALSE, message = FALSE)

# ---- Palet ------------------------------------------------------------------
# Okabe-Ito sebagai dasar: aman untuk deuteranopia, protanopia, dan tritanopia.
# Nilai terangnya diturunkan agar tidak menyilaukan di latar krem halaman.

OI <- c("#0072B2", "#E69F00", "#009E73", "#CC79A7", "#56B4E9", "#D55E00")

BIRU    <- "#1f6f9e"
HIJAU   <- "#1b7f68"
ORANYE  <- "#c25a1e"

TINTA  <- "#1c2024"
REDUP  <- "#6b7178"
GARIS  <- "#e8e4dd"
KERTAS <- "rgba(0,0,0,0)"
LATAR  <- "#fbfaf8"

SERIF <- "Source Serif 4, Georgia, serif"
SANS  <- "Inter, system-ui, -apple-system, Segoe UI, sans-serif"

# Skala berurutan satu rona. Satu rona menjaga urutan tetap terbaca pada semua
# jenis buta warna, dan lebih menyatu dengan halaman daripada skala pelangi.
BIRU_SKALA <- list(c(0, "#f2f6f9"), c(0.25, "#c3dbea"), c(0.5, "#7fb4d4"),
                   c(0.75, "#3787b9"), c(1, "#0a4f78"))

# Palet komunitas jaringan: rona teredam yang berputar. Jumlah komunitas
# melebihi palet kategorikal mana pun yang tetap terbedakan, sehingga warna
# di sini membedakan kelompok yang berdekatan, bukan menjadi kode hafalan.
PAL_KOMUNITAS <- c("#1f6f9e", "#2f8f7a", "#9c6b1f", "#8a4f7d", "#b06a3a",
                   "#4a7f5c", "#7a5c9e", "#3d6a99", "#a3562f", "#5c8fa8",
                   "#86794a", "#6f5b8e")

# ---- Data -------------------------------------------------------------------

v <- function(f) read_csv(file.path("data/viz", f), show_col_types = FALSE)

freq_kata <- v("freq_kata.csv")
tfidf     <- v("tfidf_subjek.csv")
tren_dok  <- v("tren_dokumen.csv")
arah      <- v("arah_perubahan.csv")
indeks    <- v("indeks_dokumen.csv")
sisi      <- v("jaringan_sisi.csv")
simpul    <- v("jaringan_simpul.csv")
matriks   <- v("jaringan_matriks.csv")
pohon     <- v("hierarki_pohon.csv")
hierarki  <- v("hierarki.csv")

SUMBER <- "Sumber: BPS — Berita Resmi Statistik via WebAPI BPS, diakses 2 Oktober 2026"

# Angka ringkasan yang dipakai di beberapa halaman
n_dok   <- nrow(indeks)
n_subj  <- n_distinct(indeks$subjek)
pct_eko <- round(100 * sum(indeks$domain == "Statistik Ekonomi") / n_dok, 1)
rasio   <- round(sum(arah$n[arah$arah == "Naik"]) /
                 sum(arah$n[arah$arah == "Turun"]), 2)

# ---- Tema grafik ------------------------------------------------------------
# Satu tema untuk seluruh grafik agar halaman dan visualisasinya terbaca
# sebagai satu sistem: judul serif seperti judul bagian, label sans seperti
# teks isi, garis bantu setipis garis tepi halaman, latar menyatu.

rapikan <- function(p, sumber = TRUE) {
  p |>
    layout(
      font = list(family = SANS, size = 13, color = TINTA),
      paper_bgcolor = KERTAS,
      plot_bgcolor  = KERTAS,
      margin = list(t = 104, r = 24, b = if (sumber) 80 else 48, l = 24),
      hoverlabel = list(
        font = list(family = SANS, size = 13, color = "#fff"),
        bgcolor = TINTA, bordercolor = TINTA
      ),
      xaxis = list(gridcolor = GARIS, zerolinecolor = GARIS, linecolor = GARIS,
                   tickfont = list(size = 11, color = REDUP),
                   titlefont = list(size = 11.5, color = REDUP)),
      yaxis = list(gridcolor = GARIS, zerolinecolor = GARIS, linecolor = GARIS,
                   tickfont = list(size = 11, color = REDUP),
                   titlefont = list(size = 11.5, color = REDUP)),
      annotations = if (sumber) list(list(
        text = SUMBER, showarrow = FALSE,
        xref = "paper", yref = "paper", x = 0, y = -0.2, xanchor = "left",
        font = list(family = SANS, size = 10, color = "#8c9298")
      )) else list()
    ) |>
    config(displaylogo = FALSE, locale = "id", responsive = TRUE,
           modeBarButtonsToRemove = c("lasso2d", "select2d", "autoScale2d"))
}

judul <- function(teks, anak = NULL) {
  list(
    text = if (is.null(anak)) teks else
      paste0(teks, "<br><span style='font-family:", SANS,
             ";font-size:12px;color:", REDUP, "'>", anak, "</span>"),
    x = 0, xanchor = "left",
    y = 1, yanchor = "top",
    pad = list(t = 18, b = 24, l = 0),
    font = list(family = SERIF, size = 19, color = TINTA)
  )
}

# ---- Jaringan ---------------------------------------------------------------

jaringan <- function(ambang, tinggi = "620px") {

  e <- sisi |> filter(bobot >= ambang)
  s <- simpul |> filter(ambang == !!ambang)

  nodes <- s |>
    transmute(
      id = kata, label = kata, value = kekuatan,
      color.background = PAL_KOMUNITAS[(komunitas - 1) %% length(PAL_KOMUNITAS) + 1],
      color.border               = LATAR,
      color.highlight.background = "#15536f",
      color.highlight.border     = "#0a2d3f",
      title = paste0("<b>", kata, "</b><br>Derajat: ", derajat,
                     "<br>Kekuatan: ", round(kekuatan),
                     "<br>Keantaraan: ", sprintf("%.3f", keantaraan),
                     "<br>Komunitas: ", komunitas)
    )

  edges <- e |>
    transmute(from = dari, to = ke, value = bobot,
              title = paste0(dari, " — ", ke, ": ", bobot))

  visNetwork(nodes, edges, height = tinggi, width = "100%",
             background = LATAR) |>
    visNodes(borderWidth = 2, scaling = list(min = 9, max = 42),
             font = list(size = 17, face = "Inter", color = TINTA,
                         strokeWidth = 4, strokeColor = LATAR)) |>
    visEdges(color = list(color = "#d6d0c6", highlight = BIRU, opacity = 0.8),
             smooth = FALSE) |>
    visOptions(highlightNearest = list(enabled = TRUE, degree = 1,
                                       hover = TRUE, labelOnly = FALSE),
               nodesIdSelection = list(enabled = TRUE, main = "Cari kata...")) |>
    visPhysics(solver = "forceAtlas2Based",
               forceAtlas2Based = list(gravitationalConstant = -70,
                                       springLength = 120,
                                       avoidOverlap = 0.4),
               stabilization = list(enabled = TRUE, iterations = 300)) |>
    visLayout(randomSeed = 42) |>
    visInteraction(navigationButtons = TRUE, tooltipDelay = 120)
}
