#!/bin/bash

# This script will setup the Automated pipeline, IAM Roles, and a ServiceCatalog Portfolio. This will create resources
# across three regions using CloudFormation StackSets.

ACC=$(aws sts get-caller-identity --query 'Account' | tr -d '"')
# add child accounts as space delimited list. 
childAcc=""
childAccComma=${childAcc// /,}
allACC="$ACC $childAcc"
export AWS_DEFAULT_REGION=us-east-1
allregions="us-east-1 us-east-2 us-west-1"
LinkedRole1=""
S3RootURL="https://s3.amazonaws.com/vr-pipeline-foundations-us-east-1"

date
echo "Using Account:$ACC  Region:$AWS_DEFAULT_REGION Child Accounts:$childAcc All Regions:$allregions"

echo "Creating the StackSet IAM roles"
aws cloudformation create-stack --region $AWS_DEFAULT_REGION --stack-name IAM-StackSetAdministrator --template-url "$S3RootURL/deploy/stackset-admin-role.yml" --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
aws cloudformation create-stack --region $AWS_DEFAULT_REGION --stack-name IAM-StackSetExecution --parameters "[{\"ParameterKey\":\"AdministratorAccountId\",\"ParameterValue\":\"$ACC\"}]" --template-url "$S3RootURL/deploy/stackset-execution-role.yml" --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
echo "waiting for stacks to complete..."
aws cloudformation wait stack-create-complete --stack-name IAM-StackSetAdministrator
aws cloudformation wait stack-create-complete --stack-name IAM-StackSetExecution

echo "creating the automation pipeline stack"
aws cloudformation create-stack --region $AWS_DEFAULT_REGION --stack-name SC-IACPipeline --parameters "[{\"ParameterKey\":\"ChildAccountAccess\",\"ParameterValue\":\"$childAccComma\"}]" --template-url "$S3RootURL/codepipeline/sc-codepipeline.json" --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND

echo "creating the ServiceCatalog IAM roles StackSet"
aws cloudformation create-stack-set --stack-set-name SC-IAC-automated-IAMroles --parameters "[{\"ParameterKey\":\"RepoRootURL\",\"ParameterValue\":\"$S3RootURL/\"}]" --template-url "$S3RootURL/iam/sc-setup-iam.json" --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
SSROLEOPID=$(aws cloudformation create-stack-instances --stack-set-name SC-IAC-automated-IAMroles --regions $AWS_DEFAULT_REGION --accounts $ACC --operation-preferences FailureToleranceCount=0,MaxConcurrentCount=1 | jq '.OperationId' | tr -d '"')
STATUS=""
until [ "$STATUS" = "SUCCEEDED" ]; do 
  STATUS=$(aws cloudformation describe-stack-set-operation --stack-set-name SC-IAC-automated-IAMroles --operation-id $SSROLEOPID | jq '.StackSetOperation.Status' | tr -d '"')
  echo "waiting for IAMrole Stackset to complete. current status: $STATUS"
  sleep 10
done

echo "creating the ServiceCatalog Portfolio StackSet"
aws cloudformation create-stack-set --stack-set-name SC-ECS-automated-portfolio --parameters "[{\"ParameterKey\":\"CreateEndUsers\",\"ParameterValue\":\"No\"},{\"ParameterKey\":\"LinkedRole1\",\"ParameterValue\":\"$LinkedRole1\"},{\"ParameterKey\":\"LinkedRole2\",\"ParameterValue\":\"\"},{\"ParameterKey\":\"LaunchRoleName\",\"ParameterValue\":\"SCEC2LaunchRole\"},{\"ParameterKey\":\"RepoRootURL\",\"ParameterValue\":\"$S3RootURL/\"}]" --template-url "$S3RootURL/ecs/sc-portfolio-ecs.json" --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
aws cloudformation create-stack-instances --stack-set-name SC-ECS-automated-portfolio --regions $allregions --accounts $ACC --operation-preferences FailureToleranceCount=0,MaxConcurrentCount=3

date
echo "Complete.  See CloudFormation Stacks and StackSets Console in each region for more details: $allregions"