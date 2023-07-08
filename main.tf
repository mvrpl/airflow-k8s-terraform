locals {
  name = "airflow_eks"
  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "ns_airflow" {
  metadata {
    name = "airflow-eks"
  }
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "kubernetes_persistent_volume_claim_v1" "airflow_dags_pvc" {
  provider = kubernetes
  metadata {
    name      = "airflow-eks-dags-pvc"
    namespace = kubernetes_namespace.ns_airflow.metadata.0.name
  }
  spec {
    access_modes = ["ReadWriteMany"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume" "airflow_dags_pv" {
  provider = kubernetes
  metadata {
    name = "airflow-eks-dags-pv"
  }
  spec {
    access_modes = ["ReadWriteMany"]
    capacity = {
      storage = "5Gi"
    }
    persistent_volume_reclaim_policy = "Retain"
    claim_ref {
      name      = kubernetes_persistent_volume_claim_v1.airflow_dags_pvc.metadata.0.name
      namespace = kubernetes_namespace.ns_airflow.metadata.0.name
    }
    persistent_volume_source {
      nfs {
        path   = "/dags"
        server = "-"
      }
    }
  }
}

resource "kubernetes_cron_job_v1" "airflow_dags_s3_sync" {
  provider = kubernetes
  metadata {
    name      = "airflow-eks-s3-sync"
    namespace = kubernetes_namespace.ns_airflow.metadata.0.name
  }
  spec {
    concurrency_policy            = "Replace"
    failed_jobs_history_limit     = 1
    schedule                      = "*/2 * * * *"
    timezone                      = "America/Sao_Paulo"
    starting_deadline_seconds     = 1
    successful_jobs_history_limit = 1
    job_template {
      metadata {}
      spec {
        backoff_limit = 2
        template {
          metadata {}
          spec {
            volume {
              name = kubernetes_persistent_volume.airflow_dags_pv.metadata.0.name
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.airflow_dags_pvc.metadata.0.name
              }
            }
            container {
              name  = "aws-cli"
              image = "amazon/aws-cli:latest"
              env {
                name  = "AWS_REGION"
                value = "sa-east-1"
              }
              env {
                name  = "AWS_ACCESS_KEY_ID"
                value = "ACCESS_AQUI"
              }
              env {
                name  = "AWS_SECRET_ACCESS_KEY"
                value = "SECRET_AQUI"
              }
              image_pull_policy = "IfNotPresent"
              command           = ["aws"]
              args              = ["s3", "sync", "s3://airflow-eks-dags/", "/dags/", "--no-progress", "--delete"]
              volume_mount {
                name       = kubernetes_persistent_volume.airflow_dags_pv.metadata.0.name
                mount_path = "/dags"
              }
            }
            restart_policy = "OnFailure"
          }
        }
      }
    }
  }
}

resource "helm_release" "airflow_eks" {
  name             = "airflow-eks"
  namespace        = kubernetes_namespace.ns_airflow.metadata.0.name
  create_namespace = true

  repository = "https://airflow-helm.github.io/charts"
  chart      = "airflow"
  version    = "8.7.1"

  values = [
    "${file("values-airflow.yaml")}"
  ]

  set {
    name  = "airflow.users[0].username"
    value = "mlima"
    type  = "string"
  }

  set {
    name  = "airflow.users[0].password"
    value = "#Ak8s789140"
    type  = "string"
  }
}
