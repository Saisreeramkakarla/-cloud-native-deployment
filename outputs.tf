output "ec2_public_ip" {
  value = aws_instance.web_server.public_ip
}

output "ec2_instance_id" {
  value = aws_instance.web_server.id
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.app_logs.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}