#!/bin/bash

#                                     
#  _____         _ _ _         _       
# |     |___ ___| | | |___ ___| |_ ___ 
# |  |  | . |_ -| | | | . |  _| '_|_ -|
# |_____|  _|___|_____|___|_| |_,_|___|
#       |_|                            
#                                    
#  ____          _                     
# |    \ ___ ___| |___ _ _ ___ ___     
# |  |  | -_| . | | . | | | -_|  _|    
# |____/|___|  _|_|___|_  |___|_|      
#           |_|       |___|            
#
#
#  A simple script to deploy an 
#  app instance on OpsWorks.
#

SCRIPT_VERSION=1.0.0

die () {
  echo >&2 "$@"
  exit 1
}

deployment_status () {
  DEPLOYMENT_STATUS=$(
    aws opsworks describe-deployments \
    --deployment-id="$1" \
    --query "Deployments[0].Status" \
    | \
    grep -oE "successful|running|failed"
  )
}

STACK_NAME=${STACK_NAME:-$1}
APP_NAME=${APP_NAME:-$2}
DEPLOYMENT_COMMENT=${DEPLOYMENT_COMMENT:-${3:-Automated\ deployment\ \(script\ version:\ $SCRIPT_VERSION\)}}

if [ -z "$STACK_NAME" ]; then
  die "STACK_NAME is required, either via the environment or the first argument"
fi

if [ -z "$APP_NAME" ]; then
  die "APP_NAME is required, either via the environment or the second argument"
fi

# Retrieve the Stack ID for the named stack
STACK_ID=$(
  aws opsworks --region us-east-1 describe-stacks \
  --query "Stacks[?Name == \`$STACK_NAME\`].StackId" \
  | \
  grep -o "\\w\{8\}-\\w\{4\}-\\w\{4\}-\\w\{4\}-\\w\{12\}"
)

if [ -z "$STACK_ID" ]; then
  die "Unable to retrieve the Stack ID for $STACK_NAME"
fi

# Retrieve the App ID for the named app
APP_ID=$(
  aws opsworks --region us-east-1 describe-apps \
  --stack-id="$STACK_ID" \
  --query "Apps[?Name == \`$APP_NAME\`].AppId" \
  | \
  grep -o "\\w\{8\}-\\w\{4\}-\\w\{4\}-\\w\{4\}-\\w\{12\}"
)

if [ -z "$APP_ID" ]; then
  die "Unable to retrieve the App ID for $APP_NAME on Stack $STACK_NAME"
fi

# Issue a deploy for the stack and app, 
# defaulting to deploy across all instances in the layer

DEPLOYMENT_ID=$(
  aws opsworks --region us-east-1 create-deployment \
  --stack-id="$STACK_ID" \
  --app-id="$APP_ID" \
  --command='{"Name": "deploy", "Args": { "migrate": ["true"] } }' \
  --comment="$DEPLOYMENT_COMMENT" \
  | \
  grep -o "\\w\{8\}-\\w\{4\}-\\w\{4\}-\\w\{4\}-\\w\{12\}"
)

if [ -z "$DEPLOYMENT_ID" ]; then
  die "The deploy was unsuccessful for App $APP_NAME on Stack $STACK_NAME"
fi

echo "Successfully created deployment $DEPLOYMENT_ID, beginning to monitor"

deployment_status $DEPLOYMENT_ID

if [ -z "$DEPLOYMENT_STATUS" ]; then
  die "Unable to retrieve the deployment status, or it was not one of successful, running, or failed"
fi

while [ $DEPLOYMENT_STATUS = "running" ]; do
  echo -n "."
  sleep 10s
  deployment_status $DEPLOYMENT_ID
done

echo ""

if [ -z "$DEPLOYMENT_STATUS" ]; then
  die "An error occurred detecting the status of the current deployment"
elif [ "$DEPLOYMENT_STATUS" = "failed" ]; then
  die "The deploy for app $APP_NAME failed"
else
  echo "The deploy for app $APP_NAME was successful"
fi