# Tests that call Ollama to verify the quality of generated plot code.
# These are skipped automatically when Ollama is not running.

test_that("LLM generates valid base R scatter plot code", {
  skip_if_no_ollama()
  result <- ask_ggbot("scatter plot of mpg vs wt")
  expect_false(is.null(result$code), info = "Expected a code block in response")
  run <- try_plot(result$code)
  expect_true(run$success, info = paste0("Plot failed: ", run$error, "\nCode:\n", run$code))
})

test_that("LLM generates valid grouped scatter plot code", {
  skip_if_no_ollama()
  result <- ask_ggbot("scatter plot of mpg vs wt, colored by number of cylinders")
  expect_false(is.null(result$code))
  run <- try_plot(result$code)
  expect_true(run$success, info = paste0("Plot failed: ", run$error, "\nCode:\n", run$code))
})

test_that("LLM generates valid histogram code", {
  skip_if_no_ollama()
  result <- ask_ggbot("histogram of mpg")
  expect_false(is.null(result$code))
  run <- try_plot(result$code)
  expect_true(run$success, info = paste0("Plot failed: ", run$error, "\nCode:\n", run$code))
})

test_that("LLM generates valid boxplot code", {
  skip_if_no_ollama()
  result <- ask_ggbot("boxplot of mpg grouped by number of cylinders")
  expect_false(is.null(result$code))
  run <- try_plot(result$code)
  expect_true(run$success, info = paste0("Plot failed: ", run$error, "\nCode:\n", run$code))
})

test_that("LLM code references the correct data frame name", {
  skip_if_no_ollama()
  result <- ask_ggbot("scatter plot of mpg vs wt")
  skip_if(is.null(result$code), "LLM did not return a code block")
  expect_true(
    grepl("mtcars", result$code, fixed = TRUE),
    info = "Code does not reference the mtcars data frame"
  )
})

test_that("LLM includes library() call when using tinyplot", {
  skip_if_no_ollama()
  result <- ask_ggbot("scatter plot of mpg vs wt colored by cyl")
  if (!is.null(result$code) && grepl("tinyplot", result$code, fixed = TRUE)) {
    expect_true(
      grepl("library(tinyplot)", result$code, fixed = TRUE),
      info = "tinyplot used but not loaded with library()"
    )
  } else {
    skip("LLM chose base R for this request (acceptable)")
  }
})
