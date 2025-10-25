cat << 'EOF' > create_all_files.sh
#!/bin/bash
# This script creates all necessary files for the 8-phase GKE project.
# Run it with: ./create_all_files.sh

set -e

echo "Creating directories..."
mkdir -p app
mkdir -p k8s
mkdir -p .github/workflows

echo "Creating app/requirements.txt..."
cat << 'EOT' > app/requirements.txt
Flask
psycopg2-binary
EOT

echo "Creating app/app.py..."
cat << 'EOT' > app/app.py
import os
import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)

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
        print(f"Error connecting to database: {e}")
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

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=8080)
EOT

echo "Creating app/Dockerfile..."
cat << 'EOT' > app/Dockerfile
# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory in the container
WORKDIR /usr/src/app

# Copy the requirements file
COPY requirements.txt ./

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code
COPY . .

# Make port 8080 available to the world outside this container
EXPOSE 8080

# Run app.py when the container launches
CMD ["python", "app.py"]
EOT

echo "Creating k8s/00-namespaces.yaml..."
cat << 'EOT' > k8s/00-namespaces.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: prod
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
EOT

echo "Creating k8s/01-db-secret.yaml..."
cat << 'EOT' > k8s/01-db-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: prod
type: Opaque
stringData:
  # Do not use these in a real production environment
  DB_USER: "postgres"
  DB_PASSWORD: "YourSuperSecretPassword123"
EOT

echo "Creating k8s/02-db-service.yaml..."
cat << 'EOT' > k8s/02-db-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: prod
  labels:
    app: postgres
spec:
  ports:
  - port: 5432
    name: postgres
  clusterIP: None # This makes it a Headless Service
  selector:
    app: postgres
EOT

echo "Creating k8s/03-db-statefulset.yaml..."
cat << 'EOT' > k8s/03-db-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: prod
spec:
  serviceName: "postgres"
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres # Label for the service and network policy
    spec:
      containers:
      - name: postgres
        image: postgres:14-alpine
        ports:
        - containerPort: 5432
          name: postgres
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: DB_PASSWORD
        - name: PGDATA
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