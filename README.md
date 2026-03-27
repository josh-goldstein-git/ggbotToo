# ggbotToo

Voice-controlled R plotting. Speak a command, get a ggplot2 plot. Free, local, no API key needed.

A free, local alternative to the brilliant [ggbot2](https://github.com/tidyverse/ggbot2), which inspired this project but requires a paid API key. Runs entirely on your machine using [Ollama](https://ollama.com) and [Whisper](https://github.com/openai/whisper).

---

## Requirements

- Mac with Apple Silicon (M1/M2/M3)
- R >= 4.3
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

**Step 3 — First-time setup** (downloads models, one time)

```r
library(ggbotToo)
ggbot_setup()
```

This will:
- Check Ollama is running (start it with `ollama serve` in Terminal if needed)
- Pull the default language model (`deepseek-coder-v2:lite`, ~9GB)
- Download the Whisper speech-to-text model (~75MB)

---

## Usage

```r
library(ggbotToo)
ggbot(mydata)
```

This opens a Shiny app in your browser. Hold the **Hold to speak** button and describe the plot you want. Release to transcribe and generate. You can also type commands in the text box.

**Default model:** `deepseek-coder-v2:lite` — good balance of quality and speed.
Switch models in the sidebar dropdown, or pass at startup:

```r
ggbot(mydata, model = "qwen2.5-coder")
```

---

## Walkthrough

Here is a typical session using the Palmer Penguins dataset. Each step shows what you would say (or type) and what the app produces.

**Setup:**
```r
library(ggbotToo)
library(palmerpenguins)
ggbot(penguins)
```

**Step 1** — *"scatter plot of bill length by bill depth"*

The app generates a basic scatter plot. You see the ggplot2 code in the Code panel and the plot in the Plot panel.

**Step 2** — *"color the points by species"*

The app remembers the previous plot and adds `color = species` to the aesthetic mapping.

**Step 3** — *"add a smooth regression line"*

A `geom_smooth()` layer is added on top of the existing scatter plot.

**Step 4** — *"add a title Penguin Bill Dimensions"*

`ggtitle("Penguin Bill Dimensions")` is appended to the plot.

**Step 5** — *"make the axis labels larger"*

The theme is updated with larger axis text. Each refinement builds on the previous code — nothing is lost.

If the generated code has an error, the app automatically asks the LLM to fix it and retries once.

---

## Notes

- Run `ggbot()` in a **dedicated R session** — Shiny blocks the console
- Keep a Terminal window open with `ollama serve` running
- First run after install will be slow (model loading); subsequent runs are faster
- The app works best with column names that are real words — it reads your data structure and uses it to interpret your commands
- Also supports base R / tinyplot: `ggbot(mydata, prompt = "baseR")`

---

## How it works

```
browser mic → Whisper (local STT) → Ollama LLM → ggplot2 code → plot
```

Audio is captured in the browser and transcribed locally with Whisper. The transcript is sent to a local Ollama model which generates R code. The code is evaluated and the plot is displayed — nothing leaves your machine.
