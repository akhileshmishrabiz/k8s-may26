repo : 879381241087.dkr.ecr.ap-south-1.amazonaws.com/kind-static-app


docker build -t kindapp .

docker tag kindapp  879381241087.dkr.ecr.ap-south-1.amazonaws.com/kind-static-app:1.0


docker push 879381241087.dkr.ecr.ap-south-1.amazonaws.com/kind-static-app:1.0

aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin 879381241087.dkr.ecr.ap-south-1.amazonaws.com



# when useing cer with kind

<!-- kubectl create secret <type_of_secret> <secret-name> -->
kubectl create secret docker-registry ecr-secret \
  --docker-server=879381241087.dkr.ecr.ap-south-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-south-1) \
  --namespace=default

