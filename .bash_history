          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 5Gi # Request 5GB of persistent disk
EOT

echo "Creating k8s/04-app-deployment.yaml..."
cat << 'EOT' > k8s/04-app-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app
  namespace: prod
  labels:
    app: hello-app
spec:
  replicas: 2 # Start with 2 replicas
  selector:
    matchLabels:
      app: hello-app
  template:
    metadata:
      labels:
        app: hello-app # Label for service and network policy
    spec:
      containers:
      - name: hello-app
        image: us-central1-docker.pkg.dev/alpine-anvil-473102-c4/hello-repo/hello-app:v1
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: "postgres" # The name of the database service
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_PASSWORD
        resources:
          # Required for HPA to work
          requests:
            cpu: "100m" # Request 0.1 vCPU
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
EOT

echo "Creating k8s/05-app-service.yaml..."
cat << 'EOT' > k8s/05-app-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-app-svc
  namespace: prod
spec:
  type: ClusterIP # Internal service only
  selector:
    app: hello-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
EOT

echo "Creating k8s/06-managed-cert.yaml..."
cat << 'EOT' > k8s/06-managed-cert.yaml
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: hello-app-cert
  namespace: prod
spec:
  domains:
    - www.glamournest.store
EOT

echo "Creating k8s/07-ingress.yaml..."
cat << 'EOT' > k8s/07-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-app-ingress
  namespace: prod
  annotations:
    # Use the GKE-managed certificate
    networking.gke.io/managed-certificates: "hello-app-cert"
    # Use the GKE Ingress controller
    kubernetes.io/ingress.class: "gce"
spec:
  rules:
  - host: www.glamournest.store
    http:
      paths:
      - path: /*
        pathType: ImplementationSpecific
        backend:
          service:
            name: hello-app-svc
            port:
              number: 80
EOT

echo "Creating k8s/08-hpa.yaml..."
cat << 'EOT' > k8s/08-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hello-app-hpa
  namespace: prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hello-app
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50 # Target 50% CPU utilization
EOT

echo "Creating k8s/09-rbac-role.yaml..."
cat << 'EOT' > k8s/09-rbac-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: prod-reader
  namespace: prod
rules:
- apiGroups: ["", "apps", "autoscaling", "networking.k8s.io"]
  resources: ["pods", "deployments", "services", "ingresses", "hpas", "networkpolicies"]
  verbs: ["get", "list", "watch"]
EOT

echo "Creating k8s/10-rbac-rolebinding.yaml..."
cat << 'EOT' > k8s/10-rbac-rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: bind-prod-reader
  namespace: prod
subjects:
- kind: User
  name: gandinehru35@gmail.com
roleRef:
  kind: Role
  name: prod-reader
  apiGroup: rbac.authorization.k8s.io
EOT

echo "Creating k8s/11-netpol-db.yaml..."
cat << 'EOT' > k8s/11-netpol-db.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-to-db
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: postgres # This policy applies to the database pod
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: hello-app # ONLY allow traffic from the app pods
    ports:
    - protocol: TCP
      port: 5432 # To the postgres port
EOT

echo "Creating k8s/12-netpol-app.yaml..."
cat << 'EOT' > k8s/12-netpol-app.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-app
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: hello-app # This policy applies to the app pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    # This magic block allows traffic from the GKE Ingress/Health Checkers
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-gce
    # This allows traffic from the Prometheus in the 'monitoring' namespace
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    ports:
    - protocol: TCP
      port: 8080 # To the app's container port
EOT

echo "Creating k8s/13-prometheus-values.yaml..."
cat << 'EOT' > k8s/13-prometheus-values.yaml
# This file overrides the defaults of the kube-prometheus-stack Helm chart
grafana:
  persistence:
    enabled: true
    type: pvc
    size: 10Gi
    # GKE's default StorageClass will be used
EOT

echo "Creating .github/workflows/gke-deploy.yaml..."
cat << 'EOT' > .github/workflows/gke-deploy.yaml
# This file goes in your .github/workflows/ directory in your Git repo

name: Build and Deploy to GKE

on:
  push:
    branches:
      - main # Trigger on push to main branch

env:
  PROJECT_ID: alpine-anvil-473102-c4
  GKE_CLUSTER: hello-cluster
  GKE_ZONE: us-central1-a
  IMAGE_REPO: hello-repo
  IMAGE_NAME: hello-app
  K8S_DIR: k8s

jobs:
  build-and-deploy:
    name: Build and Deploy
    runs-on: ubuntu-latest

    steps:
    - name: Checkout
      uses: actions/checkout@v3

    # Authenticate to Google Cloud
    - id: 'auth'
      uses: 'google-github-actions/auth@v1'
      with:
        # --- IMPORTANT ---
        # Create a 'GCP_SA_KEY' secret in your GitHub repo settings
        credentials_json: '${{ secrets.GCP_SA_KEY }}'

    # Set up GKE credentials
    - name: Get GKE credentials
      uses: google-github-actions/get-gke-credentials@v1
      with:
        cluster_name: ${{ env.GKE_CLUSTER }}
        location: ${{ env.GKE_ZONE }}

    # Configure Docker
    - name: Configure Docker
      run: gcloud auth configure-docker us-central1-docker.pkg.dev

    # Build and push Docker image
    - name: Build and Push
      run: |
        export IMAGE_PATH="us-central1-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.IMAGE_REPO }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
        
        # Build and push
        docker build -t $IMAGE_PATH ./app
        docker push $IMAGE_PATH
        
        # --- IMPORTANT ---
        # This step updates the k8s/04-app-deployment.yaml file 
        # with the new image tag before applying
        sed -i "s|image:.*|image: $IMAGE_PATH|g" ${{ env.K8S_DIR }}/04-app-deployment.yaml

    # Deploy to GKE
    - name: Deploy
      run: |
        # Apply all manifests
        # The 'apply' command is idempotent
        kubectl apply -f ${{ env.K8S_DIR }}/
EOT

echo ""
echo "All files created successfully with your specific values!"
echo "Run 'chmod +x create_all_files.sh' to make it executable."
echo "Run './create_all_files.sh' to create all project files."

EOF

ls
cd ~
ls
chmod +x create_all_files.sh
./create_all_files.sh
ls
./create_all_files.sh
ls
cd k8s
ls
kubectl apply -f k8s/00-namespaces.yaml
cd ~
kubectl apply -f k8s/00-namespaces.yaml
kubectl get namespace
# Configure Docker to authenticate with Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev
# Define the image tag
export IMAGE_TAG="us-central1-docker.pkg.dev/${PROJECT_ID}/hello-repo/hello-app:v1"
# Build the image
docker build -t $IMAGE_TAG ./app
# Push the image
docker push $IMAGE_TAG
echo "Applying database secret..."
kubectl apply -f k8s/01-db-secret.yaml
echo "Applying database service..."
kubectl apply -f k8s/02-db-service.yaml
echo "Applying database statefulset..."
kubectl apply -f k8s/03-db-statefulset.yaml
kubectl get pods -n prod -l app=postgres
# You should see 'postgres-0' in 'Running' state
kubectl get pvc -n prod -l app=postgres
# You should see 'data-postgres-0' in 'Bound' state
echo "Applying application deployment..."
kubectl apply -f k8s/04-app-deployment.yaml
kubectl apply -f k8s/05-app-service.yaml
echo "Applying managed certificate..."
kubectl apply -f k8s/06-managed-cert.yaml
echo "Applying ingress..."
kubectl apply -f k8s/07-ingress.yaml
kubectl get ingress -n prod -w
# Wait for the 'ADDRESS' column to show an IP address.
# Once you have the IP, update your domain's 'A' record to point to it.
kubectl get ingress -n prod -w
echo "Applying Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
echo "Applying HPA..."
kubectl apply -f k8s/08-hpa.yaml
kubectl get hpa -n prod
# You should see 'hello-app-hpa'. The 'TARGETS' column may show '<unknown>/50%' 
# for a few minutes until Metrics Server is fully operational.
kubectl get ingress -n prod -w
echo "Applying read-only RBAC role..."
kubectl apply -f k8s/09-rbac-role.yaml
echo "Applying read-only RBAC role binding..."
kubectl apply -f k8s/10-rbac-rolebinding.yaml
echo "Applying database network policy..."
kubectl apply -f k8s/11-netpol-db.yaml
echo "Applying application network policy..."
kubectl apply -f k8s/12-netpol-app.yaml
helm install prometheus prometheus-community/kube-prometheus-stack     --namespace monitoring     --values k8s/13-prometheus-values.yaml
# Get the auto-generated Grafana admin password
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
# Forward the Grafana port to your local machine
echo "Access Grafana at http://localhost:8080"
kubectl port-forward -n monitoring svc/prometheus-grafana 8080:80
# Get the auto-generated Grafana admin password
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
# Forward the Grafana port to your local machine
echo "Access Grafana at http://localhost:8080"
kubectl port-forward -n monitoring svc/prometheus-grafana 8080:80
kubectl get all -n monitoring
kubectl port-forward -n monitoring svc/prometheus-grafana 8080:80
# Get the auto-generated Grafana admin password
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
# Forward the Grafana port to your local machine
echo "Access Grafana at http://localhost:8080"
kubectl port-forward -n monitoring svc/prometheus-grafana 8080:80
kubectl describe svc prometheus-grafana -n monitoring
kubectl port-forward -n monitoring svc/prometheus-grafana 8000:80
kubectl port-forward -n monitoring svc/prometheus-grafana 9000:80
kubectl get ingress -n prod -w
kubectl gel all -n prod
kubectl get all -n prod
kubectl get ingress -n prod -w
kubectl get pods -n prod
kubectl logs -n prod hello-app-7dc49948f5-5q66q
clear
kubectl exec -it -n prod hello-app-7dc49948f5-5q66q -- /bin/sh
gcloud auth login 
gcloud config set project alpine-anvil-473102-c4
cd
ls
kubectl get pods
kubectl get pods -n prod
kubectl exec -it -n prod hello-app-7dc49948f5-5q66q -- /bin/sh
kubectl exec -it -n prod -- /bin/sh
kubectl exec -it -n prod postgres-0 -- /bin/sh
kubectl delete pod postgres-0 -n prod
kubectl get pods -n prod -o wide
kubectl exec -n prod -it postgres-0 -- /bin/sh
clear
kubectl get managedcertificate -n prod hello-app-cert
kubectl get all -n prod -o wide
kubectl get managedcertificate -n prod hello-app-cert -o wide
kubectl get ingress -n prod -w
kubectl delete  managedcertificate -n prod hello-app-cert
kubectl apply -f echo "Applying managed certificate..."
kubectl apply -f k8s/06-managed-cert.yaml
kubectl get ingress -n prod -w
kubectl delete ingress
kubectl delete ingress hello-app-ingress
kubectl delete ingress hello-app-ingress -n prod
kubectl apply -f k8s/07-ingress.yaml
kubectl get ingress -n prod -w
clear
kubectl get ingress -n prod -w
kubectl get managedcertificate -n prod hello-app-cert -o wide
kubectl get all -n prod
kubectl get managedcertificate -n prod hello-app-cert -o wide
kubectl get ingress -n prod -w
kubectl describe ingress -n prod -w
kubectl describe ingress -n prod
kubectl describe svc prod/hello-app-svc
kubectl describe svc hello-app-svc -n prod
kubectl apply -f k8s/05-app-service.yaml
kubectl describe ingress -n prod
kubectl apply -f k8s/07-ingress.yaml
kubectl describe ingress -n prod
kubectl describe managedcertificate -n prod
kubectl get ingress -n prod -w
kubectl describe ingress -n prod
clear
kubectl describe ingress -n prod
kubectl get ingress -n prod -w
kubectl describe ingress -n prod
kubectl describe managedcertificate -n prod
kubectl describe ingress -n prod
kubectl run -n prod -it --rm load-generator --image=busybox -- /bin/sh
kubectl get all -n prod
kubectl describe svc hello-app-svc -n prod
kubectl describe pod hello-app
kubectl describe pod hello-app-7dc49948f5-5q66q
kubectl describe pods hello-app-7dc49948f5-mkjmg
kubectl describe pods hello-app-7dc49948f5-mkjmg -n prod
kubectl run -n prod -it --rm load-generator --image=busybox -- /bin/sh
kubectl describe ingress -n prod
kubectl describe managedcertificate -n prod
kubectl --as=gandinehru35@gmail.com get pods -n prod
kubectl --as=gandinehru35@gmail.com delete pod <app-pod-name-here> -n prod
kubectl --as=gandinehru35@gmail.com delete pod hello-app-7dc49948f5-5q66q -n prod
# This will refresh every 2 seconds
watch 'kubectl get hpa -n prod ; echo ; kubectl get pods -n prod -l app=hello-app'
kubectl apply -f k8s/12-netpol-app.yaml
cd k8s
ls
kubectl apply -f .
cd ~
kubectl run -n prod -it --rm load-generator --image=busybox -- /bin/sh
kubectl get ingress -n prod hello-app-ingress
# NAME                CLASS   HOSTS                   ADDRESS         PORTS     AGE
# hello-app-ingress   gce     www.glamournest.store   34.XXX.XXX.XXX   80, 443   7h
nslookup www.glamournest.store
kubectl get pods -n prod
kubectl describe pod hello-app-7dc49948f5-5q66q
kubectl describe pod hello-app-7dc49948f5-5q66q -n pord
kubectl describe pod hello-app-7dc49948f5-5q66q -n prod
kubectl apply -f k8s/12-netpol-app.yaml
kubectl run -n prod -it --rm load-generator --image=busybox -- /bin/sh
kubectl delete pod load-generator -n prod
clear
kubectl run -n prod -it --rm load-generator --image=busybox -- /bin/sh
cd k8s
kubectl apply -f .
cd !
cd ~
clear
kubectl get pods -n prod
kubectl get ingress -n prod -w
kubectl run -n prod -it --rm load-generator --image=busybox -- /bin/sh
kubectl get ingress -n prod -w
kubectl describe ingress hello-app-ingress -n prod
kubectl get pods -n prod -w
kubectl describe pod -n prod hello-app-7dc49948f5-5q66q
kubectl apply -f k8s/12-netpol-app.yaml
gcloud config set project	alpine-anvil-473102-c4
gcloud projects list
gcloud config set project 1039471930533
kubectl get ingress -n prod -w
kubectl describe ingress hello-app-ingress -n prod
cat << 'EOF' > k8s/05-app-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-app-svc
  namespace: prod
  # Add an annotation GKE needs for NodePort services
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
spec:
  # --- THIS IS THE FIX ---
  # Change type from ClusterIP to NodePort
  type: NodePort
  selector:
    app: hello-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
EOF

cat << 'EOF' > k8s/12-netpol-app.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-app
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: hello-app # This policy applies to the app pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    # Allows traffic from the GKE Ingress/Health Checkers
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-gce
    # Allows traffic from Prometheus
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    # --- THIS IS THE FIX ---
    # Allows traffic from other pods in the 'prod' namespace
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: prod
    ports:
    - protocol: TCP
      port: 8080 # To the app's container port
EOF

kubectl apply -f k8s/05-app-service.yaml
kubectl apply -f k8s/12-netpol-app.yaml
kubectl describe ingress hello-app-ingress -n prod
kubectl get ingress -n prod -w
kubectl describe ingress hello-app-ingress -n prod
clear
kubectl describe ingress hello-app-ingress -n prod
kubectl get pod -n prod
kubectl get all -n prod
kubectl describe svc hello-app-svc
kubectl describe svc hello-app-svc -n prod
kubectl describe ingress hello-app-ingress -n prod
nslookup www.glamournest.store
kubectl get managedcertificate -n prod hello-app-cert
kubectl delete managedcertificate hello-app-cert -n prod
kubectl applu -f 06-managed-cert.yaml
kubectl apply -f 06-managed-cert.yaml
kubectl apply -f k8s/06-managed-cert.yaml
kubectl get managedcertificate -n prod hello-app-cert
kubectl describe svc hello-app-svc -n prod
kubectl describe ingress hello-app-ingress -n prod
kubectl describe svc hello-app-svc -n prod
kubectl get managedcertificate -n prod hello-app-cert
kubectl describe ingress hello-app-ingress -n prod
clear
kubectl describe ingress hello-app-ingress -n prod
clear
kubectl describe ingress hello-app-ingress -n prod
kubectl get managedcertificate -n prod hello-app-cert
kubectl describe ingress hello-app-ingress -n prod
cd k8s
ls
kubectl delete ingress hello-app-ingress -n prod
kubectl describe ingress hello-app-ingress -n prod
kubectl apply -f 07-ingress.yaml
kubectl describe ingress hello-app-ingress -n prod
kubectl apply -f 07-ingress.yaml
kubectl get managedcertificate -n prod hello-app-cert
kubectl describe ingress hello-app-ingress -n prod
kubectl describe get hello-app-ingress -n prod
kubectl get ingress hello-app-ingress -n prod
kubectl describe get hello-app-ingress -n prod
kubectl describe ingress hello-app-ingress -n prod
nslookup www.glamournest.store
kubectl get managedcertificate -n prod
kubectl describe ingress hello-app-ingress -n prod
cat << 'EOF' > k8s/12-netpol-app.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-app
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: hello-app # This policy applies to the app pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    # --- FIX 1 ---
    # This block allows traffic from the GKE Ingress/Health Checkers
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-gce
    # This allows traffic from the Prometheus in the 'monitoring' namespace
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    # --- FIX 2 ---
    # This allows traffic from ANY pod in our own 'prod' namespace.
    # This will allow our 'load-generator' pod to work.
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: prod
    ports:
    - protocol: TCP
      port: 8080 # To the app's container port
EOF

cd ~
cat << 'EOF' > k8s/12-netpol-app.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-app
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: hello-app # This policy applies to the app pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    # --- FIX 1 ---
    # This block allows traffic from the GKE Ingress/Health Checkers
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-gce
    # This allows traffic from the Prometheus in the 'monitoring' namespace
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    # --- FIX 2 ---
    # This allows traffic from ANY pod in our own 'prod' namespace.
    # This will allow our 'load-generator' pod to work.
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: prod
    ports:
    - protocol: TCP
      port: 8080 # To the app's container port
EOF

kubectl apply -f k8s/12-netpol-app.yaml
kubectl describe ingress hello-app-ingress -n prod
kubectl logs -n prod
kubectl logs -h
kubectl describe ingress hello-app-ingress -n prod
kubectl logs k8s1-30ec42b8-prod-hello-app-svc-80-28ae699b
kubectl logs k8s1-30ec42b8-prod-hello-app-svc-80-28ae699b -n prod
kubectl logs svc k8s1-30ec42b8-prod-hello-app-svc-80-28ae699b -n prod
kubectl describe svc k8s1-30ec42b8-prod-hello-app-svc-80-28ae699b -n prod
cat << 'EOF' > k8s/12-netpol-app.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-app
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: hello-app # This policy applies to the app pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    # --- FIX 1 ---
    # This block allows traffic from the GKE Ingress/Health Checkers
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: ingress-gce
    # This allows traffic from the Prometheus in the 'monitoring' namespace
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    # --- FIX 2 ---
    # This allows traffic from ANY pod in our own 'prod' namespace.
    # This will allow our 'load-generator' pod to work.
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: prod
    ports:
    - protocol: TCP
      port: 8080 # To the app's container port
EOF

kubectl apply -f k8s/12-netpol-app.yaml
kubectl describe ingress hello-app-ingress -n prod
cat << 'EOF' > k8s/12-netpol-app.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-to-app
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: hello-app # This policy applies to the app pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    # --- FIX 1 (The REAL fix) ---
    # This block allows traffic from the GKE Ingress/Health Checkers
    # by their specific IP ranges.
    - ipBlock:
        cidr: 130.211.0.0/22
    - ipBlock:
        cidr: 35.191.0.0/16
    # This allows traffic from the Prometheus in the 'monitoring' namespace
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    # --- FIX 2 (For your load test) ---
    # This allows traffic from ANY pod in our own 'prod' namespace.
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: prod
    ports:
    - protocol: TCP
      port: 8080 # To the app's container port
EOF

kubectl apply -f k8s/12-netpol-app.yaml
kubectl describe ingress hello-app-ingress -n prod
clear
kubectl get all -prod 
kubectl get all -n prod 
kubectl describe svc hello-app-svc -n prod
kubectl describe ingress hello-app-ingress -n prod
clear
kubectl describe ingress hello-app-ingress -n prod
kubectl get managedcertificate -n prod
kubectl describe ingress hello-app-ingress -n prod
curl -k https://34.8.72.162
kubectl describe ingress hello-app-ingress -n prod
curl -k https://34.8.72.162
cat << 'EOF' > k8s/14-app-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-metrics-reader
  namespace: prod
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-metrics-reader
  namespace: prod
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: bind-app-metrics-reader
  namespace: prod
subjects:
- kind: ServiceAccount
  name: app-metrics-reader
  namespace: prod
roleRef:
  kind: Role
  name: pod-metrics-reader
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f k8s/14-app-rbac.yaml
# This command appends the new line to the file
echo "kubernetes" >> app/requirements.txt
cat << 'EOF' > app/app.py
import os
import psycopg2
from flask import Flask, jsonify
from kubernetes import client, config

app = Flask(__name__)

# --- New Kubernetes API Setup ---
try:
    # Load in-cluster configuration
    config.load_incluster_config()
    
    # Create API clients
    v1 = client.CoreV1Api()
    metrics_api = client.CustomObjectsApi()
    
    app.logger.info("Successfully loaded in-cluster K8s config.")
except Exception as e:
    app.logger.error(f"Could not load in-cluster K8s config: {e}")
    v1 = None
    metrics_api = None
# --- End of New Setup ---


def get_db_connection():
    """Establishes a connection to the PostgreSQL database."""
    try:
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST', 'postgres'),
            database=os.environ.get('DB_NAME', 'postgres'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD')
        )
        return conn
    except Exception as e:
        app.logger.error(f"Error connecting to database: {e}")
        return None

@app.route('/')
def hello():
    """Returns a simple hello message."""
    return jsonify(message="Hello from Kubernetes!")

@app.route('/health')
def health_check():
    """Performs a health check on the app and database connection."""
    conn = None
    try:
        conn = get_db_connection()
        if conn:
            conn.close()
            db_status = "connected"
            status_code = 200
        else:
            db_status = "disconnected"
            status_code = 500

        return jsonify(status="ok", database=db_status), status_code

    except Exception as e:
        return jsonify(status="error", message=str(e)), 500
    finally:
        if conn:
            conn.close()

# --- New Metrics Endpoint ---
@app.route('/metrics')
def get_pod_metrics():
    """Fetches and displays pod metrics for the 'prod' namespace."""
    if not v1 or not metrics_api:
        return jsonify(error="K8s API client not initialized"), 500

    try:
        # 1. Get Pod Metrics (CPU/Memory)
        metrics = metrics_api.list_namespaced_custom_object(
            group="metrics.k8s.io",
            version="v1beta1",
            namespace="prod",
            plural="pods"
        )
        
        pod_metrics = {}
        for item in metrics['items']:
            pod_name = item['metadata']['name']
            usage = item['containers'][0]['usage']
            pod_metrics[pod_name] = {
                'cpu': usage.get('cpu', '0'),
                'memory': usage.get('memory', '0')
            }

        # 2. Get Pod Status (Running, Pending, etc.)
        pods = v1.list_namespaced_pod(namespace="prod")
        
        pod_data = []
        for pod in pods.items:
            pod_name = pod.metadata.name
            pod_data.append({
                'name': pod_name,
                'status': pod.status.phase,
                'node': pod.spec.node_name,
                'metrics': pod_metrics.get(pod_name, 'Not Available')
            })

        return jsonify(
            namespace="prod",
            pod_count=len(pod_data),
            pods=pod_data
        )

    except Exception as e:
        app.logger.error(f"Error fetching K8s metrics: {e}")
        return jsonify(error=str(e)), 500
# --- End of New Endpoint ---

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=8080)
EOF

cat << 'EOF' > k8s/04-app-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app
  namespace: prod
  labels:
    app: hello-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello-app
  template:
    metadata:
      labels:
        app: hello-app
    spec:
      # --- THIS IS THE CHANGE ---
      # Tell the pod to use the ServiceAccount we created
      serviceAccountName: app-metrics-reader
      # --- END OF CHANGE ---
      containers:
      - name: hello-app
        # We will build and push this v2 image next
        image: us-central1-docker.pkg.dev/alpine-anvil-473102-c4/hello-repo/hello-app:v2
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: "postgres"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_PASSWORD
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
EOF

docker build -t us-central1-docker.pkg.dev/alpine-anvil-473102-c4/hello-repo/hello-app:v2 ./app
docker push us-central1-docker.pkg.dev/alpine-anvil-473102-c4/hello-repo/hello-app:v2
kubectl apply -f k8s/04-app-deployment.yaml
kubectl getl all -n prod
kubectl get all -n prod
kubectl get all -n prod -w
kubectl get all -n prod -o wide
kubectl describe ingress hello-app-ingress -n prod
clear
mkdir -p app/templates
cat << 'EOF' > app/templates/dashboard.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GKE Cluster Dashboard (prod)</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: #f4f7f6;
            color: #333;
            margin: 0;
            padding: 20px;
        }
        h1 {
            color: #1a73e8;
            border-bottom: 2px solid #ddd;
            padding-bottom: 10px;
        }
        #dashboard {
            background-color: #fff;
            border-radius: 8px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.05);
            overflow: hidden;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 12px 16px;
            text-align: left;
            border-bottom: 1px solid #eee;
        }
        th {
            background-color: #f9f9f9;
            font-weight: 600;
        }
        tr:last-child td {
            border-bottom: none;
        }
        .status-running { color: #34a853; font-weight: bold; }
        .status-pending { color: #fbbc05; font-weight: bold; }
        .status-failed { color: #ea4335; font-weight: bold; }
        .bar-container {
            width: 100px;
            height: 16px;
            background-color: #e0e0e0;
            border-radius: 4px;
            overflow: hidden;
        }
        .bar {
            height: 100%;
            background-color: #4285f4;
            border-radius: 4px 0 0 4px;
            transition: width 0.3s ease-in-out;
        }
        .bar-memory { background-color: #34a853; }
        .metrics-value {
            font-size: 0.9em;
            color: #555;
            min-width: 60px;
            display: inline-block;
        }
        #summary {
            font-size: 1.2em;
            margin-bottom: 20px;
        }
        #summary span {
            font-weight: bold;
            color: #1a73e8;
        }
    </style>
</head>
<body>

    <h1>GKE Cluster Dashboard</h1>
    <div id="summary">
        Namespace: <strong>prod</strong> | Pod Count: <span id="pod-count">...</span>
    </div>

    <div id="dashboard">
        <table>
            <thead>
                <tr>
                    <th>Pod Name</th>
                    <th>Status</th>
                    <th>Node</th>
                    <th>CPU Usage</th>
                    <th>Memory Usage</th>
                </tr>
            </thead>
            <tbody id="pod-table-body">
                </tbody>
        </table>
    </div>

    <script>
        // Helper function to parse CPU values like "1000m" (millicores) or "10n" (nanocores)
        function parseCpu(cpuStr) {
            if (!cpuStr) return 0;
            if (cpuStr.endsWith('m')) {
                return parseFloat(cpuStr) / 1000; // Convert millicores to cores
            }
            if (cpuStr.endsWith('n')) {
                return parseFloat(cpuStr) / 1000000000; // Convert nanocores to cores
            }
            return parseFloat(cpuStr);
        }

        // Helper function to parse Memory values like "100Mi" or "10Gi"
        function parseMemory(memStr) {
            if (!memStr) return 0;
            if (memStr.endsWith('Ki')) {
                return parseFloat(memStr) * 1024;
            }
            if (memStr.endsWith('Mi')) {
                return parseFloat(memStr) * 1024 * 1024;
            }
            if (memStr.endsWith('Gi')) {
                return parseFloat(memStr) * 1024 * 1024 * 1024;
            }
            return parseFloat(memStr);
        }

        // Main function to fetch and render data
        async function updateDashboard() {
            try {
                const response = await fetch('/metrics');
                const data = await response.json();
                
                // Update summary
                document.getElementById('pod-count').textContent = data.pod_count || 0;

                // Update table
                const tableBody = document.getElementById('pod-table-body');
                tableBody.innerHTML = ''; // Clear old data

                data.pods.forEach(pod => {
                    const row = document.createElement('tr');
                    
                    let metrics = pod.metrics;
                    let cpuUsage = 0;
                    let memUsage = 0;
                    let cpuText = "0m";
                    let memText = "0Mi";

                    if (metrics && metrics.cpu) {
                        cpuUsage = parseCpu(metrics.cpu);
                        cpuText = metrics.cpu;
                    }
                    if (metrics && metrics.memory) {
                        memUsage = parseMemory(metrics.memory);
                        memText = metrics.memory;
                    }

                    // --- Create Simple Bar Graphs ---
                    // Assuming 1 core (1000m) is 100% for CPU
                    const cpuPercent = (cpuUsage / 1) * 100; 
                    // Assuming 256Mi is 100% for Memory (based on our limit)
                    const memPercent = (memUsage / (256 * 1024 * 1024)) * 100;

                    row.innerHTML = `
                        <td>${pod.name}</td>
                        <td class="status-${pod.status.toLowerCase()}">${pod.status}</td>
                        <td>${pod.node || 'N/A'}</td>
                        <td>
                            <span class="metrics-value">${cpuText}</span>
                            <div class="bar-container">
                                <div class="bar bar-cpu" style="width: ${cpuPercent.toFixed(2)}%;"></div>
                            </div>
                        </td>
                        <td>
                            <span class="metrics-value">${memText}</span>
                            <div class="bar-container">
                                <div class="bar bar-memory" style="width: ${memPercent.toFixed(2)}%;"></div>
                            </div>
                        </td>
                    `;
                    tableBody.appendChild(row);
                });

            } catch (error) {
                console.error('Error fetching dashboard data:', error);
                const tableBody = document.getElementById('pod-table-body');
                tableBody.innerHTML = '<tr><td colspan="5" style="color: red; text-align: center;">Error loading data. Is the /metrics endpoint running?</td></tr>';
            }
        }

        // Run the function now and then every 2 seconds
        updateDashboard();
        setInterval(updateDashboard, 2000); 
    </script>
</body>
</html>
EOF

cat << 'EOF' > app/app.py
import os
import psycopg2
from flask import Flask, jsonify, render_template, redirect, url_for
from kubernetes import client, config

app = Flask(__name__)

# --- Kubernetes API Setup ---
try:
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    metrics_api = client.CustomObjectsApi()
    app.logger.info("Successfully loaded in-cluster K8s config.")
except Exception as e:
    app.logger.error(f"Could not load in-cluster K8s config: {e}")
    v1 = None
    metrics_api = None

def get_db_connection():
    """Establishes a connection to the PostgreSQL database."""
    try:
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST', 'postgres'),
            database=os.environ.get('DB_NAME', 'postgres'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD')
        )
        return conn
    except Exception as e:
        app.logger.error(f"Error connecting to database: {e}")
        return None

# --- NEW: Redirect root to our new dashboard ---
@app.route('/')
def hello():
    """Redirects to the main dashboard."""
    return redirect(url_for('dashboard'))

# --- NEW: Dashboard Route ---
@app.route('/dashboard')
def dashboard():
    """Serves the human-readable dashboard page."""
    return render_template('dashboard.html')

@app.route('/health')
def health_check():
    """Performs a health check on the app and database connection."""
    conn = None
    try:
        conn = get_db_connection()
        if conn:
            conn.close()
            db_status = "connected"
            status_code = 200
        else:
            db_status = "disconnected"
            status_code = 500
        return jsonify(status="ok", database=db_status), status_code
    except Exception as e:
        return jsonify(status="error", message=str(e)), 500
    finally:
        if conn:
            conn.close()

@app.route('/metrics')
def get_pod_metrics():
    """Fetches and displays pod metrics for the 'prod' namespace."""
    if not v1 or not metrics_api:
        return jsonify(error="K8s API client not initialized"), 500

    try:
        metrics = metrics_api.list_namespaced_custom_object(
            group="metrics.k8s.io",
            version="v1beta1",
            namespace="prod",
            plural="pods"
        )
        
        pod_metrics = {}
        for item in metrics['items']:
            pod_name = item['metadata']['name']
            if item['containers']:
                usage = item['containers'][0]['usage']
                pod_metrics[pod_name] = {
                    'cpu': usage.get('cpu', '0n'),
                    'memory': usage.get('memory', '0Ki')
                }

        pods = v1.list_namespaced_pod(namespace="prod")
        
        pod_data = []
        for pod in pods.items:
            pod_name = pod.metadata.name
            pod_data.append({
                'name': pod_name,
                'status': pod.status.phase,
                'node': pod.spec.node_name,
                'metrics': pod_metrics.get(pod_name, {'cpu': '0n', 'memory': '0Ki'})
            })

        return jsonify(
            namespace="prod",
            pod_count=len(pod_data),
            pods=pod_data
        )
    except Exception as e:
        app.logger.error(f"Error fetching K8s metrics: {e}")
        return jsonify(error=str(e)), 500

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=8080)
EOF

cat << 'EOF' > k8s/04-app-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app
  namespace: prod
  labels:
    app: hello-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello-app
  template:
    metadata:
      labels:
        app: hello-app
    spec:
      serviceAccountName: app-metrics-reader
      containers:
      - name: hello-app
        # --- Pointing to v3 ---
        image: us-central1-docker.pkg.dev/alpine-anvil-473102-c4/hello-repo/hello-app:v3
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: "postgres"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_PASSWORD
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
EOF

docker build -t us-central1-docker.pkg.dev/alpine-anvil-473102-c4/hello-repo/hello-app:v3 ./app
docker push us-central1-docker.pkg.dev/alpine-anvil-473102-c4/hello-repo/hello-app:v3
kubectl apply -f k8s/04-app-deployment.yaml
kubectl get all -n prod
kubectl apply -f k8s/08-hap.yaml
kubectl apply -f k8s/08-hpa.yaml
kubectl run -n prod -it --rm load-generator --image=busybox -- /bin/sh
ls
git config --global user.name "gandinehru35-spec"
git config --global user.email "gandinehru35@gmail.com"
git init -b main
clear
