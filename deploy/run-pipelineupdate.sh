#!/bin/bash
echo "Using Account:$ACCID  Region:$AWS_DEFAULT_REGION"
ACCID=$(aws sts get-caller-identity --query 'Account' | tr -d '"')
ESTR=$((aws cloudformation update-stack --stack-name SC-IACPipeline --parameters '[{"ParameterKey":"ChildAccountAccess","UsePreviousValue":true}]' --template-url "https://$DEPLOY_BUCKET.s3.amazonaws.com/deploy/sc-codepipeline.json" --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND) 2>&1)
ECODE=$?
if [[ "$ECODE" -eq "255" && "$ESTR" =~ .(No updates are to be performed\.)$ ]]
then 
  echo "No updates, continue."
  exit 0
else
  echo "$ECODE $ESTR"
  exit $ECODE
fi