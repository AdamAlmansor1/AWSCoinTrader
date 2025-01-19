output "timestream_database" {
  value = aws_timestreamwrite_database.crypto_timestream_db.database_name
}

output "crypto_prices_table" {
  value = aws_timestreamwrite_table.crypto_prices.table_name
}
