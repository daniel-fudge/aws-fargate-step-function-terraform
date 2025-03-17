# aws-fargate-step-function-terraform
Small repo that creates an AWS Step Function to call Fargate tasks with Terraform.
![image](Fargate-Step-Function-TF.png)

This repo is related to two other repos. The first [repo](https://github.com/daniel-fudge/aws-fargate-step-function-demo) 
deployed the same Step Function but performed it with CLI commands. It also deployed the 
same ECR image to a Lambda Function called be a Step Function to demostrate the 
versatility of the ECR image.   
The second [repo](https://github.com/daniel-fudge/aws-fargate-step-function-cloud-formation) 
deployed the Fargate Step Function with CloudFormation.    
This repo replicates the CloudFormation repo in Terraform to compare the two IaC packages. 
It also skips the initial task stack and moved the ECR image creation to a sub-folder. 

## 1. Setup the Environment
### Configure the AWS Console
Before completing the following CLI command, you need to install the AWS CLI and configure 
it for the account, role and region you wish to use. I use the `aws configure sso` command.

### First set some environment variables
```shell
export AWS_ACCOUNT_ID=[ENTER YOUR AWS ACCOUNT ID HERE]
export AWS_PROFILE=[ENTER YOUR CLI PROFILE NAME HERE]
export BUCKET=[ENTER YOUR BUCKET NAME HERE]
export AWS_PAGER=""
export AWS_REGION=us-east-1
export IMAGE_NAME=timer
export IMAGE_TAG=v1
```

### S3 and ECR Image Creation
This is the exact same setup as required in the previous two repos. If you already have 
the S3 bucket and ECR image created there you can skip to the next section. If you don't, 
you can follow the make-ecr-image [README](make-ecr-image/README.md). 


## 4. Add a Step Function to the Stack
REMINDER: Delete the stack created in the previous step. This section will create a 
completely new stack and does not require the previous stack.

Create the stack and wait for it to be completed.
```shell
aws cloudformation create-stack --stack-name step --template-body file://step.yml \
--capabilities CAPABILITY_NAMED_IAM --disable-rollback \
--parameters ParameterKey=Bucket,ParameterValue=${BUCKET}
aws cloudformation wait stack-create-complete --stack-name step
```
To delete the stack and wait for it to be deleted:
```shell
aws cloudformation delete-stack --stack-name step
aws cloudformation wait stack-delete-complete --stack-name step
```

### Invoke the step function
```shell
sed "s/BUCKET/${BUCKET}/" step-input-fargate.json > temp.json
aws stepfunctions start-execution \
--state-machine-arn arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${IMAGE_NAME}-fargate \
--input "$(cat temp.json)"
rm -f temp.json
```

## 5. References
 - [CLI Repo Version](https://github.com/daniel-fudge/aws-fargate-step-function-demo)    
 - [CloudFormation Example Repo](https://github.com/nathanpeck/aws-cloudformation-fargate)    
 - [AWS CloudFormation CLI](https://awscli.amazonaws.com/v2/documentation/api/2.1.29/reference/cloudformation/index.html#cli-aws-cloudformation)
 - [AWS CloudFormation Template Reference](https://docs.aws.amazon.com/AWScloudformation/latest/UserGuide/template-reference.html)
