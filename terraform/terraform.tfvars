# Default values — mirror the .env file at the repo root.
# Override on the command line: terraform apply -var="cluster_name=my-cluster"
# or create a terraform.tfvars.local and add it to .gitignore.

aws_region         = "ap-south-1"
cluster_name       = "boundary-k8s-cluster-1"
k8s_version        = "1.31"
node_type          = "t3.medium"
node_desired       = 2
node_min           = 1
node_max           = 3
availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
lbc_chart_version  = "1.8.1"
