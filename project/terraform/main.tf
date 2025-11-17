terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ---------------------------------------------------------
# VPC + Subnet
# ---------------------------------------------------------
resource "google_compute_network" "vpc" {
  name = "php-vpc"
}

resource "google_compute_subnetwork" "subnet" {
  name          = "php-subnet"
  region        = var.region
  ip_cidr_range = "10.0.0.0/24"
  network       = google_compute_network.vpc.id
}

# ---------------------------------------------------------
# Firewall Rules
# ---------------------------------------------------------
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["php-server"]
}

resource "google_compute_firewall" "allow_gcp_healthchecks" {
  name    = "allow-healthchecks"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]

  target_tags = ["php-server"]
}

# ---------------------------------------------------------
# Instance Template (COS + Docker)
# ---------------------------------------------------------
resource "google_compute_instance_template" "php_template" {
  name         = "php-instance-template"
  machine_type = "e2-medium"
  tags         = ["php-server"]

  disk {
    auto_delete  = true
    boot         = true
    source_image = "projects/cos-cloud/global/images/family/cos-stable"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {}   # EXTERNAL IP ENABLED
  }

  metadata = {
    # IMPORTANT: Dynamic image tag from Jenkins
    "gce-container-declaration" = <<EOF
spec:
  containers:
  - name: php-app
    image: "us-central1-docker.pkg.dev/${var.project_id}/${var.repo}/${var.image_name}:${var.tag}"
    ports:
      - containerPort: 80
        hostPort: 80
  restartPolicy: Always
EOF
  }

  service_account {
    email  = "default"
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

# ---------------------------------------------------------
# Managed Instance Group
# ---------------------------------------------------------
resource "google_compute_region_instance_group_manager" "php_mig" {
  name               = "php-mig"
  region             = var.region
  base_instance_name = "php-instance"

  version {
    instance_template = google_compute_instance_template.php_template.self_link
  }

  target_size = 2

  auto_healing_policies {
    health_check      = google_compute_health_check.php_hc.id
    initial_delay_sec = 60
  }
}

# ---------------------------------------------------------
# Health Check
# ---------------------------------------------------------
resource "google_compute_health_check" "php_hc" {
  name = "php-health-check"

  http_health_check {
    port         = 80
    request_path = "/"
  }

  timeout_sec        = 5
  check_interval_sec = 5
}

# ---------------------------------------------------------
# Backend Service
# ---------------------------------------------------------
resource "google_compute_backend_service" "php_backend" {
  name        = "php-backend-service"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30

  health_checks = [google_compute_health_check.php_hc.id]

  backend {
    group           = google_compute_region_instance_group_manager.php_mig.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
  }
}

# ---------------------------------------------------------
# HTTP Load Balancer
# ---------------------------------------------------------
resource "google_compute_global_address" "php_lb_ip" {
  name = "php-lb-ip"
}

resource "google_compute_url_map" "php_urlmap" {
  name            = "php-urlmap"
  default_service = google_compute_backend_service.php_backend.id
}

resource "google_compute_target_http_proxy" "php_proxy" {
  name    = "php-http-proxy"
  url_map = google_compute_url_map.php_urlmap.id
}

resource "google_compute_global_forwarding_rule" "php_forward_rule" {
  name        = "php-forwarding-rule"
  target      = google_compute_target_http_proxy.php_proxy.id
  port_range  = "80"
  ip_protocol = "TCP"
  ip_address  = google_compute_global_address.php_lb_ip.address
}

# ---------------------------------------------------------
# Output
# ---------------------------------------------------------
output "load_balancer_ip" {
  value       = google_compute_global_forwarding_rule.php_forward_rule.ip_address
  description = "Access the PHP application using this IP"
}
