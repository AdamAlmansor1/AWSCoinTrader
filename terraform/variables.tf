variable "region" {
  default = "ap-southeast-2"
}

variable "coin_gecko_key" {
  description = "API key for CoinGecko"
  type        = string
}

variable "database_name" {
  default = "crypto_timestream_db"
}

variable "crypto_prices_table_name" {
  default = "crypto_prices"
}

variable "trade_signals_table_name" {
  default = "trade_signals"
}

variable "trade_states_bucket" {
  default = "trade-states-bucket"
}
