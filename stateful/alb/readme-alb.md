# AWS ALB on EKS (AWS Load Balancer Controller) — Hướng dẫn chạy theo repo này

Tài liệu này hướng dẫn cài **AWS Load Balancer Controller** và tạo **ALB Ingress** cho các service trong thư mục `stateful/services/`.

## Điều kiện trước khi chạy

- Bạn đã deploy EKS bằng Terraform và đã cấu hình kubeconfig:

```bash
aws eks update-kubeconfig --region us-east-1 --name phuceks
kubectl cluster-info
```

- Có công cụ: `kubectl`, `helm`, `awscli` (và có AWS credentials hợp lệ).

## Tổng quan các file trong repo

- **Helm chart controller**: `stateful/alb/aws-load-balancer-controller/`
- **Values đã cấu hình sẵn**: `stateful/alb/aws-load-balancer-controller/values.yaml`
  - `clusterName: phuceks`
  - `serviceAccount.annotations.eks.amazonaws.com/role-arn: arn:aws:iam::115228050885:role/aws-load-balancer-controller-Role`
- **Ingress mẫu**: `stateful/alb/ing.yaml`
  - Host:
    - `test.onefirefly.click` → `frontend-service:80`
    - `api.onefirefly.click` → `api-gateway:8080` và `/ws` → `notification-service:8083`

## Bước 1 — Tạo IAM Policy + IAM Role (IRSA) cho controller

Controller chạy trong cluster nhưng cần quyền AWS để tạo ALB/TargetGroup/SecurityGroup… Vì repo này dùng **IRSA**, bạn cần tạo:

- IAM Policy: `AWSLoadBalancerControllerIAMPolicy`
- IAM Role: `aws-load-balancer-controller-Role`
- Trust policy: trỏ về **OIDC provider** của cluster `phuceks`
- ServiceAccount: do chart tạo, namespace `kube-system`, service account name theo chart (mặc định)

### 1.1. Lấy OIDC issuer của cluster

```bash
aws eks describe-cluster \
  --name phuceks \
  --region us-east-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text
```

### 1.2. Tạo IAM policy chuẩn cho AWS Load Balancer Controller

```bash
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json
```

Ghi lại `Policy ARN` trả về.

### 1.3. Tạo IAM role đúng ARN đang set trong values.yaml

Repo đang kỳ vọng role ARN:

- `arn:aws:iam::115228050885:role/aws-load-balancer-controller-Role`

Bạn cần tạo role này, attach policy ở bước 1.2 và trust policy đúng OIDC issuer.

Gợi ý kiểm tra nhanh role đã tồn tại chưa:

```bash
aws iam get-role --role-name aws-load-balancer-controller-Role
```

> Nếu bạn muốn mình viết sẵn file trust policy JSON đúng cho bạn copy/paste, hãy gửi mình output của bước **1.1** (OIDC issuer).

## Bước 2 — Cài AWS Load Balancer Controller (dùng chart trong repo)

### 2.1. Cài CRDs

```bash
kubectl apply -f stateful/alb/aws-load-balancer-controller/crds/crds.yaml
```

### 2.2. Cài controller bằng Helm

```bash
helm upgrade --install aws-load-balancer-controller \
  -n kube-system --create-namespace \
  stateful/alb/aws-load-balancer-controller \
  -f stateful/alb/aws-load-balancer-controller/values.yaml
```

### 2.3. Kiểm tra controller đã chạy

```bash
kubectl get pods -n kube-system | grep -i load-balancer-controller
kubectl get ingressclass
```

## Bước 3 — Deploy application services và tạo ALB Ingress

### 3.1. Deploy các service app

Bạn cần deploy các service để `Ingress` có backend hợp lệ (`frontend-service`, `api-gateway`, `notification-service`).

Trong repo, chúng nằm ở `stateful/services/` (xem `stateful/README.md` để deploy theo script hoặc apply manifest).

### 3.2. Apply Ingress để controller tạo ALB

```bash
kubectl apply -f stateful/alb/ing.yaml
kubectl get ingress
```

Khi ALB được tạo xong, cột `ADDRESS` sẽ hiện DNS name của ALB.

## Bước 4 — Trỏ DNS domain vào ALB

Ingress đang dùng 2 host:

- `test.onefirefly.click`
- `api.onefirefly.click`

Bạn cần tạo bản ghi DNS (CNAME hoặc ALIAS) trỏ 2 domain này về DNS name của ALB (lấy ở `kubectl get ingress`).

## Troubleshooting nhanh

### 1) Ingress không ra `ADDRESS`

Chạy:

```bash
kubectl describe ingress stateful-ingress
kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=200
```

Nguyên nhân hay gặp:

- IRSA/IAM role thiếu quyền hoặc trust policy sai
- Chưa có OIDC provider của cluster
- Backend service chưa tồn tại / sai port

### 2) Backend trả 503 / target unhealthy

Kiểm tra service endpoints:

```bash
kubectl get svc frontend-service api-gateway notification-service
kubectl get endpoints frontend-service api-gateway notification-service
kubectl get pods -o wide
```

### 3) Dọn ALB / Ingress

Repo có script:

```bash
cd stateful/alb
./uninstall_alb.sh
```

Hoặc xóa riêng ingress:

```bash
kubectl delete -f stateful/alb/ing.yaml
```
