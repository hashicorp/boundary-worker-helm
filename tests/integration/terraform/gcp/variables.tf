# Copyright IBM Corp. 2026

variable "project_id" {
  description = "GCP project ID where test resources will be created."
  type        = string
}
variable "region" {
  description = "GCP region used by the Google provider for test resources."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone where the GKE cluster and node pool are created."
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Name of the GKE cluster created for integration testing."
  type        = string
  default     = "demo-gke-cluster"
}

variable "node_count" {
  description = "Number of nodes in the primary GKE node pool."
  type        = number
  default     = 2
}
