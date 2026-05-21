# Copyright IBM Corp. 2026

output "cluster_name" {
  value = google_container_cluster.primary.name
}