# --- Code sanitizer (sanitize_code) ----------------------------------------

test_that("sanitize_code strips install.packages lines", {
  code <- 'install.packages("dplyr")\nlibrary(ggplot2)\nggplot(mtcars, aes(mpg, wt)) + geom_point()'
  cleaned <- sanitize_code(code)
  expect_false(grepl("install.packages", cleaned))
  expect_true(grepl("ggplot", cleaned))
})

test_that("sanitize_code strips if-require-install boilerplate", {
  code <- 'if (!require(palmerpenguins)) {\n  install.packages("palmerpenguins")\n}\nhist(penguins$bill_depth_mm)'
  cleaned <- sanitize_code(code)
  expect_false(grepl("require", cleaned))
  expect_false(grepl("install.packages", cleaned))
  expect_true(grepl("hist", cleaned))
})

test_that("sanitize_code strips remove.packages", {
  code <- 'remove.packages("ggplot2")\nplot(1:10)'
  cleaned <- sanitize_code(code)
  expect_false(grepl("remove.packages", cleaned))
  expect_true(grepl("plot", cleaned))
})

test_that("sanitize_code leaves clean code untouched", {
  code <- "library(ggplot2)\nggplot(mtcars, aes(mpg, wt)) + geom_point()"
  expect_equal(sanitize_code(code), code)
})

test_that("sanitize_code handles code that is only install.packages", {
  code <- 'install.packages("dplyr")'
  cleaned <- sanitize_code(code)
  expect_equal(trimws(cleaned), "")
})
