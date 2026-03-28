#' @import shiny
#' @import bslib
#' @import ellmer
#' @importFrom stats predict
NULL

#' Interactive Shiny app that generates plots from voice or text commands using
#' a local Ollama model and browser-based audio capture with local Whisper STT.
#'
#' @param df A data frame to plot. Must be a simple variable name, not an
#'   expression.
#' @param model Ollama model to use for code generation. Defaults to
#'   "deepseek-coder-v2:lite".
#' @param prompt Prompt style: `"ggplot"` (default) or `"baseR"`. Or pass a
#'   custom character string to use as the system prompt prefix directly.
#'
#' @return A Shiny app object. Runs in the foreground; use a separate R session
#'   if you need the console while the app is running.
#' @export
ggbot <- function(df, model = "qwen2.5-coder", prompt = "ggplot") {
  if (missing(df)) {
    cli::cli_abort("ggbot() requires a data frame variable as the `df` argument.")
  }

  df_name <- deparse(substitute(df))

  if (!is.data.frame(df)) {
    cli::cli_abort("`df` must be a data frame.")
  }

  if (!startsWith(model, "claude")) model <- sub(":.*$", "", model)
  system_prompt <- build_prompt(df, df_name, prompt)

  # Load Whisper model (downloads ~75MB on first run, then cached)
  model_dir <- tools::R_user_dir("ggbotToo", "data")
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
  model_path <- file.path(model_dir, "ggml-tiny.bin")
  if (!file.exists(model_path)) {
    message("Downloading Whisper tiny model (~75MB)...")
    audio.whisper::whisper_download_model("tiny", model_dir = model_dir)
  }
  stt_model <- audio.whisper::whisper(model_path, use_gpu = TRUE)

  ui <- page_sidebar(
    title = "ggbotToo",
    fillable = TRUE,
    style = "--bslib-spacer: 1rem; padding-bottom: 0;",
    sidebar = sidebar(
      width = 320,
      selectInput("selected_model", label = NULL,
                  choices = ollama_models(), selected = model,
                  width = "100%"),
      # Mic level bar (driven by JS Web Audio API — no server polling needed)
      tags$div(
        style = "margin-bottom: 4px; font-size: 0.85em;",
        tags$span(id = "mic_status_js", "Mic: initializing...")
      ),
      tags$div(
        style = "height: 10px; background: #e9ecef; border-radius: 5px; overflow: hidden; margin-bottom: 8px;",
        tags$div(
          id = "js_level_bar",
          style = "height: 100%; width: 0%; background: #6c757d; transition: width 0.05s; border-radius: 5px;"
        )
      ),
      # Push-to-talk button
      tags$button(
        id = "rec_btn",
        class = "btn btn-primary btn-sm w-100",
        onmousedown = "ggbotStartRecording()",
        onmouseup   = "ggbotStopRecording()",
        onmouseleave = "ggbotStopRecording()",
        "Hold to speak"
      ),
      tags$div(
        style = "font-size: 1em; margin-top: 8px; color: #555;",
        tags$strong("Dataset: "), df_name
      ),
      tags$hr(),
      tags$strong("Or type a command:"),
      tags$div(
        style = "display: flex; gap: 4px; margin-top: 4px;",
        tags$input(
          id = "text_input",
          type = "text",
          class = "form-control form-control-sm",
          placeholder = "e.g. scatter plot of mpg vs wt"
        ),
        tags$button(
          class = "btn btn-secondary btn-sm",
          onclick = "submitText()",
          "Go"
        )
      ),
      tags$hr(),
      tags$div(
        style = "display: flex; justify-content: space-between; align-items: center;",
        tags$strong("Session transcript"),
        downloadButton("download_transcript", label = "", icon = icon("download"),
                       class = "btn-sm btn-outline-secondary", style = "padding: 2px 6px;")
      ),
      tags$div(
        id = "transcript_log",
        style = "font-size: 0.82em; max-height: 400px; overflow-y: auto; margin-top: 4px;",
        uiOutput("transcript_log")
      )
    ),
    card(
      full_screen = TRUE,
      card_header(
        class = "d-flex justify-content-between align-items-center",
        "Plot",
        downloadButton("download_plot", label = "", icon = icon("download"),
                       class = "btn-sm btn-outline-secondary", style = "padding: 2px 6px;")
      ),
      card_body(padding = 0, plotOutput("plot", fill = TRUE)),
      height = "66%"
    ),
    layout_columns(
      height = "34%",
      card(
        full_screen = TRUE,
        card_header(
          class = "d-flex justify-content-between align-items-center",
          "Code",
          downloadButton("download_code", label = "", icon = icon("download"),
                         class = "btn-sm btn-outline-secondary", style = "padding: 2px 6px;")
        ),
        verbatimTextOutput("code_text")
      ),
      card(
        full_screen = TRUE,
        card_header("Data"),
        verbatimTextOutput("data_summary")
      )
    ),
    tags$script(HTML("
      // --- Mic init & level meter ---
      (async function() {
        try {
          window._ggbotStream = await navigator.mediaDevices.getUserMedia({audio: true});
          document.getElementById('mic_status_js').textContent = 'Mic: ready';

          const ctx = new (window.AudioContext || window.webkitAudioContext)();
          const src = ctx.createMediaStreamSource(window._ggbotStream);
          const analyser = ctx.createAnalyser();
          analyser.fftSize = 256;
          src.connect(analyser);
          const buf = new Float32Array(analyser.fftSize);

          function tick() {
            analyser.getFloatTimeDomainData(buf);
            const rms = Math.sqrt(buf.reduce(function(s,v){return s+v*v;}, 0) / buf.length);
            const pct = Math.min(100, Math.round(rms / 0.1 * 100));
            const color = rms >= 0.015 ? '#28a745' : '#6c757d';
            const bar = document.getElementById('js_level_bar');
            if (bar) { bar.style.width = pct + '%'; bar.style.background = color; }
            requestAnimationFrame(tick);
          }
          tick();
        } catch(e) {
          const s = document.getElementById('mic_status_js');
          if (s) s.textContent = 'Mic error: ' + e.message;
        }
      })();

      // --- Push-to-talk ---
      var _recorder = null, _chunks = [];

      function ggbotStartRecording() {
        if (!window._ggbotStream) return;
        _chunks = [];
        _recorder = new MediaRecorder(window._ggbotStream);
        _recorder.ondataavailable = function(e) { if (e.data.size > 0) _chunks.push(e.data); };
        _recorder.onstop = function() {
          var blob = new Blob(_chunks, {type: _recorder.mimeType});
          var reader = new FileReader();
          reader.onloadend = function() {
            var b64 = reader.result.split(',')[1];
            Shiny.setInputValue('audio_blob', {data: b64, mime: blob.type}, {priority: 'event'});
          };
          reader.readAsDataURL(blob);
          var btn = document.getElementById('rec_btn');
          btn.textContent = 'Hold to speak';
          btn.classList.remove('btn-danger');
          btn.classList.add('btn-primary');
          document.getElementById('mic_status_js').textContent = 'Mic: transcribing...';
        };
        _recorder.start();
        var btn = document.getElementById('rec_btn');
        btn.textContent = 'Recording...';
        btn.classList.remove('btn-primary');
        btn.classList.add('btn-danger');
        document.getElementById('mic_status_js').textContent = 'Mic: recording';
      }

      function ggbotStopRecording() {
        if (_recorder && _recorder.state === 'recording') _recorder.stop();
      }

      // --- Text input ---
      function submitText() {
        var val = document.getElementById('text_input').value.trim();
        if (val) {
          Shiny.setInputValue('transcript', val, {priority: 'event'});
          document.getElementById('text_input').value = '';
        }
      }

      $(document).on('keydown', '#text_input', function(e) {
        if (e.key === 'Enter') submitText();
      });

      Shiny.addCustomMessageHandler('mic_ready', function(_) {
        document.getElementById('mic_status_js').textContent = 'Mic: ready';
      });

      Shiny.addCustomMessageHandler('show_transcript', function(msg) {
        var el = document.getElementById('transcript_log');
        if (!el) return;
        var div = document.createElement('div');
        div.style.cssText = 'margin-bottom: 6px; padding: 4px 6px; border-radius: 4px; background: #e8f0fe;';
        div.innerHTML = '<span style=\"font-weight: bold;\">You: </span><span>' +
          msg.text.replace(/</g, '&lt;').replace(/>/g, '&gt;') + '</span>';
        el.appendChild(div);
        el.scrollTop = el.scrollHeight;
      });

      Shiny.addCustomMessageHandler('show_bot_msg', function(msg) {
        var el = document.getElementById('transcript_log');
        if (!el) return;
        var div = document.createElement('div');
        div.style.cssText = 'margin-bottom: 6px; padding: 4px 6px; border-radius: 4px; background: #fff3cd;';
        div.innerHTML = '<span style=\"font-weight: bold;\">Bot: </span><span>' +
          msg.text.replace(/</g, '&lt;').replace(/>/g, '&gt;') + '</span>';
        el.appendChild(div);
        el.scrollTop = el.scrollHeight;
      });
    "))
  )

  server <- function(input, output, session) {
    active_model <- reactiveVal(model)
    observeEvent(input$selected_model, {
      active_model(input$selected_model)
    })

    last_code   <- reactiveVal()
    log_entries <- reactiveVal(list())

    add_log <- function(speaker, text) {
      log_entries(c(log_entries(), list(list(speaker = speaker, text = text))))
    }

    process_transcript <- function(user_text) {
      add_log("You", user_text)
      session$sendCustomMessage("show_transcript", list(text = user_text))
      id <- showNotification("Thinking...", duration = NULL, closeButton = FALSE)
      on.exit({
        removeNotification(id)
        session$sendCustomMessage("mic_ready", list())
      }, add = TRUE)
      llm_text <- build_user_message(user_text, last_code())
      response <- call_llm(active_model(), system_prompt, llm_text)
      if (is.null(response)) response <- "Error: LLM call failed — check model is available."
      add_log("Bot", response)
      code <- extract_code(response)
      if (!is.null(code)) {
        code <- sanitize_code(code)
        # Try evaluating; if it errors, ask the LLM to fix it (one retry)
        err <- try_render_code(code)
        if (!is.null(err)) {
          fix_msg <- paste0(
            "The code you generated produced this error:\n", err,
            "\nPlease fix the code and return only the corrected version."
          )
          retry_msg <- paste("Error:", err, "\u2014 retrying...")
          add_log("Bot", retry_msg)
          session$sendCustomMessage("show_bot_msg", list(text = retry_msg))
          retry <- call_llm(active_model(), system_prompt, fix_msg)
          if (!is.null(retry)) {
            retry_code <- extract_code(retry)
            if (!is.null(retry_code)) {
              add_log("Bot", retry)
              code <- retry_code
            }
          }
        }
        last_code(code)
      }
    }

    # Handle audio blob from browser MediaRecorder
    observeEvent(input$audio_blob, {
      req(input$audio_blob$data)

      # Decode base64 audio
      raw_bytes <- base64enc::base64decode(input$audio_blob$data)
      mime <- input$audio_blob$mime
      ext <- if (grepl("webm", mime, ignore.case = TRUE)) ".webm" else ".mp4"
      audio_file <- tempfile(fileext = ext)
      writeBin(raw_bytes, audio_file)
      on.exit(unlink(c(audio_file)), add = TRUE)

      # Convert to 16kHz mono WAV for Whisper
      wav_file <- tempfile(fileext = ".wav")
      on.exit(unlink(wav_file), add = TRUE)
      tryCatch(
        av::av_audio_convert(audio_file, wav_file, sample_rate = 16000, channels = 1),
        error = function(e) {
          showNotification(paste("Audio conversion error:", conditionMessage(e)), type = "error")
          return(NULL)
        }
      )

      if (!file.exists(wav_file)) return()

      # Transcribe
      result <- tryCatch(
        predict(stt_model, wav_file, language = "en"),
        error = function(e) NULL
      )

      if (is.null(result)) return()

      text <- trimws(paste(result$data$text, collapse = " "))
      if (nchar(text) == 0) return()

      process_transcript(text)
    })

    # Text input
    observeEvent(input$transcript, {
      req(input$transcript)
      process_transcript(input$transcript)
    })

    # Session transcript UI
    output$transcript_log <- renderUI({
      entries <- log_entries()
      if (length(entries) == 0) return(tags$em("No commands yet."))
      items <- lapply(entries, function(e) {
        is_user <- e$speaker == "You"
        tags$div(
          style = paste0(
            "margin-bottom: 6px; padding: 4px 6px; border-radius: 4px; ",
            if (is_user) "background: #e8f0fe;" else "background: #f0f0f0;"
          ),
          tags$span(style = "font-weight: bold;", e$speaker, ": "),
          tags$span(e$text)
        )
      })
      tagList(
        items,
        tags$script("
          var el = document.getElementById('transcript_log');
          if (el) el.scrollTop = el.scrollHeight;
        ")
      )
    })

    # Download transcript as plain text
    output$download_transcript <- downloadHandler(
      filename = function() paste0("ggbot-transcript-", format(Sys.time(), "%Y%m%d-%H%M%S"), ".txt"),
      content = function(file) {
        entries <- log_entries()
        lines <- vapply(entries, function(e) paste0(e$speaker, ": ", e$text), character(1))
        writeLines(lines, file)
      }
    )

    # Download current code as .R file
    output$download_code <- downloadHandler(
      filename = function() paste0("ggbot-code-", format(Sys.time(), "%Y%m%d-%H%M%S"), ".R"),
      content = function(file) {
        writeLines(if (!is.null(last_code())) last_code() else "# No code generated yet", file)
      }
    )

    # Download current plot as PNG
    output$download_plot <- downloadHandler(
      filename = function() paste0("ggbot-plot-", format(Sys.time(), "%Y%m%d-%H%M%S"), ".png"),
      content = function(file) {
        grDevices::png(file, width = 1200, height = 800, res = 150)
        on.exit(grDevices::dev.off())
        code <- last_code()
        if (!is.null(code)) {
          result <- eval(parse(text = code), envir = new.env(parent = globalenv()))
          if (inherits(result, "gg")) print(result)
        }
      }
    )

    output$data_summary <- renderText({
      paste(utils::capture.output(utils::str(df)), collapse = "\n")
    })

    output$plot <- renderPlot(res = 96, {
      req(last_code())
      tryCatch({
        result <- withVisible(
          eval(parse(text = last_code()), envir = new.env(parent = globalenv()))
        )
        if (result$visible) print(result$value)
      }, error = function(e) {
        msg <- gsub("\033\\[[0-9;]*m", "", conditionMessage(e))
        stop(msg, call. = FALSE)
      })
    })

    output$code_text <- renderText({
      req(last_code())
      last_code()
    })
  }

  shinyApp(ui, server)
}

#' Extract the first ```r code block from an LLM response
#'
#' @param text Character string containing the LLM response
#' @return The code as a character string, or NULL if no code block found
#' @keywords internal
extract_code <- function(text) {
  # Strip <think>...</think> blocks emitted by reasoning models
  text <- gsub("(?s)<think>.*?</think>", "", text, perl = TRUE)
  # Match ```r, ```{r}, ``` or any other language tag (e.g. deepseek uses ```{r})
  m <- regmatches(text, regexpr("(?s)```[^\\n]*\\n(.*?)```", text, perl = TRUE))
  if (length(m) == 0) return(NULL)
  gsub("^```[^\\n]*\\n|```$", "", m[[1]], perl = TRUE)
}

# --- Code guardrail --------------------------------------------------------

# Strip install.packages() calls from generated code. The LLM sometimes
# wraps plotting code in if(!require(...)) { install.packages(...) } blocks.
# We silently remove those lines rather than blocking the whole response.
sanitize_code <- function(code) {
  lines <- strsplit(code, "\n")[[1]]
  lines <- grep("^\\s*if\\s*\\(!\\s*require", lines, value = TRUE, invert = TRUE)
  lines <- grep("^\\s*install\\.packages\\s*\\(", lines, value = TRUE, invert = TRUE)
  lines <- grep("^\\s*remove\\.packages\\s*\\(", lines, value = TRUE, invert = TRUE)
  paste(lines, collapse = "\n")
}

# Test-render code in an isolated function so the png device is properly scoped.
# Returns NULL on success or an ANSI-stripped error message on failure.
try_render_code <- function(code) {
  tryCatch({
    grDevices::png(tempfile())
    on.exit(grDevices::dev.off())
    result <- eval(parse(text = code), envir = new.env(parent = globalenv()))
    if (inherits(result, "gg")) print(result)
    NULL
  }, error = function(e) {
    gsub("\033\\[[0-9;]*m", "", conditionMessage(e))
  })
}

#' Call an LLM backend and return the response text
#' @keywords internal
call_llm <- function(model, system_prompt, msg) {
  if (model %in% c("claude", "claude-sonnet")) .call_claude_code(system_prompt, msg)
  else if (model == "claude-haiku") .call_claude_code(system_prompt, msg,
                                      model_id = "claude-haiku-4-5-20251001")
  else                              .call_ollama(model, system_prompt, msg)
}

.call_claude_code <- function(system_prompt, msg, model_id = NULL) {
  Sys.unsetenv("ANTHROPIC_API_KEY")  # force CLI to use subscription, not API credits
  full_prompt <- paste0(system_prompt, "\n\n", msg)
  args <- c("--no-session-persistence", "-p", "--output-format", "text")
  if (!is.null(model_id)) args <- c(args, "--model", model_id)
  result <- tryCatch(
    system2("claude", args = args,
            input = full_prompt, stdout = TRUE, stderr = FALSE),
    error = function(e) { warning("claude CLI: ", conditionMessage(e)); NULL }
  )
  if (is.null(result)) return(NULL)
  if (isTRUE(attr(result, "status") != 0L)) return(NULL)
  paste(result, collapse = "\n")
}

.call_ollama <- function(model, system_prompt, msg) {
  tryCatch({
    chat_obj <- ellmer::chat_ollama(model = model, system_prompt = system_prompt)
    chat_obj$chat(msg, echo = "none")
  }, error = function(e) { warning("Ollama: ", conditionMessage(e)); NULL })
}

#' List available Ollama models
#' @keywords internal
ollama_models <- function() {
  ollama <- tryCatch({
    resp <- httr2::request("http://localhost:11434/api/tags") |> httr2::req_perform()
    tags <- httr2::resp_body_json(resp)
    nms  <- vapply(tags$models, `[[`, character(1), "name")
    unique(sub(":latest$", "", nms))
  }, error = function(e) character(0))
  c("claude-sonnet", "claude-haiku", ollama)
}

#' Build prompt with data frame information
#'
#' @param df Data frame to include in the prompt
#' @param df_name Character string with the variable name of the data frame
#' @param prompt_style `"ggplot"`, `"baseR"`, or a custom string
#' @return Character string containing the complete prompt
#' @keywords internal
build_prompt <- function(df, df_name, prompt_style = "ggplot") {
  prompt_file <- switch(prompt_style,
    ggplot = "prompts/prompt.md",
    baseR  = "prompts/prompt_baseR.md",
    NULL
  )
  prompt <- if (!is.null(prompt_file)) {
    paste(collapse = "\n",
          readLines(system.file(prompt_file, package = "ggbotToo")))
  } else {
    prompt_style  # treat as raw string
  }

  df_preview <- paste(
    collapse = "\n",
    utils::capture.output(utils::write.csv(utils::head(df), ""))
  )

  withr::with_options(list(width = 1000), {
    df_summary <- paste(
      collapse = "\n",
      utils::capture.output(summary(df))
    )
  })

  paste0(
    prompt,
    "\n\nThe user has provided a data frame with the variable name `", df_name, "`.",
    " Its first few rows look like this:\n\n", df_preview,
    "\n\nIts summary looks like this:\n\n", df_summary,
    "\n\nUnless explicitly told otherwise, use this data frame for plotting."
  )
}

#' Build the message sent to the LLM, injecting current plot code when available
#'
#' @param user_text The user's request (transcript or typed command)
#' @param current_code The current plot code, or NULL if no plot exists yet
#' @return Character string to pass to the LLM
#' @keywords internal
build_user_message <- function(user_text, current_code = NULL) {
  if (is.null(current_code)) return(user_text)
  paste0(
    "Current plot code:\n```r\n", current_code, "\n```\n\n",
    "User request: ", user_text
  )
}
