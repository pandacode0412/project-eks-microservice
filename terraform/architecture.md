# EKS Architecture (Terraform)

## Tóm tắt
- Region: `us-east-1`; Cluster: `phuceks` (K8s `1.32`).
- VPC CIDR `10.0.0.0/16` với 2 AZ (`us-east-1a`, `us-east-1b`), 2 public + 2 private subnet.
- Internet Gateway + NAT Gateway đơn (cost-optimized) cho outbound từ private subnet.
- EKS control plane (AWS-managed) + 1 node group `t3.medium` autoscale (min 0 / desired 2 / max 5).
- Add-ons bật: VPC CNI, CoreDNS, kube-proxy, EBS CSI, Metrics Server.
- Karpenter-ready: tag discovery trên private subnet + node SG; Terraform module `iam-karpenter-role` chuẩn bị OIDC/IAM role.

## Sơ đồ khối (ASCII)
```
                AWS Account (115228050885) - us-east-1
┌───────────────────────────────────────────────────────────┐
│ VPC 10.0.0.0/16 (phuceks)                            │
│                                                           │
│  IGW                               NAT GW (1 AZ)          │
│   │                                      │                │
│   ├──────────────┬───────────────────────┘                │
│   │              │                                        │
│ Public Subnets   │                                        │
│  - 10.0.1.0/24   │                                        │
│  - 10.0.2.0/24   │                                        │
│  (ELB/ALB)       │                                        │
│                  │                                        │
│                Private Subnets (worker nodes, pods)       │
│                 - 10.0.3.0/24 (tagged karpenter discovery)│
│                 - 10.0.4.0/24 (tagged karpenter discovery)│
│                                                          │
│   ┌───────────────────────────────────────────────────┐  │
│   │           EKS Control Plane (managed)             │  │
│   └───────────────────────────────────────────────────┘  │
│                ▲                    │                    │
│                │                    ▼                    │
│   ┌──────────────────────────┐  Add-ons (in cluster)     │
│   │ Managed Node Group       │   - VPC CNI               │
│   │ t3.medium (min0/max5)    │   - CoreDNS               │
│   │                          │   - kube-proxy            │
│   │ SG tagged karpenter disc │   - EBS CSI               │
│   └──────────────────────────┘   - Metrics Server        │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

## Thành phần & cấu hình chính
- `terraform/1-vpc.tf`: tạo VPC, subnet public/private, IGW, NAT GW; gắn tag `karpenter.sh/discovery` và `kubernetes.io/cluster/...` lên private subnet.
- `terraform/2-eks.tf`: tạo EKS, bật add-ons, node group `t3.medium`, cho phép public endpoint access; tag node SG cho Karpenter.
- `terraform/iam-karpenter-role`: chuẩn bị IAM/OIDC cho Karpenter Controller + NodeClass (triển khai Karpenter sau khi cluster sẵn sàng).
- Provider Helm/Kubernetes (comment trong `0-providers.tf`): bật khi muốn Terraform cài chart (ALB Controller, Vault, Karpenter, Istio/Knative, v.v.).

## Yêu cầu bên ngoài
- AWS IAM đủ quyền: EKS, VPC, IAM, EC2, EBS (đã liệt kê trong `terraform/README.md`).
- Công cụ: `terraform>=1.0`, `awscli`, `kubectl`, `helm` (nếu dùng Helm provider), `istioctl` (nếu định triển khai Istio/Knative).
- Kết nối: AWS credentials đã `aws configure`; nếu dùng Helm/Kubernetes provider, cần `aws eks get-token` hoạt động.

## Ghi chú triển khai
- Luôn `terraform init -> terraform plan -> terraform apply` ở thư mục `terraform/`.
- Sau khi apply, cập nhật kubeconfig: `aws eks update-kubeconfig --region us-east-1 --name phuceks`.
- Karpenter: apply chart/CRDs sau khi cluster ready; đảm bảo thêm `KarpenterNodeRole` vào `aws-auth` ConfigMap (xem `karpenter/README.md`).
