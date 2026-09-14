# ---------------------------------------------------------------------------
# Lokale Uebungsumgebung: derselbe Terraform-Workflow wie in Azure,
# nur gegen einen kind-Cluster in Docker. Kosten: keine.
#
# Was hier geuebt wird und 1:1 auf AKS uebertragbar ist:
#   - Terraform steuert Kubernetes-Objekte deklarativ
#   - Requests/Limits, Probes, PodDisruptionBudget, HPA
#   - nodeSelector auf gelabelte Knoten (wie die AKS-User-Pools)
#   - Helm-Releases aus Terraform heraus
# ---------------------------------------------------------------------------

terraform {
  required_version = "~> 1.9"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
  # Lokaler State genuegt: die Umgebung ist wegwerfbar.
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kube_context
  }
}

# --- Metrics Server: Voraussetzung fuer den HPA -----------------------------
# In AKS ist er vorinstalliert, in kind nicht. Das Flag --kubelet-insecure-tls
# ist noetig, weil kind-Knoten selbstsignierte Kubelet-Zertifikate nutzen -
# in Produktion waere das ein Fehler, hier ist es korrekt.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
  namespace  = "kube-system"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}

# --- Ingress-Controller -----------------------------------------------------
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.3"
  namespace        = "ingress-nginx"
  create_namespace = true

  # kind: Controller auf den Control-Plane-Knoten, Ports sind dort gemappt.
  set {
    name  = "controller.service.type"
    value = "NodePort"
  }
  set {
    name  = "controller.hostPort.enabled"
    value = "true"
  }
  set {
    name  = "controller.nodeSelector.ingress-ready"
    value = "true"
  }
  set {
    name  = "controller.tolerations[0].key"
    value = "node-role.kubernetes.io/control-plane"
  }
  set {
    name  = "controller.tolerations[0].operator"
    value = "Exists"
  }
  set {
    name  = "controller.tolerations[0].effect"
    value = "NoSchedule"
  }
}

# --- Namespace --------------------------------------------------------------
resource "kubernetes_namespace" "demo" {
  metadata {
    name = var.namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
    }
  }
}

# --- Der Workload -----------------------------------------------------------
resource "kubernetes_deployment" "demo" {
  metadata {
    name      = "demo-app"
    namespace = kubernetes_namespace.demo.metadata[0].name
    labels    = { app = "demo-app" }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = { app = "demo-app" }
    }

    template {
      metadata {
        labels = { app = "demo-app" }
      }

      spec {
        # Wie in AKS: Workloads gehoeren auf den apps-Pool,
        # nicht auf den System-Knoten.
        node_selector = { workload = "apps" }

        security_context {
          run_as_non_root = true
          run_as_user     = 101
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        # Pods auf verschiedene Knoten verteilen.
        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = { app = "demo-app" }
          }
        }

        container {
          name  = "app"
          image = var.app_image

          port {
            name           = "http"
            container_port = 8080
          }

          # Ohne Requests kann der Scheduler nicht planen
          # und der HPA nicht rechnen.
          resources {
            requests = {
              cpu    = "25m"
              memory = "32Mi"
            }
            limits = {
              memory = "64Mi" # kein CPU-Limit: vermeidet Throttling
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 20
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "demo" {
  metadata {
    name      = "demo-app"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    selector = { app = "demo-app" }
    type     = "ClusterIP"

    port {
      port        = 80
      target_port = "http"
    }
  }
}

# --- Schutz beim Knoten-Drain ----------------------------------------------
resource "kubernetes_pod_disruption_budget_v1" "demo" {
  metadata {
    name      = "demo-app"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    min_available = 2
    selector {
      match_labels = { app = "demo-app" }
    }
  }
}

# --- Autoscaling ------------------------------------------------------------
resource "kubernetes_horizontal_pod_autoscaler_v2" "demo" {
  metadata {
    name      = "demo-app"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    min_replicas = var.replicas
    max_replicas = 10

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.demo.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }

  depends_on = [helm_release.metrics_server]
}

# --- Erreichbar machen ------------------------------------------------------
resource "kubernetes_ingress_v1" "demo" {
  metadata {
    name      = "demo-app"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.demo.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}
