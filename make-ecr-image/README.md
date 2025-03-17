# Make ECR Image

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

### Create S3 bucket and an ECR repository
Note you only have to do this once and you may also simply use an existing bucket and 
repo. Since you may want to keep S3 objects after the stack has been deleted, you can't 
make the bucket within the CloudFormation stack. You also can't push a Docker image into 
ECR through CloudFormation, so it has to be done before you deploy the Task stack that 
requires the ECR image. Therefore the ECR repo must also be created before the stack is 
deployed.

```shell
aws s3 mb s3://$BUCKET 
aws ecr create-repository --repository-name $IMAGE_NAME --region $AWS_REGION \
--image-scanning-configuration scanOnPush=true --image-tag-mutability MUTABLE
```

## 2. Create and Publish Container to ECR

### Commands to build image and verifiy that it was built
Note you need the Docker daemon installed to complete the following.
```shell
docker buildx build --platform linux/amd64 --provenance=false -t ${IMAGE_NAME}:${IMAGE_TAG} .
docker images 
```

#### Note
If trying to build mulitple times you may run out of disk space.   
`docker system df` will show the reclaimable disck space.   
`docker system prune -a` will delete all docker artifacts.   

### Authenticate Docker CLI with ECR
You should see `Login Succeeded` after this command.
```shell
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS \
--password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

### Give the image the `latest` tag
```shell
docker tag ${IMAGE_NAME}:${IMAGE_TAG} $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${IMAGE_NAME}:latest
```

### Deploy Docker image to ECR
```shell 
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${IMAGE_NAME}:latest
```

## 3. References
 - [CLI Repo Version](https://github.com/daniel-fudge/aws-fargate-step-function-demo)    
 - [CloudFormation Repo Version](https://github.com/daniel-fudge/aws-fargate-step-function-cloud-formation)    
