skip_if_no_whisper_model <- function() {
  model_path <- file.path(tools::R_user_dir("ggbotToo", "data"), "ggml-tiny.bin")
  if (!file.exists(model_path)) skip("Whisper model not downloaded")
  invisible(model_path)
}

# Skip tests that require a running Ollama instance
skip_if_no_ollama <- function(model = "deepseek-coder-v2:lite") {
  result <- tryCatch(
    {
      resp <- httr2::request("http://localhost:11434/api/tags") |>
        httr2::req_perform()
      tags <- httr2::resp_body_json(resp)
      model_names <- vapply(tags$models, `[[`, character(1), "name")
      if (!any(startsWith(model_names, sub(":.*", "", model)))) {
        skip(paste("Ollama model", model, "not available"))
      }
    },
    error = function(e) skip("Ollama not running")
  )
  invisible(result)
}

# Ask the LLM a question and return response + extracted code
ask_ggbot <- function(prompt_text, df = mtcars, df_name = "mtcars",
                      model = "deepseek-coder-v2:lite") {
  system_prompt <- build_prompt(df, df_name)
  chat <- ellmer::chat_ollama(model = model, system_prompt = system_prompt)
  response <- chat$chat(prompt_text, echo = "none")
  list(
    response = response,
    code = extract_code(response),
    chat = chat
  )
}

# Evaluate extracted code and return TRUE if it plots without error
try_plot <- function(code, df = mtcars, env_vars = list()) {
  if (is.null(code)) return(list(success = FALSE, error = "no code extracted", code = NULL))
  e <- new.env(parent = globalenv())
  # Inject the data frame under its expected name
  assign("mtcars", df, envir = e)
  for (nm in names(env_vars)) assign(nm, env_vars[[nm]], envir = e)
  tryCatch(
    {
      png(tempfile())
      on.exit(dev.off())
      eval(parse(text = code), envir = e)
      list(success = TRUE, error = NULL, code = code)
    },
    error = function(err) list(success = FALSE, error = conditionMessage(err), code = code)
  )
}
