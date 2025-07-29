import sqlite3
from config import config

def init_db():
    conn = sqlite3.connect(config.DB_NAME)
    cur = conn.cursor()
    cur.execute('''
        CREATE TABLE IF NOT EXISTS users (
            telegram_id INTEGER PRIMARY KEY,
            username TEXT,
            balance REAL DEFAULT 0
        )
    ''')
    cur.execute('''
        CREATE TABLE IF NOT EXISTS payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            telegram_id INTEGER,
            amount REAL,
            status TEXT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()

def add_user(telegram_id, username):
    conn = sqlite3.connect(config.DB_NAME)
    cur = conn.cursor()
    cur.execute("INSERT OR IGNORE INTO users (telegram_id, username) VALUES (?, ?)", (telegram_id, username))
    conn.commit()
    conn.close()

def log_payment(telegram_id, amount, status="pending"):
    conn = sqlite3.connect(config.DB_NAME)
    cur = conn.cursor()
    cur.execute("INSERT INTO payments (telegram_id, amount, status) VALUES (?, ?, ?)", (telegram_id, amount, status))
    conn.commit()
    conn.close()
