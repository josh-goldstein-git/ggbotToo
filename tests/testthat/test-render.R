# Tests for the eval→print pipeline used in renderPlot.
#
# The key invariant: code extracted from an LLM response must produce a
# *visible* ggplot result when eval'd, so that Shiny's renderPlot (which
# calls print() only on visible results via withVisible()) actually draws
# the plot.  A silent or NULL result renders a blank plot panel.

eval_code <- function(code) {
  withVisible(
    eval(parse(text = code), envir = new.env(parent = globalenv()))
  )
}

test_that("plain ggplot code produces a visible ggplot result", {
  code <- "ggplot2::ggplot(mtcars, ggplot2::aes(x = wt, y = mpg)) + ggplot2::geom_point()"
  result <- eval_code(code)
  expect_true(result$visible)
  expect_true(inherits(result$value, "gg"))
})

test_that("ggplot code with library() call still produces a visible result", {
  # LLMs frequently prepend library(ggplot2); the last expression must remain visible
  code <- "library(ggplot2)\nggplot(mtcars, aes(x = wt, y = mpg)) + geom_point()"
  result <- eval_code(code)
  expect_true(result$visible)
  expect_true(inherits(result$value, "gg"))
})

test_that("code from a ```{r} fenced block evaluates correctly end-to-end", {
  # Simulates the full extract → eval pipeline for deepseek-style responses
  llm_response <- "```{r}\nlibrary(ggplot2)\nggplot(mtcars, aes(x = wt, y = mpg)) + geom_point()\n```"
  code <- ggbotToo:::extract_code(llm_response)
  expect_false(is.null(code))
  result <- eval_code(code)
  expect_true(result$visible)
  expect_true(inherits(result$value, "gg"))
})

test_that("base R plot code does not error and draws silently", {
  # hist() draws via side effects; result is invisible — that's expected
  code <- "hist(mtcars$mpg)"
  expect_no_error(eval_code(code))
})
