packer {
  required_plugins {
    azure = {
      version = ">= 1.4.0"
      source  = "github.com/hashicorp/azure"
    }
  }
}

variable "subscription_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "client_id" {
  type = string
}

variable "client_secret" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "vm_size" {
  type    = string
  default = "Standard_L8s_v3"
}

variable "use_azure_cli_auth" {
  type    = bool
  default = false
}

variable "allowed_inbound_ip_addresses" {
  type = list(string)
}

variable "image_offer" {
  type = string
}

variable "image_publisher" {
  type = string
}

variable "image_sku" {
  type = string
}

variable "image_version" {
  type = string
}

variable "daos_image_gallery_name" {
  type = string
}

variable "daos_image_gallery_location" {
  type = string
}

variable "daos_image_publisher" {
  type    = string
  default = "daos"
}

variable "daos_image_name" {
  type = string
}

variable "daos_image_version_prefix" {
  type = string
}

variable "daos_git_repo_url" {
  default = "https://github.com/daos-stack/daos.git"
  type    = string
}

variable "daos_git_repo_branch" {
  default = "master"
  type    = string
}

variable "daos_git_repo_tag" {
  default = ""
  type    = string
}

variable "daos_utils_script" {
  default = "utils/scripts/install-el8.sh"
  type    = string
}

variable "daos_apply_patches" {
  default = false
  type    = bool
}

variable "daos_patch_files_dir" {
  default = "/tmp/daos_patches"
  type    = string
}

variable "daos_config_files_dir" {
  default = "/tmp/daos_config"
  type    = string
}

variable "daos_prefix_path" {
  default = "/opt/daos"
  type    = string
}

variable "daos_server_service_user" {
  default = "root"
  type    = string
}

variable "daos_server_service_group" {
  default = "root"
  type    = string
}

variable "daos_python_version" {
  default = "3.11"
  type    = string
}

variable "ansible_playbook" {
  type    = string
  default = "install_daos_from_source.yml"
}

variable "nr_hugepages" {
  type    = number
  default = 8096
}

locals {
  managed_image_version = "${var.daos_image_version_prefix}.${formatdate("YYYYMMDD", timestamp())}"
  scripts_path          = "${path.root}/scripts"
  patches_path          = "${path.root}/daos_patches"
  config_files_path     = "${path.root}/daos_config"
}

source "azure-arm" "daos" {
  subscription_id           = var.subscription_id
  build_resource_group_name = var.resource_group_name

  client_id     = var.client_id
  client_secret = var.client_secret
  tenant_id     = var.tenant_id

  vm_size            = var.vm_size
  os_type            = "Linux"
  communicator       = "ssh"
  ssh_pty            = "true"
  use_azure_cli_auth = var.use_azure_cli_auth

  allowed_inbound_ip_addresses = var.allowed_inbound_ip_addresses

  image_offer     = var.image_offer
  image_publisher = var.image_publisher
  image_sku       = var.image_sku
  image_version   = var.image_version

  plan_info {
    plan_name      = var.image_sku
    plan_product   = var.image_offer
    plan_publisher = var.image_publisher
  }

  shared_image_gallery_destination {
    subscription   = var.subscription_id
    resource_group = var.resource_group_name
    gallery_name   = var.daos_image_gallery_name
    image_name     = var.daos_image_name
    image_version  = local.managed_image_version
    replication_regions = [
      var.daos_image_gallery_location
    ]
    storage_account_type = "Standard_LRS"
  }

  managed_image_resource_group_name = var.resource_group_name
  managed_image_name                = var.daos_image_name
}

build {
  sources = ["source.azure-arm.daos"]

  provisioner "shell" {
    execute_command = "echo 'packer' | sudo -S env {{ .Vars }} {{ .Path }}"
    script          = "${local.scripts_path}/bootstrap.sh"
  }

  provisioner "ansible-local" {
    playbook_file   = "./ansible/install_azure_tools.yml"
    extra_arguments = ["-b"]
  }

  provisioner "file" {
    source      = "${local.patches_path}"
    destination = "/tmp/daos_patches"
  }

  provisioner "file" {
    source      = "${local.config_files_path}"
    destination = "/tmp/daos_config"
  }

  provisioner "ansible-local" {
    playbook_file   = "./ansible/tune.yml"
    galaxy_file     = "./ansible/requirements.yml"
    extra_arguments = ["-b"]
  }

  provisioner "ansible-local" {
    playbook_file = "./ansible/${var.ansible_playbook}"
    galaxy_file   = "./ansible/requirements.yml"
    extra_arguments = [
      "-b",
      "-e",
      "daos_git_repo_url=${var.daos_git_repo_url}",
      "-e",
      "daos_git_repo_branch=${var.daos_git_repo_branch}",
      "-e",
      "daos_git_repo_tag=${var.daos_git_repo_tag}",
      "-e",
      "daos_utils_script=${var.daos_utils_script}",
      "-e",
      "daos_apply_patches=${var.daos_apply_patches}",
      "-e",
      "nr_hugpages=${var.nr_hugepages}"
    ]
  }
}
