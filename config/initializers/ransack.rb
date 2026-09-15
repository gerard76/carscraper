Ransack.configure do |config|
  # A car whose distance or mileage we do not know belongs at the bottom of the
  # table, whichever way the column is sorted. Postgres puts nulls first when
  # sorting descending, which filled the top of the table with blanks.
  config.postgres_fields_sort_option = :nulls_always_last
end
