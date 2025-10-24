git config --global user.email "gandinehru35@gmail.com"
cd my-gke-app
git init
git add .
git commit -m "Initial project"
git remote add origin https://github.com/<your-username>/gke-interview-project.git
git push -u origin main
git config --global user.email "gandinehru35@gmail.com"
git config --global user.name "gandinehru35-spec"
git init
git add .
git commit -m "Initial project"
git remote add origin https://github.com/gandinehru35-spec/gke-interview-project.git
git push -u origin main
cd my-gke-app
git init
git add .
git commit -m "Initial project"
git remote add origin https://github.com/gandinehru35-spec/gke-interview-project.git
git push -u origin main
pwd
cd my-gke-app
cd ~
pwd
cd my-gke-app
ls
mkdir -p backend frontend helm/my-gke-app/templates
ls
mv /home/gandinehru35/my-gke-app/frontend/my-gke-app/helm/my-gke-app/* helm/my-gke-app/
rm -rf /home/gandinehru35/my-gke-app/frontend/my-gke-app
rm -rf /home/gandinehru35/my-gke-app/frontend/my-gke-app/helm/my-gke-app/.git
rm -rf /home/gandinehru35/my-gke-app/helm/my-gke-app/.git
cd /home/gandinehru35/my-gke-app
rm -rf .git  # Remove any existing root .git to start fresh
git init
cd /home/gandinehru35/my-gke-app/backend
cat <<EOF > Dockerfile
FROM python:3.9-slim
RUN pip install flask
COPY app.py .
CMD ["python", "app.py"]
EOF

cat <<EOF > app.py
from flask import Flask
app = Flask(__name__)
@app.route('/')
def hello():
    return "Hello from Backend!"
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

cd /home/gandinehru35/my-gke-app/frontend
cat <<EOF > Dockerfile
FROM nginx:latest
COPY index.html /usr/share/nginx/html/index.html
EOF

cat <<EOF > index.html
<!DOCTYPE html>
<html>
<body>
  <h1>Welcome to the Frontend!</h1>
</body>
</html>
EOF

cd /home/gandinehru35/my-gke-app/helm/my-gke-app
cat <<EOF > Chart.yaml
apiVersion: v2
name: my-gke-app
description: Microservices app for GKE
type: application
version: 0.1.0
appVersion: "1.0"
EOF

cat <<EOF > values.yaml
replicaCount: 2
backend:
  image:
    repository: us-central1-docker.pkg.dev/alpine-anvil-473102-c4/my-repo/backend-api
    tag: latest
    pullPolicy: IfNotPresent
  service:
    port: 8080
frontend:
  image:
    repository: us-central1-docker.pkg.dev/alpine-anvil-473102-c4/my-repo/frontend-ui
    tag: latest
    pullPolicy: IfNotPresent
  service:
    type: LoadBalancer
    port: 80
EOF

cat <<EOF > templates/app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-gke-app.fullname" . }}-backend
  labels:
    app: microservice
    tier: backend
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      tier: backend
  template:
    metadata:
      labels:
        tier: backend
    spec:
      containers:
      - name: backend-container
        image: "{{ .Values.backend.image.repository }}:{{ .Values.backend.image.tag }}"
        imagePullPolicy: {{ .Values.backend.image.pullPolicy }}
        ports:
        - containerPort: {{ .Values.backend.service.port }}
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  labels:
    tier: backend
spec:
  selector:
    tier: backend
  ports:
  - port: 80
    targetPort: {{ .Values.backend.service.port }}
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-gke-app.fullname" . }}-frontend
  labels:
    app: microservice
    tier: frontend
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      tier: frontend
  template:
    metadata:
      labels:
        tier: frontend
    spec:
      containers:
      - name: frontend-container
        image: "{{ .Values.frontend.image.repository }}:{{ .Values.frontend.image.tag }}"
        imagePullPolicy: {{ .Values.frontend.image.pullPolicy }}
        ports:
        - containerPort: {{ .Values.frontend.service.port }}
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  labels:
    tier: frontend
spec:
  selector:
    tier: frontend
  ports:
  - port: 80
    targetPort: {{ .Values.frontend.service.port }}
  type: {{ .Values.frontend.service.type }}
EOF

mkdir -p /home/gandinehru35/my-gke-app/.github/workflows
cd /home/gandinehru35/my-gke-app
cat <<EOF > .github/workflows/deploy.yaml
name: Deploy to GKE
on:
  push:
    branches: [ main ]
jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: 'read'
      id-token: 'write'
    steps:
    - uses: actions/checkout@v3
    - name: Authenticate to GCP
      uses: google-github-actions/auth@v2
      with:
        workload_identity_provider: 'projects/737956044912/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider'
        service_account: 'github-deployer@alpine-anvil-473102-c4.iam.gserviceaccount.com'
    - name: Set up gcloud
      uses: google-github-actions/setup-gcloud@v1
    - name: Configure Docker
      run: gcloud auth configure-docker us-central1-docker.pkg.dev --quiet
    - name: Set up Helm
      uses: azure/setup-helm@v4
      with:
        version: 'v3.15.0'
    - name: Build and Push Backend
      run: |
        cd backend
        docker build -t us-central1-docker.pkg.dev/alpine-anvil-473102-c4/my-repo/backend-api:\${{ github.sha }} .
        docker push us-central1-docker.pkg.dev/alpine-anvil-473102-c4/my-repo/backend-api:\${{ github.sha }}
    - name: Build and Push Frontend
      run: |
        cd frontend
        docker build -t us-central1-docker.pkg.dev/alpine-anvil-473102-c4/my-repo/frontend-ui:\${{ github.sha }} .
        docker push us-central1-docker.pkg.dev/alpine-anvil-473102-c4/my-repo/frontend-ui:\${{ github.sha }}
    - name: Deploy to GKE
      run: |
        gcloud container clusters get-credentials gke-interview-cluster --zone=us-central1-c --project=alpine-anvil-473102-c4
        helm upgrade --install my-app helm/my-gke-app           --set backend.image.tag=\${{ github.sha }}           --set frontend.image.tag=\${{ github.sha }}
EOF

cd /home/gandinehru35/my-gke-app
git add .
git status
git commit -m "Initial project setup with backend, frontend, and Helm chart"
git remote rm origin
git remote add origin https://github.com/gandinehru35-spec/gke-interview-project.git
git branch
git branch -m master main
git push -u origin main
ssh-keygen -t ed25519 -C "gandinehru35@gmail.com"
cat /home/gandinehru35/.ssh/id_ed25519.pub
git push -u origin main
git status
git push -u origin main
git remote set-url origin git@github.com/gandinehru35-spec/gke-interview-project.git
git push -u origin main
gcloud auth login
git remote add origin https://github.com/gandinehru35-spec/gke-interview-project.git
git push -u origin main
git remote set-url origin https://github.com/gandinehru35-spec/gke-interview-project.git
git push -u origin main
git remote add origin git@github.com:gandinehru35-spec/https-github.com-ggke-interview-project.git
git branch -M main
git push -u origin main
git remote set-url origin git@github.com/gandinehru35-spec/gke-interview-project.git
git remote add origin git@github.com:gandinehru35-spec/https-github.com-ggke-interview-project.git
git branch -M main
git push -u origin main
echo "# https-github.com-ggke-interview-project" >> README.md
git init
git add README.md
git commit -m "first commit"
git branch -M main
git remote add origin git@github.com:gandinehru35-spec/https-github.com-ggke-interview-project.git
git push -u origin main
git remote -v
git push -u origin main
echo "# https-github.com-ggke-interview-project" >> README.md
git init
git add README.md
git commit -m "first commit"
git branch -M main
git remote add origin https://github.com/gandinehru35-spec/https-github.com-ggke-interview-project.git
git push -u origin main
git remote add origin git@github.com:gandinehru35-spec/https-github.com-ggke-interview-project.git
git branch -M main
git push -u origin main
git remote set-url origin git@github.com/gandinehru35-spec/https-github.com-ggke-interview-project.git
git push -u origin main
echo "# https-github.com-ggke-interview-project" >> README.md
git init
git add README.md
git commit -m "first commit"
git branch -M main
git remote add origin git@github.com:gandinehru35-spec/https-github.com-ggke-interview-project.git
git push -u origin main
ssh -T git@github.com
git push -u origin main
git remote add origin git@github.com:gandinehru35-spec/https-github.com-ggke-interview-project.git
git branch -M main
git push -u origin main
git remote set-url origin git@github.com:gandinehru35-spec/https-github.com-ggke-interview-project.git
git push -u origin main
gcloud iam workload-identity-pools create github-actions-pool     --project=alpine-anvil-473102-c4     --location=global     --display-name="GitHub Actions Pool"
gcloud iam workload-identity-pools providers create-oidc github-provider     --project=alpine-anvil-473102-c4     --location=global     --workload-identity-pool=github-actions-pool     --display-name="GitHub Provider"     --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.aud=aud"     --issuer-uri="https://token.actions.githubusercontent.com"
gcloud iam service-accounts add-iam-policy-binding github-deployer@alpine-anvil-473102-c4.iam.gserviceaccount.com     --project=alpine-anvil-473102-c4     --role="roles/iam.workloadIdentityUser"     --member="principalSet://iam.googleapis.com/projects/737956044912/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/gandinehru35-spec/gke-interview-project"
gcloud projects add-iam-policy-binding alpine-anvil-473102-c4     --member="serviceAccount:github-deployer@alpine-anvil-473102-c4.iam.gserviceaccount.com"     --role="roles/container.developer"
gcloud projects add-iam-policy-binding alpine-anvil-473102-c4     --member="serviceAccount:github-deployer@alpine-anvil-473102-c4.iam.gserviceaccount.com"     --role="roles/artifactregistry.writer"
gcloud projects describe alpine-anvil-473102-c4 --format="value(projectNumber)"
gcloud iam service-accounts create github-deployer     --display-name="GitHub Actions Deployer SA"     --description="SA for GitHub Actions CI/CD to GKE"     --project=alpine-anvil-473102-c4
gcloud iam service-accounts describe github-deployer@alpine-anvil-473102-c4.iam.gserviceaccount.com --project=alpine-anvil-473102-c4
gcloud iam workload-identity-pools providers delete github-provider     --workload-identity-pool=github-actions-pool     --location=global     --project=alpine-anvil-473102-c4
gcloud iam workload-identity-pools providers create-oidc github-provider     --project=alpine-anvil-473102-c4     --location=global     --workload-identity-pool=github-actions-pool     --display-name="GitHub Provider"     --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.aud=aud,attribute.repository=assertion.repository"     --issuer-uri="https://token.actions.githubusercontent.com"
kubectl get pod
kubectl get all
kubectl delete all --all -n default
kubectl get all
gcloud auth login
gcloud config set project alpine-anvil-473102-c4
gcloud config set compute/region northamerica-northeast1
gcloud config set compute/zone northamerica-northeast1-a
gcloud services enable   container.googleapis.com   sqladmin.googleapis.com   redis.googleapis.com   artifactregistry.googleapis.com   iam.googleapis.com   compute.googleapis.com   monitoring.googleapis.com   secretmanager.googleapis.com
git config --global user.name "gandinehru35-spec"
git config --global user.email "gandinehru35@gmail.com"
gcloud compute networks create gke-vpc --subnet-mode=custom
gcloud compute networks subnets create gke-subnet   --network=gke-vpc   --region=northamerica-northeast1   --range=10.10.0.0/24
# Reserve a range for GKE Pods (alias IP)
gcloud compute networks subnets update gke-subnet   --region=northamerica-northeast1   --add-secondary-ranges=pods=10.20.0.0/20,services=10.21.0.0/24
DB_PASS='ChangeThisStrongPassw0rd!'
gcloud sql instances create bank-postgres   --database-version=POSTGRES_14   --cpu=1 --memory=3840MB   --region=northamerica-northeast1   --network=projects/alpine-anvil-473102-c4/global/networks/gke-vpc   --no-assign-ip   --root-password="$DB_PASS"
gcloud services enable servicenetworking.googleapis.com   --project=alpine-anvil-473102-c4
gcloud compute addresses create google-managed-services-bank   --global   --prefix-length=24   --description="Private Services Access IP range for Cloud SQL"   --network=gke-vpc   --project=alpine-anvil-473102-c4
gcloud compute addresses describe google-managed-services-bank --global --project=alpine-anvil-473102-c4
gcloud services vpc-peerings connect   --service=servicenetworking.googleapis.com   --network=gke-vpc   --ranges=google-managed-services-bank   --project=alpine-anvil-473102-c4
gcloud services vpc-peerings list --network=gke-vpc --project=alpine-anvil-473102-c4
DB_PASS='ChangeThisStrongPassw0rd!'   # or your actual password
gcloud sql instances create bank-postgres   --database-version=POSTGRES_14   --cpu=1 --memory=3840MB   --region=northamerica-northeast1   --network=projects/alpine-anvil-473102-c4/global/networks/gke-vpc   --no-assign-ip   --root-password="$DB_PASS"   --project=alpine-anvil-473102-c4
gcloud sql instances describe bank-postgres --project=alpine-anvil-473102-c4
gcloud sql databases create bankdb --instance=bank-postgres
gcloud sql users create bankuser --instance=bank-postgres --password="$DB_PASS"
gcloud redis instances create bank-redis   --size=1 --region=northamerica-northeast1 --zone=northamerica-northeast1-a   --tier=BASIC   --network=projects/alpine-anvil-473102-c4/global/networks/gke-vpc
gcloud container clusters create bank-gke-cluster   --region=northamerica-northeast1   --num-nodes=1   --machine-type=e2-medium   --network=gke-vpc   --subnetwork=gke-subnet   --enable-ip-alias   --workload-pool=alpine-anvil-473102-c4.svc.id.goog   --enable-private-nodes=false   --enable-autoupgrade=false   --enable-autorepair=false
gcloud container clusters create bank-gke-cluster   --region=northamerica-northeast1   --num-nodes=1   --machine-type=e2-medium   --network=gke-vpc   --subnetwork=gke-subnet   --enable-ip-alias   --workload-pool=alpine-anvil-473102-c4.svc.id.goog   --enable-private-nodes=false   --enable-autoupgrade=false   --enable-autorepair=false
gcloud container clusters create bank-gke-cluster   --region=northamerica-northeast1   --num-nodes=1   --machine-type=e2-medium   --network=gke-vpc   --subnetwork=gke-subnet   --enable-ip-alias   --workload-pool=alpine-anvil-473102-c4.svc.id.goog   --enable-private-nodes=false   --enable-autoupgrade=false   --enable-autorepair=false
gcloud container clusters create bank-gke-cluster   --region=northamerica-northeast1   --num-nodes=1   --machine-type=e2-medium   --network=gke-vpc   --subnetwork=gke-subnet   --enable-ip-alias   --workload-pool=alpine-anvil-473102-c4.svc.id.goog 
gcloud container clusters get-credentials bank-gke-cluster --region=northamerica-northeast1
kubectl get nodes
gcloud container clusters update bank-gke-cluster   --region=northamerica-northeast1   --num-nodes=1   --machine-type=e2-medium   --network=gke-vpc   --subnetwork=gke-subnet   --enable-ip-alias   --workload-pool=alpine-anvil-473102-c4.svc.id.goog 
gcloud container clusters update bank-gke-cluster   --region=northamerica-northeast1 
gcloud container clusters delete bank-gke-cluster   --region=northamerica-northeast1 
gcloud container clusters delete bank-gke-cluster   --region=northamerica-northeast1 -f
gcloud container clusters delete 
gcloud container clusters delete --help
gcloud container clusters delete bank-gke-cluster   --region=northamerica-northeast1 --async
gcloud container operations list --location=CONTROL_PLANE_LOCATION
gcloud container operations list
gcloud container operations cancel operation-1760841469750-003a9686-e6db-4d30-8c1a-a646024c9dfc
gcloud container clusters delete bank-gke-cluster   --region=northamerica-northeast1 --async
gcloud container operations cancel operation-1760841469750-003a9686-e6db-4d30-8c1a-a646024c9dfc
gcloud container clusters delete bank-gke-cluster   --region=northamerica-northeast1 --ignore-errors     --quiet
gcloud container operations cancel operation-1760841469750-003a9686-e6db-4d30-8c1a-a646024c9dfc
gcloud container clusters delete bank-gke-cluster   --region=northamerica-northeast1 --async
gcloud container operations --help
gcloud container operations wait operation-1760841469750-003a9686-e6db-4d30-8c1a-a646024c9dfc
gcloud container clusters delete bank-gke-cluster   --region=northamerica-northeast1 --async
gcloud container operations wait operation-1760841469750-003a9686-e6db-4d30-8c1a-a646024c9dfc
gcloud container clusters delete bank-gke-cluster   --region=northamerica-northeast1 
gcloud container clusters delete bank-gke-cluster   --region=northamerica-northeast1 --async
gcloud container operations wait operation-1760844471102-d42f5fa2-995a-49bd-9bba-1d6fcf7c07d3
gcloud container clusters create bank-gke-cluster   --region=northamerica-northeast1   --num-nodes=1   --machine-type=e2-medium   --network=gke-vpc   --subnetwork=gke-subnet   --enable-ip-alias   --workload-pool=alpine-anvil-473102-c4.svc.id.goog 
gcloud container clusters delete bank-gke-cluster   --region=northamerica-northeast1 --async
goperation-1760844471102-d42f5fa2-995a-49b
gcloud container clusters create bank-gke-cluster   --zone=northamerica-northeast1-b   --num-nodes=1   --machine-type=e2-medium   --network=gke-vpc   --subnetwork=gke-subnet   --enable-ip-alias   --workload-pool=alpine-anvil-473102-c4.svc.id.goog
gcloud container clusters get-credentials bank-gke-cluster --zone=northamerica-northeast1-b
kubectl get nodes
kubectl get pods
kubectl get all
gcloud iam service-accounts create bank-app-sa --display-name="Bank App SA"
gcloud projects add-iam-policy-binding alpine-anvil-473102-c4   --member="serviceAccount:bank-app-sa@alpine-anvil-473102-c4.iam.gserviceaccount.com"   --role="roles/cloudsql.client"
gcloud projects add-iam-policy-binding alpine-anvil-473102-c4   --member="serviceAccount:bank-app-sa@alpine-anvil-473102-c4.iam.gserviceaccount.com"   --role="roles/secretmanager.secretAccessor"
kubectl create serviceaccount ksa-bank-app
gcloud iam service-accounts add-iam-policy-binding   --role roles/iam.workloadIdentityUser   --member "serviceAccount:alpine-anvil-473102-c4.svc.id.goog[default/ksa-bank-app]"   bank-app-sa@alpine-anvil-473102-c4.iam.gserviceaccount.com
gcloud sql connect bank-postgres --user=bankuser --quiet --database=bankdb
# then paste SQL
gcloud sql instances describe bank-postgres   --project=alpine-anvil-473102-c4   --format="value(connectionName)"
gcloud compute instances create sql-proxy-vm   --zone=northamerica-northeast1-b   --machine-type=e2-micro   --subnet=gke-subnet   --image-family=debian-12   --image-project=debian-cloud   --project=alpine-anvil-473102-c4
VM_SA_EMAIL=$(gcloud compute instances describe sql-proxy-vm \
  --zone=northamerica-northeast1-b \
  --project=alpine-anvil-473102-c4 \
  --format="value(serviceAccounts.email)")
echo $VM_SA_EMAIL
gcloud projects add-iam-policy-binding alpine-anvil-473102-c4   --member="serviceAccount:${VM_SA_EMAIL}"   --role="roles/cloudsql.client"
gcloud compute ssh sql-proxy-vm --zone=northamerica-northeast1-b --project=alpine-anvil-473102-c4
# update and install psql client
sudo apt-get update && sudo apt-get install -y wget postgresql-client
gcloud compute ssh sql-proxy-vm --zone=northamerica-northeast1-b --project=alpine-anvil-473102-c4
gcloud auth login
gcloud compute ssh sql-proxy-vm --zone=northamerica-northeast1-b --project=alpine-anvil-473102-c4
curl -s https://ifconfig.co
$MY_IP=curl -s https://ifconfig.co
$MY_IP={curl -s https://ifconfig.co
$MY_IP=34.23.65.254
export MY_IP=34.23.65.254
gcloud sql instances patch bank-postgres   --authorized-networks=${MY_IP}/32   --project=alpine-anvil-473102-c4
gcloud sql connect bank-postgres --user=bankuser --quiet --database=bankdb
# then paste SQL
gcloud sql connect bank-postgres --user=bankuser --quiet --database=bankdb
# then paste SQL
gcloud sql connect bank-postgres --user=bankuser --quiet --database=bankdb
gcloud artifacts repositories create bank-repo --repository-format=docker --location=northamerica-northeast1
IMAGE="northamerica-northeast1-docker.pkg.dev/alpine-anvil-473102-c4/bank-repo/bank-app:v1"
docker build -t $IMAGE .
gcloud auth configure-docker northamerica-northeast1-docker.pkg.dev
docker push $IMAGE
gcloud sql instances describe bank-postgres --format='value(ipAddresses.ipAddress)'
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl get pods
kubectl get svc
kubectl get ingress
cd bank-app
ls
cd banking-app
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl get pods
kubectl get svc
kubectl get ingress
kubectl apply -f k8s/manage-cert.yaml
kubectl get ingress
kubectl get svc
kubectl get pods
kubectl apply -f k8s/deployment.yaml
gcloud container clusters delete bank-gke-cluster --region=northamerica-northeast1 --quiet
gcloud sql instances delete bank-postgres --quiet
gcloud redis instances delete bank-redis --region=northamerica-northeast1 --quiet
gcloud artifacts repositories delete bank-repo --location=northamerica-northeast1 --quiet
gcloud compute networks delete gke-vpc --quiet
kubectl get pods
kubectl get all
gcloud container clisters list
helm create hello-chart
helm package hello-chart/
gcloud container clusters create my-gke-cluster --zone=us-central1-a
ls
helm install my-app-release hello-chart-0.1.0.tgz
helm install my-app-release ./hello-chart/
helm install my-app-release ./hello-chart/ --set image.tag=latest
kubectl get pods,svc
helm upgrade my-app-release ./hello-chart/
helm -help
helm --help
helm uninstall my-app-release
kubectl get all
gcloud container cluster delete my-gke-cluster
gcloud container clusters delete my-gke-cluster
gcloud container clusters delete my-gke-cluster --zone=us-central1-a
gcloud services enable container.googleapis.com artifactregistry.googleapis.com
gcloud auth login
gcloud config set project alpine-anvil-473102-c4
gcloud services enable container.googleapis.com artifactregistry.googleapis.com
gcloud container clusters create hello-cluster   --zone=us-central1-a   --num-nodes=1   --project=$PROJECT_ID
gcloud container clusters create hello-cluster   --zone=us-central1-a   --num-nodes=1 
gcloud container clusters get-credentials hello-cluster --zone us-central1-a 
export $PROJECT_ID=alpine-anvil-473102-c4
export $PROJECT_ID alpine-anvil-473102-c4
export PROJECT_ID=alpine-anvil-473102-c4
gcloud artifacts repositories create hello-repo   --repository-format=docker   --location=us-central1   --description="Hello World demo"
cd /day1of7
ls
cd day1of7
gcloud auth configure-docker us-central1-docker.pkg.dev
docker build -t us-central1-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v1 .
docker push us-central1-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v1
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl get pods
kubectl get svc hello-service
kubectl apply -f deployment.yaml
kubectl get pods
kubectl get svc hello-service
kubectl scale deployment hello-deployment --replicas=5
kubectl logs -l app=hello
kubectl top pods
git config --global user.name "gandinehru35-spec"
git config --global user.email "gandinehru35@gmail.com"
mkdir k8s-hello-world-gke
cd k8s-hello-world-gke
mkdir app k8s
# Add app.py, Dockerfile to app/; deployment.yaml, service.yaml to k8s/
nano README.md   # Write your documentation here
cat README.md
git init
ls
cd day1of7
ls
git init
git add .
git commit -m "Initial commit: Day 1 Hello World GKE Project!"
# Add your remote repo URL (replace YOUR_GITHUB_USERNAME)
git remote add origin https://github.com/gandinehru35-spec/k8s-hello-world-gke.git
# Push local code to GitHub
git push -u origin master   # Or main if branch is main
git remote add origin https://github.com/gandinehru35-spec/k8s-hello-world-gke.git
git branch -M main
git push -u origin main
git --version
git remote add origin https://github.com/gandinehru35-spec/k8s-hello-world-gke.git
git push -u origin master   # Or main if branch is main
git push -u origin main   # Or main if branch is main
cd 
cd day1of7
ls
cd k8s-hello-world-gke
git push -u origin main   # Or main if branch is main
kubectl get pofs
kubectl get pods
cd day1of7
ls
docker build -t us-central-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v2 .
export PROJECT_ID=	alpine-anvil-473102-c4
export PROJECT_ID=alpine-anvil-473102-c4
docker build -t us-central-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v2 .
docker push us-central-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v2
gcloud auth login 
gcloud auth configure-docker
docker push us-central-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v2
docker push us-central1-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v2
docker build -t us-central-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v2 .
docker push us-central1-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v2
docker build -t us-central1-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v2 .
docker push us-central1-docker.pkg.dev/$PROJECT_ID/hello-repo/hello-app:v2
kubectl apply -f deployment.yam
kubectl apply -f deployment.yaml
kubectl rollout status hello-deployment
kubectl rollout status deployment/hello-deployment
kubectl rollout history deployment/hello-deployment
kubectl get pods
kubectl apply -f deployment.yaml
kubectl rollout status deployment/hello-deployment
kubectl get all
kubectl rollout status deployment/hello-deployment
kubectl get all
kubectl rollout status deployment/hello-deployment
kubectl rollout history deployment/hello-deployment
kubectl delete pod pod/hello-deployment-55c6f6564f-bb8gx
kubectl delete pod hello-deployment-55c6f6564f-bb8gx
kubectl get all
kubectl describe pod hello-deployment-55c6f6564f-wcpbn
kubectl get node
kubectl top node 
kubectl top pod
kubectl apply -f deployment.yaml
kubectl get all
kubectl apply -f deployment.yaml
kubectl get all
kubectl delete pod -a
kubectl delete pod -A
kubectl delete pod --A
kubectl delete pod hello-deployment-55c6f6564f-h9fhs
kubectl delete pod hello-deployment-55c6f6564f-pbfql
kubectl get pods
kubectl rollout status deployment/hello-deployment
kubectl rollout history deployment/hello-deployment
kubectl get all
kubectl top node
kubectl top pod
ls
kubectl apply -f hpa.yaml
kubectl get hpa
kubectl get pods
kubectl get all
kubectl run -i --tty load-generator --image=busybox /bin/sh
# Inside the pod, run a traffic generator:
while true; do wget -q -O- http://hello-service; done
kubectl get hpa -w
kubectl delete hpa hello-hpa
kubectl get all
kubectl delete pod load-balancer
kubectl delete pod load
kubectl delete pod load-generator
