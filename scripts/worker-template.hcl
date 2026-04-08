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
    type = ["worker", "egress", "test"]
  }
  
  controller_generated_activation_token = "<activation-token>"
}

hcp_boundary_cluster_id = "<cluster-id>"

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