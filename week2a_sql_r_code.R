library(DBI)
library(RSQLite)
library(readr)
library(dplyr)
library(ggplot2)

# Create the database folder if it does not exist.
dir.create("database", showWarnings = FALSE)

# Open the SQLite database or create it if necessary.
con <- dbConnect(
  RSQLite::SQLite(),
  dbname = "database/movie_ratings.sqlite"
)

# Enable foreign key enforcement.
dbExecute(con, "PRAGMA foreign_keys = ON;")

# Create the participants table with anonymous codes.
dbExecute(con, "
  CREATE TABLE IF NOT EXISTS participants (
    participant_id INTEGER PRIMARY KEY,
    participant_code TEXT NOT NULL UNIQUE
  );
")

# Create the movies table.
dbExecute(con, "
  CREATE TABLE IF NOT EXISTS movies (
    movie_id INTEGER PRIMARY KEY,
    movie_title TEXT NOT NULL UNIQUE
  );
")

# Create the ratings table.
# Missing ratings are stored as NULL, not zero.
dbExecute(con, "
  CREATE TABLE IF NOT EXISTS ratings (
    participant_id INTEGER NOT NULL,
    movie_id INTEGER NOT NULL,
    rating INTEGER,
    PRIMARY KEY (participant_id, movie_id),
    FOREIGN KEY (participant_id)
      REFERENCES participants(participant_id),
    FOREIGN KEY (movie_id)
      REFERENCES movies(movie_id),
    CHECK (
      rating IS NULL OR
      (typeof(rating) = 'integer' AND rating BETWEEN 1 AND 5)
    )
  );
")

# Import the CSV into SQL only if the staging table does not exist.
if (!dbExistsTable(con, "survey_import")) {
  
  stopifnot(
    file.exists("data_private/movie_ratings_raw.csv")
  )
  
  survey_raw <- read_csv(
    "data_private/movie_ratings_raw.csv",
    col_types = cols(.default = col_character()),
    name_repair = "minimal"
  )
  
  dbWriteTable(
    con,
    "survey_import",
    as.data.frame(survey_raw),
    row.names = FALSE
  )
}

# Insert anonymous participants only if the table is empty.
n_participants <- dbGetQuery(con, "
  SELECT COUNT(*) AS n FROM participants;
")$n

if (n_participants == 0) {
  dbExecute(con, "
    INSERT INTO participants
      (participant_id, participant_code)
    SELECT
      rowid,
      printf('P%03d', rowid)
    FROM survey_import;
  ")
}

# Insert the six movies only if the table is empty.
n_movies <- dbGetQuery(con, "
  SELECT COUNT(*) AS n FROM movies;
")$n

if (n_movies == 0) {
  dbExecute(con, "
    INSERT INTO movies (movie_id, movie_title)
    VALUES
      (1, 'Spider-Man: Brand New Day'),
      (2, 'The Odyssey'),
      (3, 'Toy Story 5'),
      (4, 'Coyote vs. Acme'),
      (5, 'By Any Means'),
      (6, 'Onslaught');
  ")
}

# List all database tables.
dbListTables(con)

# Verify the number of imported responses and participants.
dbGetQuery(con, "
  SELECT
    (SELECT COUNT(*) FROM survey_import) AS total_responses,
    (SELECT COUNT(*) FROM participants) AS total_participants,
    (SELECT COUNT(*) FROM movies) AS total_movies;
")

# Display the first five anonymous participants.
dbGetQuery(con, "
  SELECT *
  FROM participants
  ORDER BY participant_id
  LIMIT 5;
")

# Display the six movies.
dbGetQuery(con, "
  SELECT *
  FROM movies
  ORDER BY movie_id;
")

# Retrieve movie titles and IDs from the SQL database.
movie_list <- dbGetQuery(con, "
  SELECT movie_id, movie_title
  FROM movies
  ORDER BY movie_id;
")

# Build one SQL query for each movie-rating column.
rating_queries <- vapply(
  seq_len(nrow(movie_list)),
  function(i) {
    
    column_name <- paste0(
      "Movie Ratings [",
      movie_list$movie_title[i],
      "]"
    )
    
    quoted_column <- as.character(
      dbQuoteIdentifier(con, column_name)
    )
    
    sprintf(
      "SELECT
         rowid AS participant_id,
         %d AS movie_id,
         TRIM(%s) AS rating_text
       FROM survey_import",
      movie_list$movie_id[i],
      quoted_column
    )
  },
  character(1)
)

ratings_source_sql <- paste(
  rating_queries,
  collapse = " UNION ALL "
)

# Check for unexpected response labels.
invalid_labels <- dbGetQuery(
  con,
  paste0("
    SELECT DISTINCT rating_text
    FROM (", ratings_source_sql, ")
    WHERE rating_text IS NOT NULL
      AND rating_text NOT IN (
        '',
        'I have not seen this movie'
      )
      AND rating_text NOT GLOB '[1-5] – *'
      AND rating_text NOT GLOB '[1-5] - *';
  ")
)

if (nrow(invalid_labels) > 0) {
  print(invalid_labels)
  stop("Unexpected rating labels were found.")
}

# Insert the ratings only when the ratings table is empty.
n_ratings <- dbGetQuery(con, "
  SELECT COUNT(*) AS n
  FROM ratings;
")$n

if (n_ratings == 0) {
  dbExecute(
    con,
    paste0("
      INSERT INTO ratings (
        participant_id,
        movie_id,
        rating
      )
      SELECT
        participant_id,
        movie_id,
        CASE
          WHEN rating_text IS NULL
            OR rating_text = ''
            OR rating_text = 'I have not seen this movie'
          THEN NULL
          ELSE CAST(
            SUBSTR(rating_text, 1, 1) AS INTEGER
          )
        END AS rating
      FROM (", ratings_source_sql, ");
    ")
  )
}

# Verify the number of rating records stored in SQL.
dbGetQuery(con, "
  SELECT
    COUNT(*) AS total_records,
    COUNT(rating) AS available_ratings,
    COUNT(*) - COUNT(rating) AS missing_ratings
  FROM ratings;
")

# Load the normalized SQL data into an R dataframe.
ratings_df <- dbGetQuery(con, "
  SELECT
    p.participant_code,
    m.movie_title,
    r.rating
  FROM ratings AS r
  INNER JOIN participants AS p
    ON r.participant_id = p.participant_id
  INNER JOIN movies AS m
    ON r.movie_id = m.movie_id
  ORDER BY
    p.participant_id,
    m.movie_id;
")

# Verify that the SQL query returned 210 records.
stopifnot(nrow(ratings_df) == 210)

# Display the structure of the R dataframe.
str(ratings_df)

# Display the first twelve records.
head(ratings_df, 12)

# Count available and missing ratings in the R dataframe.
data.frame(
  total_records = nrow(ratings_df),
  available_ratings = sum(!is.na(ratings_df$rating)),
  missing_ratings = sum(is.na(ratings_df$rating))
)

# Missing-rating strategy:
#
# A response of "I have not seen this movie" is not a numerical
# rating. Therefore, it was stored in SQL as NULL rather than zero.
#
# When the SQL data is loaded into R, NULL values become NA values.
# These values are counted to measure how many participants did not
# rate each movie, but they are excluded from the calculation of the
# average and median ratings.
#
# This prevents movies that participants have not seen from receiving
# artificially low average ratings.

# Question 1:
# How many available and missing ratings does each movie have,
# and what is its average rating?

movie_summary <- ratings_df |>
  group_by(movie_title) |>
  summarise(
    total_responses = n(),
    available_ratings = sum(!is.na(rating)),
    missing_ratings = sum(is.na(rating)),
    average_rating = mean(rating, na.rm = TRUE),
    median_rating = median(rating, na.rm = TRUE),
    .groups = "drop"
  ) |>
  arrange(desc(average_rating))

# Create a rounded version for presentation.
movie_summary_display <- movie_summary |>
  mutate(
    average_rating = round(average_rating, 2),
    median_rating = round(median_rating, 2)
  )

# Display the complete movie summary.

print(movie_summary_display, width = Inf)

# Interpretation:
#
# Every movie received 35 total responses. Available ratings were
# used to calculate the average and median ratings. Missing ratings
# represent participants who did not see or did not rate the movie.
#
# Spider-Man: Brand New Day had the largest number of available
# ratings, with 22. By Any Means and Onslaught had the fewest,
# with 7 available ratings each.
#
# Because the number of available ratings differs among movies,
# average ratings should be interpreted together with the number
# of available and missing ratings.

# Create a graph of average ratings by movie.
ggplot(
  movie_summary,
  aes(
    x = reorder(movie_title, average_rating),
    y = average_rating
  )
) +
  geom_col(fill = "#2C7FB8") +
  geom_text(
    aes(label = round(average_rating, 2)),
    hjust = -0.15,
    size = 3.5
  ) +
  coord_flip() +
  scale_y_continuous(
    limits = c(0, 5),
    breaks = 0:5
  ) +
  labs(
    title = "Average Movie Ratings",
    subtitle = "Missing ratings were excluded from the averages",
    x = "Movie",
    y = "Average rating"
  ) +
  theme_minimal()

# Question 2:
# How many movies did each participant rate, and how many
# participants did not rate any movies?

participant_summary <- ratings_df |>
  group_by(participant_code) |>
  summarise(
    total_movies = n(),
    movies_rated = sum(!is.na(rating)),
    movies_not_rated = sum(is.na(rating)),
    average_rating = if (all(is.na(rating))) {
      NA_real_
    } else {
      mean(rating, na.rm = TRUE)
    },
    .groups = "drop"
  ) |>
  arrange(desc(movies_rated), participant_code)

# Create a rounded version for presentation.

participant_summary_display <- participant_summary |>
  mutate(
    average_rating = round(average_rating, 2)
  )

# Display the participant-level results.

print(participant_summary_display, n = Inf, width = Inf)

# Summarize participant engagement.

participation_summary <- participant_summary |>
  summarise(
    total_participants = n(),
    participants_with_ratings = sum(movies_rated > 0),
    participants_without_ratings = sum(movies_rated == 0),
    average_movies_rated = round(mean(movies_rated), 2)
  )

print(participation_summary, width = Inf)

# Interpretation:
#
# Of the 35 participants, 26 rated at least one movie and 9 did not
# rate any movies. Participants rated an average of approximately
# 2.34 of the 6 movies.
#
# Participants who did not rate any movies were retained in the
# database because their responses provide information about movie
# familiarity. Their missing values were not included in the
# calculation of average ratings.

# Conclusions:
#
# The survey included 35 participants and 6 movies, producing 210
# possible rating records. Of these records, 82 contained ratings
# and 128 represented movies that participants had not seen or rated.
#
# Coyote vs. Acme had the highest average rating, at 4.45, but this
# result was based on only 11 available ratings. Spider-Man: Brand
# New Day was the most frequently rated movie, with 22 ratings, and
# had an average rating of 4.36.
#
# By Any Means and Onslaught were the least frequently rated movies.
# Each movie received only 7 ratings. Their averages should therefore
# be interpreted carefully because they are based on small numbers
# of observations.
#
# Of the 35 participants, 26 rated at least one movie and 9 did not
# rate any movies. Responses for movies that were not seen were
# stored as NULL and excluded from the average calculations.
#
# This was a small convenience sample, so the results cannot represent
# the opinions of the general population. The results describe only
# the participants who completed this survey.

# Final database validation.

integrity_check <- dbGetQuery(
  con,
  "PRAGMA integrity_check;"
)

print(integrity_check)

# Stop the program if the database integrity check fails.

stopifnot(integrity_check[1, 1] == "ok")

# Check for invalid foreign-key relationships.

foreign_key_check <- dbGetQuery(
  con,
  "PRAGMA foreign_key_check;"
)

if (nrow(foreign_key_check) == 0) {
  message("Foreign key validation passed.")
} else {
  print(foreign_key_check)
  stop("Foreign key validation failed.")
}

# Verify the expected final results.

stopifnot(
  nrow(ratings_df) == 210,
  sum(!is.na(ratings_df$rating)) == 82,
  sum(is.na(ratings_df$rating)) == 128,
  nrow(movie_summary) == 6,
  nrow(participant_summary) == 35
)

message("All final data checks passed.")

# Close the database connection.

dbDisconnect(con)

message("Database connection closed successfully.")