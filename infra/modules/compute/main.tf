data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_region" "current" {}

resource "aws_instance" "bastione" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  iam_instance_profile        = var.iam_instance_profile_name
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              # Update and install required packages
              dnf update -y
              dnf install -y git curl tar gzip jq

              # Install kubectl
              KUBECTL_VERSION="$(curl -L -s https://dl.k8s.io/release/stable.txt)"
              curl -LO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
              chmod +x ./kubectl
              mv ./kubectl /usr/local/bin/kubectl

              # Install Helm 3
              curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

              # Clone repo directly as ec2-user so ownership and permissions are correct
              su - ec2-user -c "git clone https://github.com/Abdelhamid108/AtosGraduationProject.git /home/ec2-user/AtosGraduationProject || true"
              chown -R ec2-user:ec2-user /home/ec2-user/AtosGraduationProject
              chmod -R u+rwX /home/ec2-user/AtosGraduationProject

              # Prevent git 'dubious ownership' errors
              su - ec2-user -c "git config --global --add safe.directory /home/ec2-user/AtosGraduationProject"

              # Pre-configure EKS kubeconfig for ec2-user
              su - ec2-user -c "aws eks update-kubeconfig --name ${var.cluster_name} --region ${data.aws_region.current.name} || true"

              # Bash aliases & auto-completion for kubectl
              for RC in /home/ec2-user/.bashrc /root/.bashrc; do
                echo "alias k=kubectl" >> "$RC"
                echo "source <(kubectl completion bash)" >> "$RC"
                echo "complete -o default -F __start_kubectl k" >> "$RC"
              done
              chown ec2-user:ec2-user /home/ec2-user/.bashrc
              EOF

  tags = {
    Name      = "${var.cluster_name}-bastion"
    Terraform = "true"
  }
}
