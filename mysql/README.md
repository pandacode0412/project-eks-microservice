# MySQL Database for Microservices

## 🚦 Deployment Flow

**Deploy MySQL after infrastructure is ready!**

1. Ensure EKS cluster is ready (see [terraform/README.md](../terraform/README.md))
2. Deploy MySQL:
   ```bash
   kubectl apply -f mysql.yaml
   ```
3. Deploy other core services: [Kafka](../kafka/README.md), [Redis](../redis/README.md)
4. Deploy application layer:
   - [Traditional Kubernetes (Stateful)](../stateful/README.md)
   - [Knative + Istio](../knative/README.md)

## 🔧 Configuration
- **Root password:** `root`
- **Database:** `javatechie`
- **Storage:** 1Gi (gp3)
- **Port:** 3306

## 📚 Related Documentation
- [Terraform README](../terraform/README.md)
- [Kafka README](../kafka/README.md)
- [Redis README](../redis/README.md)
- [Knative README](../knative/README.md)
- [Stateful README](../stateful/README.md) 