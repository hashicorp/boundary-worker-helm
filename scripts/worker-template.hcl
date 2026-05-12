# Copyright IBM Corp. 2026

disable_mlock = true

listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
}

listener "tcp" {
  address     = "0.0.0.0:9203"
  purpose     = "ops"
  tls_disable = true
}

worker {
  auth_storage_path = "/var/lib/boundary"
  recording_storage_path = "/boundary/recording"
  tags {
    type = ["worker", "egress"]
  }
  
  # REQUIRED: Set your controller-generated activation token
  # controller_generated_activation_token = "your-activation-token-here"
}

# REQUIRED: Set your HCP Boundary cluster ID or use initial_upstreams for self-managed
# hcp_boundary_cluster_id = "your-cluster-id-here"

events {
  audit_enabled       = true
  sysevents_enabled   = true
  observations_enable = true
  sink "stderr" {
    name = "all-events"
    description = "All events sent to stderr"
    event_types = ["*"]
    format = "cloudevents-json"
  }
}