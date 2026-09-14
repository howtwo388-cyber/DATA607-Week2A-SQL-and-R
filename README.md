# DATA 607 Week 2A: SQL and R Movie Ratings

## Author

Patricio Romero

## Project Overview

This project collects and analyzes ratings for six recent movies. The survey included 35 participants. The responses were stored in a normalized SQLite database and then loaded into an R dataframe for analysis.

The project demonstrates how to create relational database tables, define primary and foreign keys, handle missing values, join SQL tables, and analyze the resulting data in R.

## Movies

1. Spider-Man: Brand New Day
2. The Odyssey
3. Toy Story 5
4. Coyote vs. Acme
5. By Any Means
6. Onslaught

## Database Structure

The SQLite database contains the following tables:

- `participants`: Stores anonymous participant codes.
- `movies`: Stores movie IDs and titles.
- `ratings`: Stores the relationship between participants, movies, and ratings.
- `survey_import`: Temporary staging table used to import the original survey responses.

The `ratings` table uses a composite primary key containing `participant_id` and `movie_id`. Foreign keys connect the ratings to the participants and movies tables.

## Missing-Rating Strategy

A response of “I have not seen this movie” is not treated as a numerical rating. These responses are stored as `NULL` in SQL and become `NA` when loaded into R.

Missing ratings are counted, but they are excluded from average and median calculations. This prevents movies that participants have not seen from receiving artificially low ratings.

## Main Results

The database contains:

- 35 participants
- 6 movies
- 210 possible rating records
- 82 available ratings
- 128 missing ratings
- 26 participants who rated at least one movie
- 9 participants who did not rate any movies

Coyote vs. Acme had the highest average rating, at 4.45, based on 11 available ratings.

Spider-Man: Brand New Day was the most frequently rated movie, with 22 ratings, and had an average rating of 4.36.

By Any Means and Onslaught were the least frequently rated movies, with 7 ratings each.

## Files

- `week2a_sql_r_code.R`: Creates and populates the SQLite database, loads the normalized data into R, performs the analysis, creates the graph, and validates the database.
- `week2a_sql_r_approach.Rmd`: Describes the planned approach and anticipated challenges.
- `week2a_sql_r_approach.html`: Rendered version of the planned approach.
- `DATA607-Week2A-SQL-and-R.Rproj`: RStudio project file.
- `.gitignore`: Prevents private survey data and local database files from being uploaded.

## Required R Packages

The project uses the following R packages:

```r
install.packages(c(
  "DBI",
  "RSQLite",
  "readr",
  "dplyr",
  "ggplot2"
))
```

## Running the Project

Open the RStudio project and run:

```r
source("week2a_sql_r_code.R")
```

The original survey CSV must be stored locally at:

```text
data_private/movie_ratings_raw.csv
```

The script creates the SQLite database inside the local `database` folder.

## Privacy

The original survey CSV, SQLite database, and deployment files are excluded from GitHub. Participant identities are replaced with anonymous codes such as `P001`, `P002`, and `P003`.

## Limitations

This project uses a small convenience sample. Therefore, the results describe only the people who completed the survey and should not be generalized to the entire population.

Some movies received relatively few ratings, so their average ratings should be interpreted carefully.

## Video Explainer

My Week 2A video presentation is available here:

[Watch the DATA 607 Week 2A Video Explainer](https://youtu.be/CX8djwpKEk8)

## AI Use

ChatGPT was used to help interpret the assignment requirements, improve the English writing, organize the project, and provide coding guidance. I ran the code and reviewed the results to confirm that the analysis was accurate.
