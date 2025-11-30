# Tên project – dùng để đặt tag và tên IAM Role
variable "project_name" {
  default = "clickstream-local-sg"
}

# S3 buckets (local, không cần global-unique như AWS thật)
variable "assets_bucket_name" {
  default = "clickstream-assets-local-sg"
}

variable "raw_clickstream_bucket_name" {
  default = "clickstream-raw-local-sg"
}

# Đường dẫn file .zip của Lambda (tương đối với thư mục terraform)
variable "lambda_ingest_zip_path" {
  default = "lambda/ingest.zip"
}

variable "lambda_etl_zip_path" {
  default = "lambda/etl.zip"
}

# Lịch ETL – chạy mỗi 1 phút ở local để dễ test
variable "etl_schedule_expression" {
  default = "rate(1 minute)"
}
