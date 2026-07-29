# RStudio "Run App" entrypoint
#
# In dev: loads package code via pkgload::load_all()
# When installed: uses library(earshot)

if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
} else {
  library(earshot)
}

run_app()
