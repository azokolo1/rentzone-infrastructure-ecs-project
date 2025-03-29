locals {
  region       = var.region
  project_name = var.project_name
  environment  = var.environment

  # Get target group ARN via data source
  alb_target_group_arn = data.aws_lb_target_group.app_tg.arn
}

# Data source to fetch the target group
data "aws_lb_target_group" "app_tg" {
  name = "${local.project_name}-${local.environment}-tg"

  # Add a dependency to ensure this runs after the ALB module
  depends_on = [
    module.application_load_balancer
  ]
}

# create vpc module
module "vpc" {
  source                  = "git@github.com:azokolo1/terraform-modules.git//vpc"
  region                  = local.region
  project_name            = local.project_name
  environment             = local.environment
  vpc_cidr                = var.vpc_cidr
  public_subnet_az1       = var.public_subnet_az1
  public_subnet_az2       = var.public_subnet_az2
  private_app_subnet_az1  = var.private_app_subnet_az1
  private_app_subnet_az2  = var.private_app_subnet_az2
  private_data_subnet_az1 = var.private_data_subnet_az1
  private_data_subnet_az2 = var.private_data_subnet_az2
}

# create nat-gateway
module "nat-gateway" {
  source                     = "git@github.com:azokolo1/terraform-modules.git//nat-gateway"
  project_name               = local.project_name
  environment                = local.environment
  public_subnet_az1_id       = module.vpc.public_subnet_az1_id
  internet_gateway           = module.vpc.internet_gateway
  public_subnet_az2_id       = module.vpc.public_subnet_az2_id
  vpc_id                     = module.vpc.vpc_id
  private_app_subnet_az1_id  = module.vpc.private_app_subnet_az1_id
  private_data_subnet_az1_id = module.vpc.private_data_subnet_az1_id
  private_app_subnet_az2_id  = module.vpc.private_app_subnet_az2_id
  private_data_subnet_az2_id = module.vpc.private_data_subnet_az2_id
}

# create security groups
module "security-groups" {
  source       = "git@github.com:azokolo1/terraform-modules.git//security-group"
  project_name = local.project_name
  environment  = local.environment
  vpc_id       = module.vpc.vpc_id
  ssh_ip       = var.ssh_ip
}

# launch rds instance
module "rds" {
  source                       = "git@github.com:azokolo1/terraform-modules.git//rds"
  project_name                 = local.project_name
  environment                  = local.environment
  private_data_subnet_az1_id   = module.vpc.private_data_subnet_az1_id
  private_data_subnet_az2_id   = module.vpc.private_data_subnet_az2_id
  database_snapshot_identifier = var.database_snapshot_identifier
  database_instance_class      = var.database_instance_class
  availability_zone_1          = module.vpc.availability_zone_1
  database_instance_identifier = var.database_instance_identifier
  multi_az_deployment          = var.multi_az_deployment
  database_security_group_id   = module.security-groups.database_security_group_id
}

# request ssl certificate
module "ssl_certificate" {
  source            = "git@github.com:azokolo1/terraform-modules.git//acm"
  domain_name       = var.domain_name
  alternative_names = var.alternative_names
}

# create application load balancer
module "application_load_balancer" {
  source                = "git@github.com:azokolo1/terraform-modules.git//alb"
  project_name          = local.project_name
  environment           = local.environment
  alb_security_group_id = module.security-groups.alb_security_group_id
  public_subnet_az1_id  = module.vpc.public_subnet_az1_id
  public_subnet_az2_id  = module.vpc.public_subnet_az2_id
  target_type           = var.target_type
  vpc_id                = module.vpc.vpc_id
  certificate_arn       = module.ssl_certificate.certificate_arn
}

# create s3 bucket
module "s3_bucket" {
  source               = "git@github.com:azokolo1/terraform-modules.git//s3"
  project_name         = local.project_name
  env_file_bucket_name = var.env_file_bucket_name
  env_file_name        = var.env_file_name
}

# create ecs task execution role
module "ecs_task_execution_role" {
  source               = "git@github.com:azokolo1/terraform-modules.git//iam-role"
  project_name         = local.project_name
  environment          = local.environment
  env_file_bucket_name = module.s3_bucket.env_file_bucket_name
}

# create ecs cluster task definition and service
module "ecs" {
  source                       = "git@github.com:azokolo1/terraform-modules.git//ecs"
  alb_target_group_arn         = local.alb_target_group_arn
  project_name                 = local.project_name
  environment                  = local.environment
  ecs_task_execution_role_arn  = module.ecs_task_execution_role.ecs_task_execution_role_arn
  architecture                 = var.architecture
  container_image              = var.container_image
  env_file_bucket_name         = module.s3_bucket.env_file_bucket_name
  env_file_name                = module.s3_bucket.env_file_name
  region                       = local.region
  private_app_subnet_az1_id    = module.vpc.private_app_subnet_az1_id
  private_app_subnet_az2_id    = module.vpc.private_app_subnet_az2_id
  app_server_security_group_id = module.security-groups.app_server_security_group_id
}

# create an auto scaling group
module "ecs_asg" {
  source       = "git@github.com:azokolo1/terraform-modules.git//asg-ecs"
  project_name = local.project_name
  environment  = local.environment
  ecs_service  = module.ecs.ecs_service
}