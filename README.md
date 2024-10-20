# Analisando main.tf

## Provedor
Inicialmente vamos definir o nosso provedor (Amazon Web Services) e a região na qual alocaremos nossos recursos.
```terraform
provider "aws" {
  region = "us-east-1"
}
```

## Variáveis
Criamos algumas variáveis que serviram para personalizar de forma automática as tags dos recursos que criaremos.
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
Aqui vamos criar nosso par de chaves para conectar com a instancia EC2.<br><br>
Nesse primeiro bloco usamos um recurso interno do próprio terraform para criar nossa chave
```terraform
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"     //Algorítimo de criptografia utilizado
  rsa_bits  = 2048
}
```
Já nesse segundo bloco nos criamos o recurso próprio da AWS para armazenar as chaves
```terraform
resource "aws_key_pair" "ec2_key_pair" {
  key_name   = "${var.projeto}-${var.candidato}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}
```