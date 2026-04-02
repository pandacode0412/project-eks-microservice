# Huong dan chay du an `project-eks-microservice`

Tai lieu nay tong hop cach chay toan bo project tren AWS EKS dua theo cac file trong repo hien tai.

## 1) Tong quan kien truc

Project gom cac lop chinh:

- Ha tang AWS bang Terraform: VPC + EKS + node group (`terraform/`)
- Core services:
  - Kafka + Zookeeper (`kafka/`)
  - MySQL (`mysql/`)
  - Redis (`redis/`)
  - Vault (tuy chon) (`vault/`)
- Lop ung dung microservice:
  - Stateful Kubernetes (`stateful/services/`)
  - Hoac Knative Services (`knative/services/`)
- Expose ra ngoai theo 1 trong 3 huong:
  - Stateful + ALB (`stateful/alb/ing.yaml`)
  - Stateful + Istio (`stateful/istio/`)
  - Knative + Istio (`knative/services/`)

## 2) Yeu cau truoc khi chay

Can cai dat:

- `aws` CLI (da `aws configure`)
- `terraform`
- `kubectl`
- `helm`
- `istioctl` (neu chon huong Istio/Knative)
- `jq` (can cho Vault script)
- Mot shell co ho tro bash (`Git Bash`/`WSL`) de chay `*.sh`

Luu y:

- Ban dang dung Windows PowerShell, cac script `deploy_kafka.sh`, `deploy_vault.sh` la bash script.
- Co the chay script bang Git Bash/WSL, hoac tuyen bo lenh `helm/kubectl` thu cong trong PowerShell.

## 3) Cau hinh can kiem tra truoc

### 3.1 Terraform locals

File: `terraform/1-vpc.tf`

- `account_id` (hien tai: `115228050885`)
- `region` (hien tai: `us-east-1`)
- `cluster_name` (hien tai: `phuceks`)
- CIDR/AZ/subnet theo nhu cau

### 3.2 ALB controller values

File: `stateful/alb/aws-load-balancer-controller/values.yaml`

- `serviceAccount.annotations.eks.amazonaws.com/role-arn`
- `clusterName`

Phai khop voi cluster that va IAM role cua ban.

### 3.3 Domain hostnames

Dang co su khong dong nhat giua cac phan:

- Stateful ALB/Istio dang dung `test.onefirefly.click`, `api.onefirefly.click`
- Knative domain mapping dang dung `*.onefirefly.click`

Ban can chon 1 bo domain thong nhat va sua cac file lien quan truoc khi public (trong bo nay da dung `onefirefly.click`).

### 3.4 StorageClass

- MySQL/Redis/Vault dung storage class kieu EBS (`gp3`; cluster cu co the con `gp2`)
- Kafka chart dang co cau hinh persistence lien quan `nfs-client` trong `kafka/kafka-values.yaml`

Neu cluster khong co `nfs-client`, can doi ve storage class co san tren EKS (uu tien `gp3`) de PVC bind duoc.

## 4) Trinh tu deploy end-to-end

## B0 - Chuan bi bien moi truong

Trong PowerShell:

```powershell
$env:AWS_REGION="us-east-1"
$env:CLUSTER_NAME="phuceks"
```

## B1 - Tao ha tang bang Terraform

```powershell
cd "D:\New folder\project-eks-microservice\terraform"
terraform init
terraform plan
terraform apply
```

Cap kubeconfig:

```powershell
aws eks update-kubeconfig --region $env:AWS_REGION --name $env:CLUSTER_NAME
kubectl cluster-info
kubectl get nodes
```

## B2 - Deploy core services

### MySQL

```powershell
cd "D:\New folder\project-eks-microservice\mysql"
kubectl apply -f mysql.yaml
```

### Redis

```powershell
cd "D:\New folder\project-eks-microservice\redis"
kubectl apply -f redis.yaml
```

### Kafka + Zookeeper

Lua chon A (khuyen nghi): chay script bang Git Bash/WSL

```bash
cd "/d/New folder/project-eks-microservice/kafka"
bash deploy_kafka.sh
```

Lua chon B (thu cong):

```powershell
cd "D:\New folder\project-eks-microservice\kafka"
helm dependency update .\kafka
helm upgrade --install kafka .\kafka -f .\kafka-values.yaml --namespace default --create-namespace
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=zookeeper --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka --timeout=300s
```

Kiem tra nhanh:

```powershell
kubectl get pods
kubectl get svc
kubectl get pvc
```

## B3 - (Tuy chon) Deploy Vault

```bash
cd "/d/New folder/project-eks-microservice/vault"
bash deploy_vault.sh
```

Neu can init thu cong:

```bash
kubectl exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > cluster-keys.json
VAULT_UNSEAL_KEY=$(jq -r ".unseal_keys_b64[]" cluster-keys.json)
kubectl exec vault-0 -- vault operator unseal "$VAULT_UNSEAL_KEY"
CLUSTER_ROOT_TOKEN=$(jq -r ".root_token" cluster-keys.json)
kubectl exec vault-0 -- vault login "$CLUSTER_ROOT_TOKEN"
kubectl exec vault-0 -- vault secrets enable kv
```

## B4 - Deploy ung dung (chon 1 huong)

### Huong A: Stateful + ALB

1) Deploy app services:

```powershell
kubectl apply -f "D:\New folder\project-eks-microservice\stateful\services\"
```

1) Cai ALB controller chart local trong repo:

```powershell
kubectl apply -f "D:\New folder\project-eks-microservice\stateful\alb\aws-load-balancer-controller\crds\crds.yaml"
helm upgrade --install aws-load-balancer-controller `
  -n kube-system --create-namespace `
  "D:\New folder\project-eks-microservice\stateful\alb\aws-load-balancer-controller" `
  -f "D:\New folder\project-eks-microservice\stateful\alb\aws-load-balancer-controller\values.yaml"
```

1) Apply ingress:

```powershell
kubectl apply -f "D:\New folder\project-eks-microservice\stateful\alb\ing.yaml"
kubectl get ingress
```

### Huong B: Stateful + Istio

1) Deploy app services:

```powershell
kubectl apply -f "D:\New folder\project-eks-microservice\stateful\services\"
```

1) Cai Istio:

```powershell
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
istioctl x precheck
helm install istio-base istio/base --namespace istio-system --create-namespace --version 1.18.2 --set profile=demo
helm install istiod istio/istiod --namespace istio-system --version 1.18.2 --wait --set profile=demo
helm install istio-ingress istio/gateway --namespace istio-ingress --create-namespace --version 1.18.2
```

1) Apply gateway + virtual services:

```powershell
kubectl apply -f "D:\New folder\project-eks-microservice\stateful\istio\gateway.yaml"
kubectl apply -f "D:\New folder\project-eks-microservice\stateful\istio\virtual-services.yaml"
![1774950277679](image/huongdan/1774950277679.png)
```

Luu y quan trong: theo README repo, truoc khi cai ingress gateway can mo SG cho TCP `15017` tu cluster SG sang node SG.

### Huong C: Knative + Istio

1) Cai Istio:

```powershell
istioctl install -y
```

1) Cai net-istio:

```powershell
kubectl apply -f https://github.com/knative/net-istio/releases/download/knative-v1.18.0/net-istio.yaml
```

1) Cai Knative operator:

```powershell
helm repo add knative-operator https://knative.github.io/operator
helm install knative-operator --create-namespace --namespace knative-operator knative-operator/knative-operator
```

1) Apply namespace va services Knative:

```powershell
kubectl apply -f "D:\New folder\project-eks-microservice\knative\namespace.yaml"
kubectl apply -f "D:\New folder\project-eks-microservice\knative\services\"
kubectl get ksvc
kubectl get domainmappings
```

## 5) Kiem tra sau deploy

```powershell
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
kubectl get events -A --sort-by=.metadata.creationTimestamp
```

Neu co loi pod:

```powershell
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

## 6) Cac van de thuong gap trong repo nay

- Khong co script tong `deploy_all.sh` o root, nen can deploy theo thu tu thu cong.
- `stateful/README.md` nhac toi `serivces/deploy_services.sh` (sai chinh ta + script khong ton tai trong repo hien tai).
- `stateful/alb/README.md` nhac toi `setup-alb-controller.sh` nhung repo hien tai khong co file nay.
- `knative/uninstall_knative.sh` co path tham chieu de gay nham lan (khong anh huong luong deploy neu ban theo huong dan tren).
- `vault/deploy_vault.sh` tao file `minikube-cluster-keys.json`, trong khi README hay dung `cluster-keys.json`.

## 7) Goi y "golden path" de chay nhanh

Neu muc tieu la chay nhanh va on dinh de test:

1. Terraform  
2. MySQL + Redis + Kafka  
3. Stateful services  
4. ALB controller + `stateful/alb/ing.yaml`  

Day la luong it buoc hon so voi Knative, de debug networking hon.

## 8) Deploy tu dong

Repo co 2 script dieu phoi deploy tu dong:

- `deploy_all.ps1` (Windows/PowerShell)
- `deploy_all.sh` (Linux / WSL / macOS)

### 8.1 Windows (PowerShell) – `deploy_all.ps1`

Vi du chay mode **Stateful + ALB** (day du tu Terraform -> core -> apps):

```powershell
cd "D:\New folder\project-eks-microservice"
.\deploy_all.ps1 -Mode stateful-alb -RunTerraform -AutoApproveTerraform
```

Vi du mode **Stateful + Istio** (bo qua core, chi deploy apps + routing):

```powershell
cd "D:\New folder\project-eks-microservice"
.\deploy_all.ps1 -Mode stateful-istio -SkipCore
```

Vi du mode **Knative + Istio**:

```powershell
cd "D:\New folder\project-eks-microservice"
.\deploy_all.ps1 -Mode knative-istio -SkipCore
```

Luu y: Kafka/Vault trong repo la script `bash`, nen may cua ban can co `bash` (Git Bash/WSL). Tong qua script se tu dong goi den `kafka/deploy_kafka.sh` va `vault/deploy_vault.sh` neu ban bat `-RunVault`.

### 8.2 Linux / WSL – `deploy_all.sh`

Trong Linux/WSL:

```bash
cd "/mnt/d/New folder/project-eks-microservice"   # hoac duong dan tuong ung tren Linux
chmod +x deploy_all.sh

# Chay full Terraform + core services + Stateful + ALB (mac dinh)
MODE=stateful-alb RUN_TERRAFORM=true ./deploy_all.sh

# Chi deploy apps + Istio (bo qua Terraform + core)
MODE=stateful-istio RUN_TERRAFORM=false ./deploy_all.sh

# Knative + Istio (chi apps)
MODE=knative-istio RUN_TERRAFORM=false ./deploy_all.sh
```

Bien moi truong `AWS_REGION` va `CLUSTER_NAME` mac dinh lan luot la `us-east-1` va `phuceks`; neu can, ban co the override:

```bash
AWS_REGION=ap-southeast-1 CLUSTER_NAME=my-eks MODE=stateful-alb ./deploy_all.sh
```
