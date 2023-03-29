data "aws_iam_policy_document" "lambda_assume_role" {
    statement {
        effect = "Allow"
        principals {
            type = "Service"
            identifiers = ["lambda.amazonaws.com"]
        }
        actions = ["sts:AssumeRole"]
    }
}

resource "aws_iam_role" "lambda_iam_role" {
    name = "aws_nuke_lambda_role"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
    managed_policy_arns = [
        "arn:aws:iam::aws:policy/AdministratorAccess",
        aws_iam_policy.lambda_logging.arn
    ]
}

data "archive_file" "pyyaml" {
    type = "zip"
    source_dir = "dependencies/pyyaml"
    output_path = "pyyaml_layer.zip"
    excludes = [
        "dependencies/pyyaml/_yaml/__pycache__",
        "dependencies/pyyaml/yaml/__pycache__"
    ]
}

resource "aws_lambda_layer_version" "pyyaml" {
    filename = "pyyaml_layer.zip"
    layer_name = "pyyaml_layer"
    compatible_runtimes = ["python3.9"]
    compatible_architectures = ["arm64"]
    source_code_hash = data.archive_file.pyyaml.output_base64sha256
}

data "archive_file" "aws_nuke" {
    type = "zip"
    source_dir = "dependencies/aws-nuke"
    output_path = "aws_nuke_layer.zip"
}

resource "aws_lambda_layer_version" "aws_nuke" {
    filename = "aws_nuke_layer.zip"
    layer_name = "aws_nuke_layer"
    compatible_runtimes = ["python3.9"]
    compatible_architectures = ["arm64"]
    source_code_hash = data.archive_file.aws_nuke.output_base64sha256
}

data "archive_file" "lambda_function" {
    type = "zip"
    source_dir = "lambda_function"
    output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "aws_nuke_lambda" {
    function_name = "aws-nuke"
    role = aws_iam_role.lambda_iam_role.arn
    architectures = ["arm64"]
    description = "Corrects 'expirationdate' tags and nukes resources past their 'expirationdate'."
    filename = "lambda_function.zip"
    handler = "lambda_function.lambda_handler"
    memory_size = 1024
    runtime = "python3.9"
    source_code_hash = data.archive_file.lambda_function.output_base64sha256
    timeout = 300
    layers = [
        aws_lambda_layer_version.pyyaml.arn,
        aws_lambda_layer_version.aws_nuke.arn
    ]
}

resource "aws_cloudwatch_log_group" "aws_nuke_log_group" {
    name = "/aws/lambda/aws-nuke"
    retention_in_days = 30
}

data "aws_iam_policy_document" "lambda_logging" {
    statement {
        effect = "Allow"
        actions = ["logs:CreateLogGroup"]
        resources = ["arn:aws:logs:*:*:*"]
    }

    statement {
        effect = "Allow"
        actions = [
            "logs:CreateLogStream",
            "logs:PutLogEvents"
        ]
        resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/aws-nuke:*"]
    }
}

resource "aws_iam_policy" "lambda_logging" {
    name = "aws_nuke_lambda_logging"
    path = "/service-role/"
    description = "IAM policy for aws-nuke lambda function to log to CloudWatch"
    policy = data.aws_iam_policy_document.lambda_logging.json
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
    role = aws_iam_role.lambda_iam_role.name
    policy_arn = aws_iam_policy.lambda_logging.arn
}

resource "aws_cloudwatch_event_rule" "once_a_day" {
    name = "aws-nuke-once-a-day"
    description = "Runs aws-nuke lambda function once a day"
    schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "aws_nuke_once_a_day" {
    rule = aws_cloudwatch_event_rule.once_a_day.name
    target_id = "aws_nuke"
    arn = aws_lambda_function.aws_nuke_lambda.arn
}

resource "aws_lambda_permission" "cloudwatch_event_permission" {
    statement_id = "AllowAWS-NukeFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.aws_nuke_lambda.function_name
    principal = "events.amazonaws.com"
    source_arn = aws_cloudwatch_event_rule.once_a_day.arn
}