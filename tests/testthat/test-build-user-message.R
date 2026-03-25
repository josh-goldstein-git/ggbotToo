test_that("build_user_message returns user_text unchanged when no current code", {
  expect_equal(build_user_message("make a scatter plot"), "make a scatter plot")
  expect_equal(build_user_message("make a scatter plot", NULL), "make a scatter plot")
})

test_that("build_user_message includes current code block when provided", {
  code <- 'ggplot(df, aes(x = x, y = y)) + geom_point()'
  msg  <- build_user_message("add a title", code)
  expect_true(grepl("Current plot code", msg, fixed = TRUE))
  expect_true(grepl(code, msg, fixed = TRUE))
})

test_that("build_user_message includes the user request after the code", {
  msg <- build_user_message("color by species", "ggplot(df, aes(x,y)) + geom_point()")
  expect_true(grepl("User request: color by species", msg, fixed = TRUE))
  # code block appears before user request
  expect_lt(regexpr("```r", msg), regexpr("User request:", msg))
})

test_that("build_user_message wraps code in an r code fence", {
  msg <- build_user_message("refine", "ggplot(df) + geom_point()")
  expect_true(grepl("```r\n", msg, fixed = TRUE))
  expect_true(grepl("\n```\n", msg, fixed = TRUE))
})
