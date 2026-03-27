#' Check and set up ggbotToo dependencies
#'
#' Verifies that Ollama is running, pulls the default model if missing, and
#' downloads the Whisper tiny model if needed. Run this once after installing
#' the package.
#'
#' @param model Ollama model to check/pull. Defaults to `"deepseek-coder-v2:lite"`.
#' @param whisper_model Whisper model variant. Only `"tiny"` is currently
#'   supported.
#' @param quiet Suppress progress messages if `TRUE`.
#' @return Invisibly returns a named logical vector indicating which components
#'   are ready: `ollama`, `model`, `whisper`.
#' @export
ggbot_setup <- function(model = "deepseek-coder-v2:lite",
                        whisper_model = "tiny",
                        quiet = FALSE) {
  status <- c(ollama = FALSE, model = FALSE, whisper = FALSE)

  msg <- function(...) if (!quiet) message(...)

  # ── 1. Ollama reachable ───────────────────────────────────────────────────
  msg("Checking Ollama...")
  ollama_ok <- tryCatch({
    resp <- httr2::request("http://localhost:11434/api/tags") |>
      httr2::req_timeout(5) |>
      httr2::req_perform()
    httr2::resp_status(resp) == 200L
  }, error = function(e) FALSE)

  if (!ollama_ok) {
    cli::cli_alert_danger(
      "Ollama is not running. Start it with {.code ollama serve} in a terminal."
    )
    return(invisible(status))
  }
  cli::cli_alert_success("Ollama is running.")
  status["ollama"] <- TRUE

  # ── 2. Model available ────────────────────────────────────────────────────
  msg("Checking model {model}...")
  available <- ollama_models()
  model_base <- sub(":.*", "", model)
  model_present <- any(startsWith(available, model_base))

  if (!model_present) {
    cli::cli_alert_info("Pulling {model} (this may take several minutes)...")
    pull_ok <- tryCatch({
      resp <- httr2::request("http://localhost:11434/api/pull") |>
        httr2::req_body_json(list(name = model, stream = FALSE)) |>
        httr2::req_timeout(600) |>
        httr2::req_perform()
      httr2::resp_status(resp) == 200L
    }, error = function(e) {
      cli::cli_alert_danger("Failed to pull {model}: {conditionMessage(e)}")
      FALSE
    })
    if (!pull_ok) return(invisible(status))
    cli::cli_alert_success("Model {model} pulled.")
  } else {
    cli::cli_alert_success("Model {model} is available.")
  }
  status["model"] <- TRUE

  # ── 3. Whisper model ──────────────────────────────────────────────────────
  model_dir  <- tools::R_user_dir("ggbotToo", "data")
  model_file <- paste0("ggml-", whisper_model, ".bin")
  model_path <- file.path(model_dir, model_file)

  msg("Checking Whisper {whisper_model} model...")
  if (!file.exists(model_path)) {
    cli::cli_alert_info(
      "Downloading Whisper {whisper_model} model (~75 MB, one-time download)..."
    )
    dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
    tryCatch(
      audio.whisper::whisper_download_model(whisper_model, model_dir = model_dir),
      error = function(e) {
        cli::cli_alert_danger(
          "Whisper download failed: {conditionMessage(e)}"
        )
        return(invisible(status))
      }
    )
  }

  if (file.exists(model_path)) {
    cli::cli_alert_success("Whisper {whisper_model} model ready.")
    status["whisper"] <- TRUE
  } else {
    cli::cli_alert_danger("Whisper model file not found after download attempt.")
  }

  # ── Summary ───────────────────────────────────────────────────────────────
  if (all(status)) {
    cli::cli_alert_success("All set! Run {.code ggbot(your_data)} to start.")
  } else {
    missing <- names(status)[!status]
    cli::cli_alert_warning(
      "Setup incomplete. Check the issues above. Missing: {paste(missing, collapse = ', ')}"
    )
  }

  invisible(status)
}
