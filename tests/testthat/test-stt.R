# Helper: generate a WAV file from text using macOS say + av conversion
say_to_wav <- function(text) {
  aiff <- tempfile(fileext = ".aiff")
  wav  <- tempfile(fileext = ".wav")
  ret  <- system2("say", args = c("-o", aiff, text), stdout = FALSE, stderr = FALSE)
  if (ret != 0 || !file.exists(aiff)) return(NULL)
  av::av_audio_convert(aiff, wav, sample_rate = 16000, channels = 1,
                       verbose = FALSE)
  if (file.exists(wav)) wav else NULL
}

# Helper: load whisper model (cached across tests in this file via local env)
load_whisper <- function() {
  model_path <- file.path(tools::R_user_dir("ggbotToo", "data"), "ggml-tiny.bin")
  suppressMessages(
    audio.whisper::whisper(model_path, use_gpu = TRUE)
  )
}

# ── av conversion ─────────────────────────────────────────────────────────────

test_that("av converts aiff to 16kHz mono WAV", {
  skip_if_not_installed("av")
  wav <- say_to_wav("test")
  skip_if(is.null(wav), "say command not available")

  info <- av::av_media_info(wav)
  expect_equal(info$audio$sample_rate, 16000)
  expect_equal(info$audio$channels, 1)
  expect_gt(file.info(wav)$size, 0)
})

test_that("base64 encode → decode round-trip preserves audio file", {
  skip_if_not_installed("av")
  skip_if_not_installed("base64enc")
  wav <- say_to_wav("hello")
  skip_if(is.null(wav), "say command not available")

  original <- readBin(wav, "raw", file.info(wav)$size)
  b64      <- base64enc::base64encode(original)
  decoded  <- base64enc::base64decode(b64)
  expect_identical(original, decoded)
})

test_that("server audio pipeline: base64 aiff → wav → readable file", {
  skip_if_not_installed("av")
  skip_if_not_installed("base64enc")

  # Simulate: browser sends base64-encoded audio, server decodes + converts
  aiff <- tempfile(fileext = ".aiff")
  ret  <- system2("say", args = c("-o", aiff, "scatter plot"), stdout = FALSE, stderr = FALSE)
  skip_if(ret != 0, "say command not available")

  raw_bytes <- readBin(aiff, "raw", file.info(aiff)$size)
  b64       <- base64enc::base64encode(raw_bytes)

  # Server side
  decoded   <- base64enc::base64decode(b64)
  tmp_in    <- tempfile(fileext = ".aiff")
  writeBin(decoded, tmp_in)
  tmp_wav   <- tempfile(fileext = ".wav")
  av::av_audio_convert(tmp_in, tmp_wav, sample_rate = 16000, channels = 1,
                       verbose = FALSE)

  expect_true(file.exists(tmp_wav))
  expect_gt(file.info(tmp_wav)$size, 0)
})

# ── Whisper transcription ──────────────────────────────────────────────────────

test_that("whisper model loads without error", {
  skip_if_no_whisper_model()
  model <- load_whisper()
  expect_s3_class(model, "whisper")
})

test_that("whisper transcribes a short utterance with plausible accuracy", {
  skip_if_no_whisper_model()
  wav <- say_to_wav("scatter plot of mpg versus weight")
  skip_if(is.null(wav), "say command not available")

  model  <- load_whisper()
  result <- predict(model, wav, language = "en")

  expect_s3_class(result$data, "data.frame")
  expect_true("text" %in% names(result$data))

  text <- tolower(trimws(paste(result$data$text, collapse = " ")))
  expect_gt(nchar(text), 0)
  # At least one key word should survive transcription
  expect_true(
    grepl("scatter", text) || grepl("plot", text) ||
    grepl("mpg", text)     || grepl("weight", text),
    info = paste("transcription was:", text)
  )
})

test_that("whisper returns empty/short text for silence", {
  skip_if_no_whisper_model()
  skip_if_not_installed("av")

  # Create a short silent WAV: 1s of zeros at 16kHz
  n_samples <- 16000L
  raw_pcm   <- writeBin(rep(as.raw(0), n_samples * 2L), raw())
  sil_wav   <- tempfile(fileext = ".wav")

  # Write a minimal PCM WAV header + silence
  con <- file(sil_wav, "wb")
  on.exit(close(con), add = TRUE)
  pcm_data <- as.raw(integer(n_samples * 2L))  # 16-bit zeros
  data_size <- length(pcm_data)
  writeBin(charToRaw("RIFF"),              con)
  writeBin(as.integer(36L + data_size),    con, size = 4L)
  writeBin(charToRaw("WAVE"),              con)
  writeBin(charToRaw("fmt "),              con)
  writeBin(16L,   con, size = 4L)   # chunk size
  writeBin(1L,    con, size = 2L)   # PCM
  writeBin(1L,    con, size = 2L)   # mono
  writeBin(16000L, con, size = 4L)  # sample rate
  writeBin(32000L, con, size = 4L)  # byte rate
  writeBin(2L,    con, size = 2L)   # block align
  writeBin(16L,   con, size = 2L)   # bits per sample
  writeBin(charToRaw("data"),          con)
  writeBin(as.integer(data_size),      con, size = 4L)
  writeBin(pcm_data,                   con)
  close(con)
  on.exit(NULL)  # con already closed

  model  <- load_whisper()
  result <- predict(model, sil_wav, language = "en")
  text   <- trimws(paste(result$data$text, collapse = " "))
  # Whisper should return empty or very short text for silence
  expect_lte(nchar(text), 20)
})
