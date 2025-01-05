variable "region" {
  default = "ap-southeast-2"
}

variable "queue_name" {
  default = "crypto-prices"
}

variable "COIN_GECKO_KEY" {
  description = "API key for CoinGecko"
  type        = string
}