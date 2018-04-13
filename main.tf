module "label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.3"
  namespace  = "${var.namespace}"
  stage      = "${var.stage}"
  name       = "${var.name}"
  delimiter  = "${var.delimiter}"
  attributes = "${var.attributes}"
  tags       = "${var.tags}"
}

module "kops_metadata" {
  source     = "git::https://github.com/cloudposse/terraform-aws-kops-metadata.git?ref=tags/0.1.1"
  dns_zone   = "${var.name}"
  nodes_name = "${var.nodes_name}"
}

resource "aws_s3_bucket" "default" {
  bucket        = "${module.label.id}"
  acl           = "private"
  force_destroy = false

  tags = "${
      merge(
        module.label.tags,
        map(
          "Description", "Used for secrets storage with Vault"
        )
      )
    }"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

data "aws_iam_policy_document" "default" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.default.arn}"]
    effect    = "Allow"
  }

  statement {
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.default.arn}/*"]
    effect    = "Allow"
  }
}

resource "aws_iam_policy" "default" {
  name        = "${module.label.id}"
  policy      = "${data.aws_iam_policy_document.default.json}"
  description = "Allow Vault to get/put/delete objects from the bucket"
}

data "aws_iam_policy_document" "role_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"

      identifiers = [
        "${module.kops_metadata.nodes_role_arn}",
      ]
    }
  }
}

resource "aws_iam_role" "default" {
  name               = "${module.label.id}"
  assume_role_policy = "${data.aws_iam_policy_document.role_trust.json}"
  description        = "Allow Vault to get/put/delete objects from the bucket"
}

resource "aws_iam_role_policy_attachment" "default" {
  role       = "${aws_iam_role.default.name}"
  policy_arn = "${aws_iam_policy.default.arn}"
}
