variable "kube_context" {
  type        = string
  default     = "kind-demo"
  description = "kubeconfig-Kontext des kind-Clusters."
}

variable "namespace" {
  type        = string
  default     = "demo"
  description = "Namespace fuer den Beispiel-Workload."
}

variable "replicas" {
  type        = number
  default     = 3
  description = "Startanzahl der Pods. Der HPA skaliert davon ausgehend."

  validation {
    condition     = var.replicas >= 2
    error_message = "Mindestens 2 - sonst greift das PodDisruptionBudget nicht."
  }
}

variable "app_image" {
  type        = string
  default     = "nginxinc/nginx-unprivileged:1.27-alpine"
  description = "Image des Beispiel-Workloads. Laeuft bewusst als Non-Root."
}
