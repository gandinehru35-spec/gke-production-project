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
