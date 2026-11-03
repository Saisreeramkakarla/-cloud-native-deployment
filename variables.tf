variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  type = string
}

variable "my_ip" {
  type = string
}

variable "notification_email" {
  type    = string
  default = ""
}