output "namespace" {
  value = kubernetes_namespace.demo.metadata[0].name
}

output "app_url" {
  description = "Im Browser oeffnen, sobald die Pods laufen."
  value       = "http://localhost:8080"
}

output "check_command" {
  value = "kubectl get pods,svc,hpa,pdb,ingress -n ${kubernetes_namespace.demo.metadata[0].name}"
}
