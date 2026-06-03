
# aws eks update-kubeconfig --name <cluster name>


# buil ecr image s
# 879381241087.dkr.ecr.ap-south-1.amazonaws.com/devopsdozo

cd backend
docker build --platform linux/amd64 -t  879381241087.dkr.ecr.ap-south-1.amazonaws.com/devopsdozo:backend .

cd ../frontend
docker build --platform linux/amd64 -t  879381241087.dkr.ecr.ap-south-1.amazonaws.com/devopsdozo:frontend .

# ecr login
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 879381241087.dkr.ecr.ap-south-1.amazonaws.com

docker push 879381241087.dkr.ecr.ap-south-1.amazonaws.com/devopsdozo:frontend

docker push 879381241087.dkr.ecr.ap-south-1.amazonaws.com/devopsdozo:backend


# EKS infra from terraform
- Network setup - public/private subnets, Nat gateway
- private route table, private subnet associtaed 





user: postgres
db:postgres
password: Admin1234



my dockerhub for images

https://hub.docker.com/repository/docker/livingdevopswithakhilesh/devopsdozo/general