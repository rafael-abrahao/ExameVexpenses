provider "aws" {
  region = "us-east-1"
}

variable "projeto" {
  description = "Nome do projeto"
  type        = string
  default     = "VExpenses"
}

variable "candidato" {
  description = "Nome do candidato"
  type        = string
  default     = "SeuNome"
}

resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"     //Algorítimo de criptografia utilizado
  rsa_bits  = 2048
}

#Criando o recurso AWS apropriado para par de chaves, usando como base o recurso anterior
resource "aws_key_pair" "ec2_key_pair" {
  key_name   = "${var.projeto}-${var.candidato}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

#Criando a nuvem privada principal
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.projeto}-${var.candidato}-vpc"
  }
}

#Definindo a subnet principal da main_vpc
resource "aws_subnet" "main_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.projeto}-${var.candidato}-subnet"
  }
}

#Craindo um gateway para fazer a conexão da main_vpc com a Internet
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "${var.projeto}-${var.candidato}-igw"
  }
}

#Definindo a tabela de roteamento da main_vpc
resource "aws_route_table" "main_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  //Qualquer conexão será roteada para o main_igw
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-route_table"
  }
}

#Associando a main_route_table e a main_subnet
resource "aws_route_table_association" "main_association" {
  subnet_id      = aws_subnet.main_subnet.id
  route_table_id = aws_route_table.main_route_table.id

  tags = {
    Name = "${var.projeto}-${var.candidato}-route_table_association"
  }
}

resource "aws_security_group" "ssh_sg" {
  name        = "${var.projeto}-${var.candidato}-ssh-sg"
  description = "Permitir SSH somente de IPs especificos"
  vpc_id      = aws_vpc.main_vpc.id

  # Não permitir acesso indiscriminado
  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["192.168.0.1"] //Exemplo
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-ssh-sg"
  }
}

resource "aws_security_group" "http_sg" {
  name        = "${var.projeto}-${var.candidato}-http-sg"
  description = "Permitir HTTP de qualquer lugar"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-http-sg"
  }
}

resource "aws_security_group" "https_sg" {
  name        = "${var.projeto}-${var.candidato}-https-sg"
  description = "Permitir HTTP de qualquer lugar"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port        = 443
    to_port          = 443 
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-https-sg"
  }
}

resource "aws_flow_log" "example" {
  iam_role_arn    = "arn"
  log_destination = "log"
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main_vpc.id
}

# Acessando o id do ami, filtrando pelo tipo de imagem e virtualização
data "aws_ami" "debian12" {
  most_recent = true

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]              
  }

  owners = ["679593333241"]
}

# Por fim, instanciando a EC2
resource "aws_instance" "debian_ec2" {
  ami             = data.aws_ami.debian12.id            //id do ami
  instance_type   = "t2.micro"                          //tipo da instância
  subnet_id       = aws_subnet.main_subnet.id           //id da subnet
  key_name        = aws_key_pair.ec2_key_pair.key_name  //par de chaves
  security_groups = [aws_security_group.ssh_sg, aws_security_group.http_sg, aws_security_group.https_sg]   //lista dos grupos de segurança
  iam_instance_profile = "teste"

  monitoring = true
  ebs_optimized = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y &&
              sudo apt install -y nginx
              echo "Olá Mundo" > /var/www/html/index.html
              EOF

  tags = {
    Name = "${var.projeto}-${var.candidato}-ec2"
  }
}

output "private_key" {
  description = "Chave privada para acessar a instância EC2"
  value       = tls_private_key.ec2_key.private_key_pem
  sensitive   = true
}

output "ec2_public_ip" {
  description = "Endereço IP público da instância EC2"
  value       = aws_instance.debian_ec2.public_ip
}
