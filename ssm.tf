# Pull in the AWS-provided RunShellScript SSM doc
data "aws_ssm_document" "launch-tutor-doc" {
  name            = "AWS-RunShellScript"
  document_format = "YAML"
}

# Set up an SSM State Manager association for the app server, so the RunShellScript doc will run against all app servers
resource "aws_ssm_association" "launch-tutor-task" {
  depends_on = [aws_spot_instance_request.edx-spot-instance, aws_ec2_tag.edx-server-tagging]
  name       = data.aws_ssm_document.launch-tutor-doc.name

  targets {
    key    = "tag:Project"
    values = ["Open-edX"]
  }

  parameters = {
    "commands"         = file("./install-and-start-edx.sh"),
    "workingDirectory" = "/home/ec2-user",
    "executionTimeout" = "1800"
  }

  wait_for_success_timeout_seconds = 1800

}