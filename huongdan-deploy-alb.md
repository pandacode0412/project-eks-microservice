# Huong dan trien khai AWS Load Balancer Controller + Ingress ALB (Stateful)

Tai lieu nay huong dan **tu dau den cuoi** cach cai **AWS Load Balancer Controller** tren EKS va expose ung dung trong `stateful/services/` bang **Ingress ALB**, dung dung file trong repo:

- Chart: `stateful/alb/aws-load-balancer-controller/`
- Values: `stateful/alb/aws-load-balancer-controller/values.yaml`
- Ingress mau: `stateful/alb/ing.yaml`

Neu ban gap loi kieu:

- `no endpoints available for service "aws-load-balancer-webhook-service"`
- `failed calling webhook "vingress.elbv2.k8s.aws"`

phan **Muc 9 – Troubleshooting** o duoi se giai thich cach xu ly.

---

## 0. Dieu kien

1. Cluster **EKS** da chay, `kubectl` ket noi duoc:

   ```bash
   aws eks update-kubeconfig --region <REGION> --name <CLUSTER_NAME>
   kubectl cluster-info
   ```

2. Cong cu: `aws` CLI (2.x), `kubectl`, `helm` (3.x).

3. Quyen IAM duoc tao policy/role va (neu can) OIDC provider cho EKS.

4. Biet **region** va **ten cluster** (repo mac dinh: `us-east-1`, `phuceks`).

---

## 1. Dat bien moi truong (tranh loi endpoint rong)

Moi lan mo shell moi, nen dat lai:

```bash
export AWS_REGION="us-east-1"
export CLUSTER_NAME="phuceks"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "REGION=$AWS_REGION CLUSTER=$CLUSTER_NAME ACCOUNT=$ACCOUNT_ID"
```

Neu `$AWS_REGION` de trong, lenh `aws eks ...` se bao loi kieu `Invalid endpoint: https://eks..amazonaws.com`.

---

## 2. Bat / kiem tra OIDC cho EKS (IRSA)

Controller can **IAM Role gan vao ServiceAccount** (IRSA). Cluster phai co **OIDC identity provider** tren IAM.

### Cach A – Co `eksctl` (nhanh)

```bash
eksctl utils associate-iam-oidc-provider \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --approve
```

### Cach B – Khong co `eksctl`

1. Lay issuer URL:

   ```bash
   aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
     --query "cluster.identity.oidc.issuer" --output text
   ```

2. Neu chua associate OIDC provider, lam theo [AWS: Enabling IAM roles for service accounts](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html) (Console: EKS cluster → **Details** → **OIDC provider** → Associate), hoac cai `eksctl` chi cho buoc nay.

---

## 3. Tao IAM Policy cho AWS Load Balancer Controller

```bash
curl -sS -o iam-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json \
  --query Policy.Arn --output text
```

- Neu policy **da ton tai**, lay ARN:

  ```bash
  export POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
  aws iam get-policy --policy-arn "$POLICY_ARN" --query Policy.Arn --output text
  ```

**Luu y:** `POLICY_ARN` phai co dung **Account ID** (`arn:aws:iam::123456789012:policy/...`). Neu `ACCOUNT_ID` trong, lenh `attach-role-policy` se that bai.

---

## 4. Tao IAM Role (IRSA) + trust policy

ServiceAccount ma chart tao (release `aws-load-balancer-controller`, namespace `kube-system`) thuong co ten **`aws-load-balancer-controller`**. Trust policy phai khop:

`system:serviceaccount:kube-system:aws-load-balancer-controller`

```bash
ISSUER_URL=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query "cluster.identity.oidc.issuer" --output text)
OIDC_PROVIDER=$(echo "$ISSUER_URL" | sed 's|^https://||')

cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name aws-load-balancer-controller-Role \
  --assume-role-policy-document file://trust-policy.json

export POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"

aws iam attach-role-policy \
  --role-name aws-load-balancer-controller-Role \
  --policy-arn "$POLICY_ARN"
```

Ghi nhận ARN role:

```text
arn:aws:iam::<ACCOUNT_ID>:role/aws-load-balancer-controller-Role
```

---

## 5. Chinh `values.yaml` cho dung account / cluster

Mo file: `stateful/alb/aws-load-balancer-controller/values.yaml`

1. **`serviceAccount.annotations.eks.amazonaws.com/role-arn`**  
   Dat dung ARN role o buoc 4 (khong copy account cua nguoi khac).

2. **`clusterName`**  
   Dat dung ten cluster EKS that (ví dụ `phuceks`).

3. (Tuy chon) **`region`**  
   Neu co van de VPC/region, co the set `region: us-east-1` trong values (dong `region:` trong file).

---

## 6. Cai CRDs + Helm chart

Tu thu muc goc repo (`project-eks-microservice`):

```bash
kubectl apply -f stateful/alb/aws-load-balancer-controller/crds/crds.yaml

helm upgrade --install aws-load-balancer-controller \
  -n kube-system --create-namespace \
  stateful/alb/aws-load-balancer-controller \
  -f stateful/alb/aws-load-balancer-controller/values.yaml
```

---

## 7. Kiem tra controller va **webhook** (quan trong)

Khi apply Ingress, API server goi **webhook** qua Service `aws-load-balancer-webhook-service` trong `kube-system`. Neu Service **khong co Endpoints** (khong pod Ready), se loi:

`no endpoints available for service "aws-load-balancer-webhook-service"`

Chay:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get svc -n kube-system aws-load-balancer-webhook-service
kubectl get endpoints -n kube-system aws-load-balancer-webhook-service
```

- Pod phai **Running** va **READY** (1/1 hoac 2/2).
- `endpoints` phai co **it nhat mot IP:port** (khong phai `<none>`).

Neu pod **CrashLoop** / **ImagePullBackOff**:

```bash
kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=100
kubectl describe pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

Nguyen nhan thuong gap: **IRSA sai** (role ARN sai, trust policy sai, policy chua attach), **clusterName** sai, thieu quyen AWS.

**Chi apply Ingress sau khi controller Ready va webhook co endpoints.**

---

## 8. Deploy ung dung Stateful + Ingress

1. Deploy core (neu chua co): MySQL, Redis, Kafka theo `mysql/`, `redis/`, `kafka/` (hoac `deploy_all.sh`).

2. Deploy microservice:

   ```bash
   kubectl apply -f stateful/services/
   ```

3. Apply Ingress:

   ```bash
   kubectl apply -f stateful/alb/ing.yaml
   kubectl get ingress stateful-ingress
   ```

Khi on, cot **ADDRESS** se hien DNS name cua ALB.

Ingress trong repo dung host:

- `test.onefirefly.click` → `frontend-service:80`
- `api.onefirefly.click` → `api-gateway:8080`, `/ws` → `notification-service:8083`

Annotation `target-type: ip` phu hop VPC CNI (pod IP). Neu cluster khong dung IP target, xem lai AWS doc ve `instance` vs `ip`.

---

## 9. DNS

Tao ban ghi CNAME (hoac ALIAS) tro:

- `test.onefirefly.click` → `ADDRESS` tu `kubectl get ingress`
- `api.onefirefly.click` → cung `ADDRESS`

Neu dung Cloudflare: bat dau co the dat SSL **Flexible** neu backend chi HTTP, tranh 525 khi chua co TLS tren ALB.

---

## 10. Troubleshooting nhanh

| Hien tuong | Huong xu ly |
| --- | --- |
| `no endpoints` cho webhook | Doi pod controller Ready; xem log + IRSA + clusterName. |
| Ingress khong co ADDRESS | `kubectl describe ingress stateful-ingress`; log controller AWS API errors. |
| 503 / target unhealthy | `kubectl get endpoints frontend-service api-gateway notification-service`; kiem tra pod + port. |
| Policy ARN sai / empty account | `export ACCOUNT_ID=...` va tao lai `POLICY_ARN` day du. |

### Goi y go Ingress neu ket webhook (chi khi biet minh lam gi)

Chi dung khi can debug tam; khong khuyen nghi lau dai:

- Tim `ValidatingWebhookConfiguration` lien quan `elbv2.k8s.aws` va hieu rang xoa se **tat validation** Ingress ALB.

---

## 11. Goi y thu muc lien quan

- Huong dan chi tiet them: `stateful/alb/readme-alb.md`
- Go Ingress mau: `stateful/alb/ing.yaml`
- Gỡ: `stateful/alb/uninstall_alb.sh` (neu co trong repo)

---

## 12. Luu y bao mat

- File `iam-policy.json`, `trust-policy.json` co the chua thong tin nhay cam ve cau truc account – khong commit len git neu khong can.

Sau khi on dinh, ban co the xoa file tam tren may:

```bash
rm -f iam-policy.json trust-policy.json
```

---

## 13. Xoa resource (don dep)

Lam tu **ngoai vao trong**: Ingress → (ALB AWS tu dong xoa khi khong con Ingress dung no) → tuy chon gỡ controller → tuy chon gỡ app / IAM.

### 13.1. Xoa Ingress Stateful (va ALB lien quan)

Ingress la `stateful-ingress` trong `stateful/alb/ing.yaml`. Xoa Ingress truoc de AWS Load Balancer Controller **huy ALB** tren AWS (co the mat vai phut).

Tu thu muc goc repo:

```bash
kubectl delete -f stateful/alb/ing.yaml
```

Hoac:

```bash
kubectl delete ingress stateful-ingress
```

Kiem tra:

```bash
kubectl get ingress
```

Tren AWS Console (EC2 → Load Balancers): ALB map voi Ingress do se bien mat sau khi controller reconcile xong.

### 13.2. (Tuy chon) Xoa cac service app trong `stateful/services`

Neu muon go luon microservice (frontend, api-gateway, …):

```bash
kubectl delete -R -f stateful/services/
```

Hoac xoa tung thu muc neu ban muon giu lai mot phan. Luu y: lenh delete co the fail neu resource phu thuoc; khi do xoa theo thu tu (Deployment truoc, Service sau) hoac dung `kubectl delete -k` neu ban co kustomize.

### 13.3. (Tuy chon) Gỡ AWS Load Balancer Controller (Helm)

Sau khi **khong con Ingress nao** dung class `alb` (hoac ban chap nhan mat quan ly ALB con lai — tot nhat la xoa het Ingress ALB truoc):

```bash
helm uninstall aws-load-balancer-controller -n kube-system
```

Kiem tra:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get svc -n kube-system | grep -i load-balancer
```

### 13.4. (Tuy chon) Xoa CRDs cua controller

**Can than:** xoa CRDs se anh huong moi tai nguyen dung `TargetGroupBinding`, `IngressClassParams`, … tren cluster. Chi lam khi ban **chac** khong con addon nao phu thuoc.

```bash
# Chi tham khao — doc ky truoc khi chay
# kubectl delete -f stateful/alb/aws-load-balancer-controller/crds/crds.yaml
```

Thong thuong: **gỡ Helm la du**, giu CRDs neu sau nay cai lai controller.

### 13.5. (Tuy chon) Gỡ IAM role + policy (tren AWS)

Chi khi ban **khong con** dung role nay cho cluster khac (hoac khong cai lai controller):

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"

aws iam detach-role-policy \
  --role-name aws-load-balancer-controller-Role \
  --policy-arn "$POLICY_ARN"

aws iam delete-role --role-name aws-load-balancer-controller-Role

# Policy AWSLoadBalancerControllerIAMPolicy: chi xoa neu khong account nao khac dung
# aws iam delete-policy --policy-arn "$POLICY_ARN"
```

**OIDC provider** của EKS: **thuong khong xoa** (cluster khac hoac IRSA khac van can).

### 13.6. Script co san trong repo

Trong `stateful/alb/uninstall_alb.sh` co lenh xoa `ing.yaml` va `../services/` — **chay trong thu muc `stateful/alb`** neu dung script:

```bash
cd stateful/alb
bash uninstall_alb.sh
```

Script **khong** gỡ Helm controller; neu can, lam them buoc 13.3.
