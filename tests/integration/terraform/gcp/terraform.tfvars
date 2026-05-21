# Copyright IBM Corp. 2026

# Values are supplied via environment variables using the TF_VAR_* convention,
# or via the Makefile -var= flags (which read from the .env file at the repo root).
# Variables not set here must be supplied externally (variables.tf currently has no defaults).
#
# Required environment variables (set in .env or export before running make):
#
#   GCP_PROJECT_ID              -> project_id          (default: none)
#   GCP_REGION                  -> region              (default: none)
#   GCP_ZONE                    -> zone                (default: none)
#   GKE_CLUSTER_NAME            -> cluster_name        (default: none)
#   GKE_NODE_COUNT              -> node_count          (default: none)
#
# To override on the command line without changing .env:
#   terraform apply -var="cluster_name=my-gke-cluster" -var="region=us-central1"