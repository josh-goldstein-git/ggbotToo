test_that("ggbot() errors clearly when df is missing", {
  expect_error(ggbot(), "requires a data frame")
})

test_that("ggbot() errors clearly when df is not a data frame", {
  expect_error(ggbot(42), "must be a data frame")
})

# Source-inspection tests: read directly from package source.
# Skipped on CRAN (source files not present in installed package).
local({
  src_path <- system.file("../R/ggbotToo.R", package = "ggbotToo")
  if (!nzchar(src_path)) {
    # Fallback: find source relative to testthat directory
    src_path <- file.path(
      dirname(dirname(dirname(testthat::test_path()))),
      "R", "ggbotToo.R"
    )
  }

  skip_if(!file.exists(src_path), "Source file not accessible (installed package)")
  src <- paste(readLines(src_path), collapse = "\n")

  test_that("UI source contains push-to-talk button with correct id", {
    expect_true(grepl("rec_btn",             src, fixed = TRUE))
    expect_true(grepl("ggbotStartRecording", src, fixed = TRUE))
    expect_true(grepl("ggbotStopRecording",  src, fixed = TRUE))
  })

  test_that("UI source contains JS level bar element", {
    expect_true(grepl("js_level_bar", src, fixed = TRUE))
  })

  test_that("UI source contains mic status JS element", {
    expect_true(grepl("mic_status_js", src, fixed = TRUE))
  })

  test_that("UI source sends audio_blob to Shiny", {
    expect_true(grepl("audio_blob",          src, fixed = TRUE))
    expect_true(grepl("Shiny.setInputValue", src, fixed = TRUE))
  })

  test_that("server handles audio_blob input", {
    expect_true(grepl("input\\$audio_blob",       src))
    expect_true(grepl("base64enc::base64decode",  src, fixed = TRUE))
    expect_true(grepl("av::av_audio_convert",     src, fixed = TRUE))
  })

  test_that("UI source uses MediaRecorder API", {
    expect_true(grepl("MediaRecorder", src, fixed = TRUE))
    expect_true(grepl("getUserMedia",  src, fixed = TRUE))
  })
})
