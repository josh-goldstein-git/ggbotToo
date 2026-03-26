# ggbotToo

Voice-controlled R plotting. Speak a command, get a ggplot2 plot. Free, local, no API key needed.

A free, local alternative to the brilliant [ggbot2](https://github.com/tidyverse/ggbot2), which inspired this project but requires a paid API key. Runs entirely on your machine using [Ollama](https://ollama.com) and [Whisper](https://github.com/openai/whisper).

---

## Requirements

- Mac with Apple Silicon (M1/M2/M3)
- R ≥ 4.3
- [Ollama](https://ollama.com) — free, runs LLMs locally

---

## Installation

**Step 1 — Install Ollama** (one time)

Download from [ollama.com](https://ollama.com) or run in Terminal:

```bash
brew install ollama
```

**Step 2 — Install the R package**

```r
remotes::install_github("bnosac/audio.whisper")
remotes::install_github("josh-goldstein-git/ggbotToo")
```

**Step 3 — First-time setup** (downloads ~5GB of models, one time)

```r
library(ggbotToo)
ggbot_setup()
```

This will:
- Check Ollama is running (start it with `ollama serve` in Terminal if needed)
- Pull the default language model (~4.7GB)
- Download the Whisper speech-to-text model (~75MB)

---

![Demo](man/figures/demo.gif)

## Usage

### Try the demo first (no microphone needed)

```r
library(ggbotToo)
install.packages("palmerpenguins")  # one-time
ggbot_demo()
```

This opens the app pre-loaded with the Palmer Penguins dataset. Click **▶ Demo step** to play five pre-recorded voice commands through the full pipeline — Whisper transcription, Ollama code generation, and live plot updates — without needing a microphone.

### Use with your own data

```r
ggbot(mydata)
```

This opens a Shiny app in your browser. Hold the **Hold to speak** button and describe the plot you want. Release to transcribe and generate.

**Example commands:**
- *"scatter plot of birth year by death age"*
- *"color the points by state"*
- *"add a regression line"*
- *"make the axis labels larger"*
- *"add a title"*

The app remembers the conversation, so you can refine iteratively.

**Faster model (default):** `qwen2.5-coder` — good for quick exploration
**Smarter model:** switch in the sidebar dropdown, or pass at startup:

```r
ggbot(mydata, model = "deepseek-coder-v2:lite")
```

---

## Notes

- Run `ggbot()` in a **dedicated R session** — Shiny blocks the console
- Keep a Terminal window open with `ollama serve` running
- First run after install will be slow (model loading); subsequent runs are faster
- The app works best with column names that are real words — it reads your data structure and uses it to interpret your commands

---

## How it works

```
browser mic → Whisper (local STT) → Ollama LLM → ggplot2 code → plot
```

Audio is captured in the browser and transcribed locally with Whisper. The transcript is sent to a local Ollama model which generates R code. The code is evaluated and the plot is displayed — nothing leaves your machine.
