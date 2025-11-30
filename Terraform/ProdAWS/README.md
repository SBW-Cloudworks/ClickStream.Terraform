# SBW ClickStream – Prod AWS Terraform (Hands-on)

Bài này hướng dẫn từng bước (như “cầm tay chỉ việc”) để dựng hạ tầng Production theo kiến trúc trong `README.md` gốc: VPC (public + 2 private), S3 raw/processed/media, Lambda ingest + ETL (API Gateway + EventBridge), Cognito, SNS, EC2 cho OLTP/DWH/Shiny, ALB nội bộ cho Shiny, tùy chọn Amplify.

## 0) Bạn cần gì trước khi bắt đầu (step-by-step)
1. **Cài công cụ**
   - Cài Terraform >= 1.5 (https://developer.hashicorp.com/terraform/downloads).
   - Cài AWS CLI (https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
   - Kiểm tra: `terraform version` và `aws --version`.
2. **Đăng nhập AWS**
   - Chạy `aws configure` để nhập Access Key/Secret/Region/Output, hoặc đã có profile trong `~/.aws/credentials`.
   - Dùng profile nào thì đặt vào `aws_profile` trong `prod.auto.tfvars` (để Terraform dùng đúng profile).
3. **Kiểm tra quyền**
   - Cần quyền tạo: VPC/Subnet/IGW/NAT, IAM roles/policies, Lambda, API Gateway, EventBridge, EC2, S3, SNS, Cognito và (nếu bật) Amplify.
   - Nếu thiếu quyền, `terraform apply` sẽ báo lỗi (hãy xin thêm quyền hoặc chạy với role đủ quyền).
4. **Chọn region & AZ**
   - Chọn region có **tối thiểu 2 AZ** (ví dụ `ap-southeast-1`).
   - Kiểm tra: `aws ec2 describe-availability-zones --region <region>`.
   - Nếu thấy ít hơn 2 AZ khả dụng, chọn region khác.
5. **Chuẩn bị Lambda ZIP**
   - Build 2 file zip: ingest và etl.
   - Ghi đúng đường dẫn local vào `lambda_ingest_zip`, `lambda_etl_zip` (trong `prod.auto.tfvars`).
   - Kiểm tra file tồn tại: `ls <path>` (Windows: `dir <path>`).
6. **Chuẩn bị SSH/SSM**
   - Nếu muốn SSH: tạo EC2 Key Pair trong AWS, điền `oltp_key_name`, `dwh_key_name`, `shiny_key_name`.
   - Nếu chỉ dùng SSM Session Manager: có thể để trống các key name (đã gán policy SSM mặc định).
   - Đảm bảo máy bạn có thể vào VPC (VPN/DirectConnect) trước khi SSH nếu không có IP public.
7. **Amplify** (mặc định đang **bật**: `enable_amplify = true`)
   - Cần repo Git (HTTPS) và personal access token (PAT) hợp lệ.
   - Điền `amplify_repo_url`, `amplify_access_token`, `amplify_branch_name`.
   - Nếu chưa cần Amplify, đặt `enable_amplify = false` trong `prod.auto.tfvars`.

## 1) Chuẩn bị remote state (nên làm)
**Tại sao cần remote state?**
- State là “sự thật” để Terraform biết đã tạo gì; nếu giữ local dễ mất/ghi đè, không khóa được khi nhiều người chạy.  
- Remote state (S3) + lock (DynamoDB hoặc phương án khác) giúp tránh xung đột, có bản sao an toàn, dùng chung cho team/CI.

Tạo S3 + DynamoDB để lưu state/lock, sau đó init backend:
```bash
aws s3api create-bucket --bucket <tfstate-bucket> --region <region> --create-bucket-configuration LocationConstraint=<region>
aws dynamodb create-table --table-name <lock-table> \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

terraform -chdir=Terraform/ProdAWS init \
  -backend-config="bucket=<tfstate-bucket>" \
  -backend-config="key=clickstream/prod/terraform.tfstate" \
  -backend-config="region=<region>" \
  -backend-config="dynamodb_table=<lock-table>"
```
Ghi chú về lock (chọn 1) + vì sao:
- **S3 + DynamoDB (khuyến nghị trên AWS)**: Đây là cách tích hợp sẵn để khóa state khi dùng backend S3; ngăn hai người `apply` cùng lúc dẫn tới xung đột/ hỏng state.
- **Terraform Cloud/Enterprise (remote backend)**: Có state + lock + UI sẵn, không cần dựng DynamoDB; phù hợp nếu muốn tối giản vận hành và có giao diện kiểm soát run.
- **Consul backend**: Dùng Consul KV làm state/lock; phù hợp khi bạn đã có/h muốn tự host một KV store (on-prem/HCP).
- **Không lock** (S3 không cấu hình `dynamodb_table`): Không nên dùng; rủi ro cao khi nhiều người chạy đồng thời sẽ corrupt state.

## 2) Tạo file biến `prod.auto.tfvars` (như một gói cấu hình)
- **Vì sao cần tfvars riêng**: Giữ giá trị môi trường (tên bucket, key SSH, repo Amplify, đường dẫn ZIP) tách khỏi code; có thể version và chia sẻ cho team/CI.
- **Dùng file mẫu**: Đã có `Terraform/ProdAWS/prod.auto.tfvars` (placebo). Sửa trực tiếp file này với giá trị thật.
- **Các nhóm biến chính cần điền**:
  - Region/profile: `region`, `aws_profile`.
  - Buckets: `bucket_media`, `bucket_raw`, `bucket_processed`.
  - Lambda: đường dẫn ZIP `lambda_ingest_zip`, `lambda_etl_zip`.
  - Mạng/egress: `enable_nat_gateway`, `allowed_admin_cidrs` (mở Shiny ALB cho IP nào).
  - EC2: key pair `oltp_key_name`, `dwh_key_name`, `shiny_key_name`; AMI tùy chọn nếu không dùng Amazon Linux 2 mặc định.
  - Cognito/SNS: `cognito_user_pool_name`, `cognito_client_name`, `sns_topic_name`.
  - Amplify (mặc định bật): `enable_amplify`, `amplify_repo_url`, `amplify_access_token`, `amplify_branch_name`.
  - Khác: `log_retention_days`, `shiny_user_data` nếu bạn thay script cài Shiny.
- **Ví dụ (có sẵn trong file mẫu)**:
  ```hcl
  region           = "ap-southeast-1"
  aws_profile      = "prod"
  bucket_media     = "sbw-clickstream-media-prod"
  bucket_raw       = "sbw-clickstream-raw-prod"
  bucket_processed = "sbw-clickstream-processed-prod"
  lambda_ingest_zip = "../../artifacts/lambda_ingest.zip"
  lambda_etl_zip    = "../../artifacts/lambda_etl.zip"
  enable_nat_gateway  = true
  allowed_admin_cidrs = ["203.0.113.0/24"]
  oltp_key_name  = "prod-key"
  dwh_key_name   = "prod-key"
  shiny_key_name = "prod-key"
  cognito_user_pool_name = "clickstream-users"
  cognito_client_name    = "clickstream-app-client"
  sns_topic_name         = "clickstream-prod-alerts"
  enable_amplify       = true
  amplify_repo_url     = "https://github.com/<org>/<repo>"
  amplify_access_token = "<gh_pat>"
  amplify_branch_name  = "main"
  log_retention_days   = 30
  ```
- **Mẹo nhanh**:
  - Muốn private tuyệt đối (không egress Internet): đặt `enable_nat_gateway = false` (S3 vẫn truy cập qua VPC Endpoint).
  - `allowed_admin_cidrs` trống → Shiny ALB không mở cho ai; dùng VPN/SSM trước khi mở.
  - `shiny_user_data` mặc định là placeholder; hãy thay bằng script cài R + Shiny Server + reverse proxy.
  - Dùng SSM thay SSH? Có thể bỏ key name (policy SSM đã gán).

## 3) Chạy Terraform
```bash
terraform -chdir=Terraform/ProdAWS init   # lần đầu hoặc khi đổi backend
terraform -chdir=Terraform/ProdAWS plan   -var-file=prod.auto.tfvars
terraform -chdir=Terraform/ProdAWS apply  -var-file=prod.auto.tfvars
```

## 4) Kiểm tra kết quả (Outputs)
Xem ở đâu?
- Ngay sau `terraform apply`: phần cuối log sẽ in block Outputs.
- Hoặc xem lại bất kỳ lúc nào: `terraform -chdir=Terraform/ProdAWS output` (thêm `-json` nếu cần cho máy đọc).

Bạn cần chú ý các giá trị:
- `api_invoke_url` – URL API Gateway (gửi request POST /click).
- `lambda_functions` – ARN ingest/etl.
- `s3_buckets` – tên media/raw/processed.
- `cognito.user_pool_id`, `cognito.client_id` – cấu hình frontend.
- `sns_topic_arn` – gắn vào cảnh báo.
- `shiny_alb_dns` – DNS ALB nội bộ cho Shiny (chỉ có khi `enable_shiny_alb = true`).
- `ec2_instances` – ID EC2 (OLTP, DWH, Shiny).
- `api_invoke_url` – URL API Gateway (gửi request POST /click).
- `lambda_functions` – ARN ingest/etl.
- `s3_buckets` – tên media/raw/processed.
- `cognito.user_pool_id`, `cognito.client_id` – cấu hình frontend.
- `sns_topic_arn` – gắn vào cảnh báo.
- `shiny_alb_dns` – DNS ALB nội bộ cho Shiny (chỉ có khi `enable_shiny_alb = true`).
- `ec2_instances` – ID EC2 (OLTP, DWH, Shiny).

## 5) Khớp với kiến trúc
- Public: API Gateway (+ tùy chọn Amplify/CloudFront).
- Private OLTP: subnet riêng + SG cho DB.
- Private Analytics: subnet riêng + SG cho DWH và Shiny; ALB nội bộ (nếu bật).
- Luồng dữ liệu: API GW → Lambda ingest → S3 raw → EventBridge → Lambda ETL → S3 processed → EC2 warehouse → Shiny dashboards.
- Kiểm soát: S3 gateway endpoint, SG phân tách, IAM giới hạn S3/SNS/Logs, S3 block public + SSE + versioning, log retention cấu hình qua `log_retention_days`.

## 6) Tiếp theo nên làm gì
1. Thay `shiny_user_data` bằng script cài đặt thực tế (R, Shiny Server, nginx).
2. Thêm CloudWatch alarms (CPU/disk EC2, Lambda errors, API 5xx, S3 4xx/5xx qua CloudFront nếu dùng Amplify).
3. Nếu có domain, cấu hình Route53 + ACM + custom domain cho API/CloudFront (không nằm trong file này).
4. Tự động build/pack Lambda zips trong pipeline và trỏ `lambda_*_zip` tới artifact mới nhất.
