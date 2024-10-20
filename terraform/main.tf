provider "aws" {
    region = "us-east-1"
}

resource "aws_s3_bucket" "lambda_bucket" {
    bucket = "my-serverless-app-bucket-harika"
    acl    = "private"
}

resource "aws_iam_role" "lambda_role" {
    name = "lambda_role"
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action = "sts:AssumeRole"
            Principal = {
                Service = "lambda.amazonaws.com"
            }
            Effect = "Allow"
            Sid    = ""
        }]
    })
}

resource "aws_s3_bucket_object" "lambda_zip" {
    bucket = aws_s3_bucket.lambda_bucket.bucket
    key    = "lambda.zip"
    source = "../lambda/lambda.zip"  # Path to your zipped Lambda function
}

resource "aws_lambda_function" "my_lambda" {
    function_name = "my_lambda_function"
    handler       = "handler.handler"
    runtime       = "nodejs18.x"
    role          = aws_iam_role.lambda_role.arn
    s3_bucket     = aws_s3_bucket.lambda_bucket.bucket
    s3_key        = aws_s3_bucket_object.lambda_zip.key
}


# Create a CodeCommit repository
resource "aws_codecommit_repository" "my_repo" {
    repository_name = "my-serverless-app-repo"
    description     = "My Serverless App Repository"
}

# Create a CodeBuild project
resource "aws_codebuild_project" "my_build" {
    name          = "my-serverless-app-build"
    service_role  = aws_iam_role.lambda_role.arn
    source {
        type            = "CODECOMMIT"
        location        = aws_codecommit_repository.my_repo.clone_url_http
        buildspec       = "buildspec.yml"
    }
    environment {
        compute_type = "BUILD_GENERAL1_SMALL"
        image        = "aws/codebuild/standard:5.0"
        type         = "LINUX_CONTAINER"
    }
}

# Create a CodePipeline
resource "aws_codepipeline" "my_pipeline" {
    name     = "my-serverless-app-pipeline"
    role_arn = aws_iam_role.lambda_role.arn

    artifact_store {
        location = aws_s3_bucket.lambda_bucket.bucket
        type     = "S3"
    }

    stage {
        name = "Source"
        action {
            name            = "Source"
            category        = "Source"
            provider        = "CodeCommit"
            output_artifacts = ["source_output"]
            configuration = {
                RepositoryName = aws_codecommit_repository.my_repo.repository_name
                BranchName     = "main"
            }
        }
    }

    stage {
        name = "Build"
        action {
            name            = "Build"
            category        = "Build"
            provider        = "CodeBuild"
            input_artifacts = ["source_output"]
            output_artifacts = ["build_output"]
            configuration = {
                ProjectName = aws_codebuild_project.my_build.name
            }
        }
    }

    stage {
        name = "Deploy"
        action {
            name            = "Deploy"
            category        = "Invoke"
            provider        = "Lambda"
            input_artifacts = ["build_output"]
            configuration = {
                FunctionName = aws_lambda_function.my_lambda.function_name
                UserParameters = jsonencode({"bucket" : aws_s3_bucket.lambda_bucket.bucket})
            }
        }
    }
}
