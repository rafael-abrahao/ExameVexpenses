# Analisando main.tf

## Provedor
Definindo o provedor (Amazon Web Services) e a região na qual os recursos serão instanciados.
```terraform
provider "aws" {
  region = "us-east-1"
}
```

## Variáveis
Algumas variáveis que servirão para personalizar de forma automática as tags dos recursos.
```terraform
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
```

## Chaves 
Aqui será criado o par de chaves para conectar com a instancia EC2.<br><br>
Nesse primeiro bloco será utilizado um recurso interno do próprio terraform para criar as chaves.
```terraform
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"     //Algorítimo de criptografia utilizado
  rsa_bits  = 2048
}
```
Já nesse segundo bloco será criado o recurso próprio da AWS para utilizar as chaves criadas no bloco acima.
```terraform
resource "aws_key_pair" "ec2_key_pair" {
  key_name   = "${var.projeto}-${var.candidato}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}
```

## Nuvem Privada (VPC)

Criação de uma nuvem que funciona de forma isolada e privada.

```terraform
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.projeto}-${var.candidato}-vpc"
  }
}
```

### Subnet

Definição de uma subnet na main_vpc, o recurso de EC2 será criado nessa subnet.

```terraform
resource "aws_subnet" "main_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.projeto}-${var.candidato}-subnet"
  }
}
```
### Gateway

Criação de um gateway que vai permitir o acesso de uma subnet a internet. Subnets com acesso a internet são consideradas públicas enquanto as que se limitar a VPC são consideradas privadas.

```terraform
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "${var.projeto}-${var.candidato}-igw"
  }
}
```

### Tabela de roteamento

Definição de uma tabela de roteamento que contém as regras de roteamento da VPC. No caso abaixo todas as conexões (0.0.0.0/0) serão roteadas para o main_igw criado no bloco anterior.

```terraform
resource "aws_route_table" "main_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-route_table"
  }
}
```

### Associando a tabela main_route_table

Nesse bloco é feita a associação entre a main_route_table e a main_subnet, como consequência todas as conexões da main_subnet serão roteadas para o main_igw.

```terraform
resource "aws_route_table_association" "main_association" {
  subnet_id      = aws_subnet.main_subnet.id
  route_table_id = aws_route_table.main_route_table.id

  tags = {
    Name = "${var.projeto}-${var.candidato}-route_table_association"
  }
}
```

## Security Group

Grupo de segurança que define as regras de acesso da main_vpc, nesse caso qualquer um pode fazer conexão de SSH(terminal remoto) e qualquer conexão de saída pode ser feita independete da origem ou procólo.

```terraform
resource "aws_security_group" "main_sg" {
  name        = "${var.projeto}-${var.candidato}-sg"
  description = "Permitir SSH de qualquer lugar e todo o tráfego de saída"
  vpc_id      = aws_vpc.main_vpc.id

  # Regras de entrada
  ingress {
    description      = "Allow SSH from anywhere"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # Regras de saída
  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-sg"
  }
}
```

## AMI id

Nesse bloco do tipo data, sera feito a recuperação do ID do ami que será usado na criação do EC2. A recuperação é feita através de filtros que filtram pelo tipo de imagem e virtualização.

```terraform
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
```

## Criação do EC2

Por fim, o EC2(Elastic Compute Cloud) é instanciado.

```terraform
resource "aws_instance" "debian_ec2" {
  ami             = data.aws_ami.debian12.id            //id do ami
  instance_type   = "t2.micro"                          //tipo da instância
  subnet_id       = aws_subnet.main_subnet.id           //id da subnet
  key_name        = aws_key_pair.ec2_key_pair.key_name  //par de chaves
  security_groups = [aws_security_group.main_sg.name]   //lista dos grupos de segurança

  associate_public_ip_address = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }

  user_data = <<-EOF                      //definindo comandos para serem executados
              #!/bin/bash                 //automaticamente na instanciação
              apt-get update -y
              apt-get upgrade -y
              EOF

  tags = {
    Name = "${var.projeto}-${var.candidato}-ec2"
  }
}
```
## Output

Aqui os dados que serão produzidos como output para uso posterior, no caso a chave privada de acesso e o ip público do EC2.

```terraform
output "private_key" {
  description = "Chave privada para acessar a instância EC2"
  value       = tls_private_key.ec2_key.private_key_pem
  sensitive   = true
}

output "ec2_public_ip" {
  description = "Endereço IP público da instância EC2"
  value       = aws_instance.debian_ec2.public_ip
}
```