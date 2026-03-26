test_that("extract_code pulls out a ```r block", {
  response <- "Sure! Here you go:\n```r\nplot(1:10)\n```\nHope that helps."
  expect_equal(extract_code(response), "plot(1:10)\n")
})

test_that("extract_code handles ``` without r tag", {
  response <- "```\nhist(mtcars$mpg)\n```"
  expect_equal(extract_code(response), "hist(mtcars$mpg)\n")
})

test_that("extract_code returns NULL when no code block", {
  response <- "I can only help with plotting requests."
  expect_null(extract_code(response))
})

test_that("extract_code handles multiline code blocks", {
  code <- "par(mfrow = c(1, 2))\nhist(mtcars$mpg)\nhist(mtcars$wt)\n"
  response <- paste0("```r\n", code, "```")
  expect_equal(extract_code(response), code)
})

test_that("extract_code strips <think> blocks from reasoning models", {
  response <- "<think>\nLet me think...\n```r\nwrong_code()\n```\n</think>\n```r\nplot(1:10)\n```"
  expect_equal(extract_code(response), "plot(1:10)\n")
})

test_that("extract_code handles ```{r} fences (e.g. deepseek output)", {
  response <- "```{r}\nggplot(mtcars, aes(x = wt)) + geom_point()\n```"
  expect_equal(extract_code(response), "ggplot(mtcars, aes(x = wt)) + geom_point()\n")
})

test_that("extract_code takes the first block when multiple are present", {
  response <- "```r\nplot(1:10)\n```\nOr alternatively:\n```r\nbarplot(1:5)\n```"
  result <- extract_code(response)
  expect_true(grepl("plot(1:10)", result, fixed = TRUE))
  expect_false(grepl("barplot", result, fixed = TRUE))
})
