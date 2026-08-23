resource "aws_security_group" "bastion_sg" {
  name        = "${var.cluster_name}-bastion-sg"
  description = "Security group for SSM Bastion Host"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic for updates and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.cluster_name}-bastion-sg"
    Terraform = "true"
  }
}
