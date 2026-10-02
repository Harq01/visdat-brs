# =============================================================================
# 01_fetch_brs.R
# Menarik korpus Berita Resmi Statistik (BRS) dari WebAPI BPS
#
# Endpoint mengikuti paket resmi BPS `stadata`:
#   https://webapi.bps.go.id/v1/api/list/model/pressrelease/perpage/{n}/lang/{lang}
#   /domain/{domain}/key/{key}/keyword/{kw}/page/{p}[/year/{y}][/month/{m}]
#
# Field tiap dokumen:
#   brs_id, subj_id, subj, title, abstract, rl_date, updt_date, pdf, size
#
# Output: data/raw/brs_raw.csv   (satu baris = satu dokumen BRS)
# =============================================================================

# ---- Cek paket -------------------------------------------------------------

pkgs <- c("jsonlite", "dplyr", "readr", "purrr")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  stop(
    "Paket berikut belum terpasang: ", paste(missing, collapse = ", "), "\n",
    "Jalankan dulu:\n",
    '  install.packages(c("', paste(missing, collapse = '", "'), '"))',
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(jsonlite); library(dplyr); library(readr); library(purrr)
})

# ---- Konfigurasi -----------------------------------------------------------

TOKEN  <- Sys.getenv("BPS_TOKEN")
DOMAIN <- "0000"          # 0000 = nasional
LANG   <- "ind"
YEARS  <- 2015:2025        # sesuai klaim di spreadsheet kelas
OUTDIR <- "data/raw"

if (!nzchar(TOKEN)) {
  stop(
    "BPS_TOKEN belum terbaca.\n",
    "1. Buat file .Renviron di root proyek berisi satu baris:\n",
    "     BPS_TOKEN=tokenmu\n",
    "2. Pastikan ada baris kosong di akhir file.\n",
    "3. Restart R: menu Session > Restart R.\n",
    "Cek dengan: Sys.getenv(\"BPS_TOKEN\")",
    call. = FALSE
  )
}

dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)

# ---- Satu panggilan API ----------------------------------------------------

brs_url <- function(page = 1, year = "", month = "", keyword = "",
                    perpage = 1000) {
  paste0(
    "https://webapi.bps.go.id/v1/api/list/model/pressrelease",
    "/perpage/", perpage,
    "/lang/",    LANG,
    "/domain/",  DOMAIN,
    "/key/",     TOKEN,
    "/keyword/", keyword,
    "/page/",    page,
    if (nzchar(as.character(month))) paste0("/month/", month) else "",
    if (nzchar(as.character(year)))  paste0("/year/",  year)  else ""
  )
}

brs_call <- function(page = 1, year = "", tries = 3) {
  
  url <- brs_url(page = page, year = year)
  
  res <- NULL
  for (attempt in seq_len(tries)) {
    res <- tryCatch(
      jsonlite::fromJSON(url, simplifyVector = TRUE),
      error = function(e) {
        message("  ! percobaan ", attempt, " gagal: ", conditionMessage(e))
        NULL
      }
    )
    if (!is.null(res)) break
    Sys.sleep(2 * attempt)
  }
  
  if (is.null(res)) {
    stop("Gagal menghubungi WebAPI setelah ", tries, " percobaan ",
         "(tahun ", year, ", halaman ", page, "). Cek koneksi internet.",
         call. = FALSE)
  }
  
  if (!identical(res$status, "OK")) {
    stop("WebAPI menolak permintaan: ",
         if (!is.null(res$message)) res$message else "tanpa pesan",
         "\nBiasanya ini berarti token salah atau belum aktif.",
         call. = FALSE)
  }
  
  if (is.null(res$data) || identical(res$data, "") || length(res$data) < 2) {
    return(list(meta = NULL, items = NULL))
  }
  
  list(meta = res$data[[1]], items = res$data[[2]])
}

# ---- Seluruh halaman untuk satu tahun --------------------------------------

fetch_year <- function(year) {
  
  message("Tahun ", year, " ...")
  first <- brs_call(page = 1, year = year)
  
  if (is.null(first$items)) {
    message("  (kosong)")
    return(NULL)
  }
  
  pages <- suppressWarnings(as.integer(first$meta$pages))
  if (length(pages) != 1 || is.na(pages) || pages < 1) pages <- 1
  
  out <- list(first$items)
  
  # CATATAN: stadata memakai range(2, pages) yang melewatkan halaman terakhir.
  # Di sini seq(2, pages) supaya halaman terakhir ikut terambil.
  if (pages > 1) {
    for (p in seq(2, pages)) {
      pg <- brs_call(page = p, year = year)
      if (is.null(pg$items)) break
      out[[length(out) + 1]] <- pg$items
      Sys.sleep(0.3)   # jeda sopan terhadap server BPS
    }
  }
  
  df <- dplyr::bind_rows(out)
  message("  ", nrow(df), " dokumen (", pages, " halaman)")
  df
}

# ---- Jalankan --------------------------------------------------------------

keep_cols <- c("brs_id", "subj_id", "subj", "title", "abstract",
               "rl_date", "updt_date", "pdf", "size")

brs_raw <- purrr::map(YEARS, fetch_year) |>
  purrr::compact() |>
  dplyr::bind_rows()

if (nrow(brs_raw) == 0) {
  stop("Tidak ada dokumen terambil sama sekali. Cek token dan koneksi.",
       call. = FALSE)
}

brs_raw <- brs_raw |>
  dplyr::select(dplyr::any_of(keep_cols)) |>
  dplyr::distinct(brs_id, .keep_all = TRUE)

# PENTING: simpan lebih dulu, sebelum pengolahan apa pun.
# Kalau parsing tanggal di bawah bermasalah, hasil unduhan tidak ikut hilang.
readr::write_csv(brs_raw, file.path(OUTDIR, "brs_raw.csv"))
message("\nTersimpan: ", file.path(OUTDIR, "brs_raw.csv"),
        " (", nrow(brs_raw), " baris)")

# ---- Parsing tanggal, defensif ---------------------------------------------
# Format rl_date dari WebAPI belum diverifikasi, jadi dicoba beberapa pola.

parse_tanggal <- function(x) {
  x <- trimws(as.character(x))
  pola <- c("%Y-%m-%d", "%Y-%m-%d %H:%M:%S", "%d-%m-%Y", "%d/%m/%Y")
  for (p in pola) {
    d <- suppressWarnings(as.Date(x, format = p))
    if (sum(!is.na(d)) > 0.8 * length(x)) return(d)
  }
  warning("Format rl_date tidak dikenali. Contoh nilai: ",
          paste(utils::head(x, 3), collapse = " | "), call. = FALSE)
  rep(as.Date(NA), length(x))
}

brs_raw$rl_parsed <- parse_tanggal(brs_raw$rl_date)
brs_raw$tahun     <- as.integer(format(brs_raw$rl_parsed, "%Y"))

# ---- Ringkasan untuk dicek mata --------------------------------------------

abs_txt <- as.character(brs_raw$abstract)
abs_txt[is.na(abs_txt)] <- ""

cat("\n==================== RINGKASAN KORPUS ====================\n")
cat("Total dokumen     :", nrow(brs_raw), "\n")
cat("Jumlah subjek     :", dplyr::n_distinct(brs_raw$subj), "\n")
cat("Abstrak kosong    :", sum(!nzchar(trimws(abs_txt))), "\n")
cat("Rata-rata panjang abstrak (karakter):",
    round(mean(nchar(abs_txt))), "\n")
cat("Contoh nilai rl_date:", paste(utils::head(brs_raw$rl_date, 2),
                                   collapse = " | "), "\n\n")

cat("Dokumen per tahun:\n")
print(as.data.frame(table(brs_raw$tahun, useNA = "ifany")))

cat("\nDokumen per subjek:\n")
print(as.data.frame(dplyr::count(brs_raw, subj, sort = TRUE)))
cat("==========================================================\n")