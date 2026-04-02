# Redis Cache for Microservices

## 🚦 Deployment Flow

**Deploy Redis after infrastructure is ready!**

1. Ensure EKS cluster is ready (see [terraform/README.md](../terraform/README.md))
2. Deploy Redis:
   ```bash
   kubectl apply -f redis.yaml
   ```
3. Deploy other core services: [Kafka](../kafka/README.md), [MySQL](../mysql/README.md)
4. Deploy application layer:
   - [Traditional Kubernetes (Stateful)](../stateful/README.md)
   - [Knative + Istio](../knative/README.md)

## 🔧 Configuration
- **Storage:** 1Gi (gp3)
- **Port:** 6379

## 📚 Related Documentation
- [Terraform README](../terraform/README.md)
- [Kafka README](../kafka/README.md)
- [MySQL README](../mysql/README.md)
- [Knative README](../knative/README.md)
- [Stateful README](../stateful/README.md) 