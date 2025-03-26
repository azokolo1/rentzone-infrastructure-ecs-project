locals {
  region       = var.region
  project_name = var.project_name
  environment  = var.environment
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