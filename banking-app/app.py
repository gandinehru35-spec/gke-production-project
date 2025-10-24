from flask import Flask, jsonify, request
import os
import psycopg2
import redis

app = Flask(__name__)

DB_HOST = os.getenv("DB_HOST")  # private IP of Cloud SQL or use cloud-sql-proxy if connecting locally
DB_NAME = os.getenv("DB_NAME", "bankdb")
DB_USER = os.getenv("DB_USER", "bankuser")
DB_PASS = os.getenv("DB_PASS")
REDIS_HOST = os.getenv("REDIS_HOST")

def get_db_conn():
    conn = psycopg2.connect(dbname=DB_NAME, user=DB_USER, password=DB_PASS, host=DB_HOST)
    return conn

r = None
if REDIS_HOST:
    r = redis.Redis(host=REDIS_HOST, port=6379, db=0)

@app.route("/accounts")
def accounts():
    # Try cache
    if r and r.get("accounts"):
        return jsonify({"cached": True, "data": r.get("accounts").decode()}), 200
    conn = get_db_conn()
    cur = conn.cursor()
    cur.execute("SELECT id, name, balance FROM accounts;")
    rows = cur.fetchall()
    data = [{"id": r[0], "name": r[1], "balance": float(r[2])} for r in rows]
    conn.close()
    if r:
        r.set("accounts", str(data), ex=30)
    return jsonify({"cached": False, "data": data}), 200

@app.route("/transaction", methods=["POST"])
def transaction():
    payload = request.json
    acc_id = payload["account_id"]
    amount = float(payload["amount"])
    conn = get_db_conn()
    cur = conn.cursor()
    cur.execute("UPDATE accounts SET balance = balance + %s WHERE id=%s RETURNING id, balance;", (amount, acc_id))
    res = cur.fetchone()
    conn.commit()
    conn.close()
    # invalidate cache
    if r:
        r.delete("accounts")
    return jsonify({"id": res[0], "balance": float(res[1])}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
