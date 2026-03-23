test_that("build_prompt includes the data frame name", {
  p <- build_prompt(mtcars, "mtcars")
  expect_true(grepl("mtcars", p, fixed = TRUE))
})

test_that("build_prompt includes column names from the data", {
  p <- build_prompt(mtcars, "mtcars")
  expect_true(grepl("mpg", p, fixed = TRUE))
})

test_that("build_prompt includes summary stats", {
  p <- build_prompt(mtcars, "mtcars")
  # summary() output contains "Min." for numeric columns
  expect_true(grepl("Min.", p, fixed = TRUE))
})

test_that("build_prompt includes the head of the data frame as CSV", {
  p <- build_prompt(mtcars, "mtcars")
  # write.csv of head(mtcars) will include row numbers and column names
  expect_true(grepl("\"mpg\"", p, fixed = TRUE))
})

test_that("build_prompt works with a custom-named data frame", {
  my_data <- data.frame(x = 1:5, y = rnorm(5))
  p <- build_prompt(my_data, "my_data")
  expect_true(grepl("my_data", p, fixed = TRUE))
  expect_true(grepl("\"x\"", p, fixed = TRUE))
})
