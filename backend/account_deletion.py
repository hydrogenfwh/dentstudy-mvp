"""Account removal, durable file cleanup, and unlinked payment reconciliation.

No live payment calls are made here. Callers must authenticate and recheck the
password while holding BEGIN IMMEDIATE before calling erase_account.
"""
import re
import hashlib
import time
import stones
from datetime import datetime, timezone


def initialize_deletion(db):
    db.executescript('''
        CREATE TABLE IF NOT EXISTS account_deletion_receipts(
          session_hash TEXT PRIMARY KEY, deletion_id TEXT NOT NULL,
          expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS account_deletion_files(
          submission_id TEXT PRIMARY KEY, deletion_id TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS account_deletion_attempts(
          user_id TEXT PRIMARY KEY REFERENCES users(id),
          attempts INTEGER NOT NULL, locked_until INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS deleted_account_role_blocks(
          address_hash TEXT PRIMARY KEY);
        CREATE TABLE IF NOT EXISTS deleted_account_tombstones(
          user_hash TEXT PRIMARY KEY, deleted_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS deleted_account_payments(
          id TEXT PRIMARY KEY, provider TEXT NOT NULL, amount_fen INTEGER NOT NULL,
          status TEXT NOT NULL, created_at TEXT NOT NULL, paid_at TEXT,
          provider_trade_no TEXT UNIQUE, refunded_at TEXT, refund_request_no TEXT,
          deleted_at TEXT NOT NULL, last_provider_status TEXT,
          last_notified_at TEXT, needs_review INTEGER NOT NULL DEFAULT 1);
    ''')
    columns = {row['name'] for row in db.execute('PRAGMA table_info(deleted_account_payments)')}
    for name in ('stone_count', 'total_fen'):
        if name not in columns:
            db.execute(f'ALTER TABLE deleted_account_payments ADD COLUMN {name} INTEGER')


def cleanup_deleted_files(db, submissions):
    """Crash-safe retry: unlink only server-issued submission basenames."""
    for row in db.execute('SELECT submission_id FROM account_deletion_files').fetchall():
        submission_id = row['submission_id']
        if not re.fullmatch(r'[A-Za-z0-9_-]{16,100}', submission_id):
            continue
        try:
            (submissions / f'{submission_id}.json').unlink(missing_ok=True)
            (submissions / f'.{submission_id}.tmp').unlink(missing_ok=True)
        except OSError:
            continue  # Durable queue is retried; never claim this file is gone.
        db.execute('DELETE FROM account_deletion_files WHERE submission_id=?',
                   (submission_id,))
    db.execute('DELETE FROM account_deletion_receipts WHERE expires<?', (int(time.time()),))
    db.commit()


def deletion_result(db, deletion_id):
    pending = db.execute('SELECT COUNT(*) FROM account_deletion_files WHERE deletion_id=?',
                         (deletion_id,)).fetchone()[0]
    return {'ok': True, 'deleted': True, 'fileCleanupPending': pending > 0}


def erase_account(db, uid, session_hash, deletion_id):
    now = datetime.now(timezone.utc).isoformat(timespec='seconds')
    db.execute('INSERT OR IGNORE INTO deleted_account_tombstones VALUES(?,?)',
               (hashlib.sha256(uid.encode()).hexdigest(), now))
    # Retain only order identifiers/amounts/status for financial reconciliation.
    # No user ID, email, profile, payer details, or membership survives here.
    db.execute('''INSERT INTO deleted_account_payments(
        id,provider,amount_fen,status,created_at,paid_at,provider_trade_no,
        refunded_at,refund_request_no,deleted_at,stone_count,total_fen)
        SELECT id,provider,amount_fen,status,created_at,paid_at,provider_trade_no,
        refunded_at,refund_request_no,?,stone_count,total_fen FROM payment_orders WHERE user_id=?''', (now, uid))
    stones.delete_account(db, uid, now)
    db.execute('DELETE FROM payment_orders WHERE user_id=?', (uid,))
    db.execute('''INSERT INTO account_deletion_files(submission_id,deletion_id)
        SELECT id,? FROM question_bank_submissions WHERE user_id=?''', (deletion_id, uid))

    # Remove references first; other people's replies remain as standalone posts.
    db.execute('''DELETE FROM notifications WHERE user_id=? OR actor_id=?
        OR comment_id IN (SELECT id FROM question_comments WHERE user_id=?)
        OR connection_id IN (SELECT id FROM friend_connections
                             WHERE user_low_id=? OR user_high_id=?)
        OR message_id IN (SELECT id FROM direct_messages WHERE sender_id=? OR recipient_id=?)''',
               (uid,) * 7)
    db.execute('''DELETE FROM comment_votes WHERE user_id=? OR comment_id IN
                  (SELECT id FROM question_comments WHERE user_id=?)''', (uid, uid))
    db.execute('''UPDATE question_comments SET parent_id=NULL WHERE parent_id IN
                  (SELECT id FROM question_comments WHERE user_id=?)''', (uid,))
    db.execute('DELETE FROM question_comments WHERE user_id=?', (uid,))
    db.execute('DELETE FROM direct_messages WHERE sender_id=? OR recipient_id=?', (uid, uid))
    db.execute('DELETE FROM friend_connections WHERE user_low_id=? OR user_high_id=?', (uid, uid))
    db.execute('DELETE FROM social_blocks WHERE blocker_id=? OR blocked_id=?', (uid, uid))
    db.execute('''DELETE FROM social_removed_contacts
            WHERE user_low_id=? OR user_high_id=?''', (uid, uid))
    for table in ('sessions', 'events', 'settings', 'question_bank_submissions',
                  'profiles', 'daily_checkins', 'ai_question_bank_requests',
                  'assistant_chat_requests', 'vip_memberships', 'account_deletion_attempts'):
        db.execute(f'DELETE FROM {table} WHERE user_id=?', (uid,))
    db.execute('DELETE FROM users WHERE id=?', (uid,))
    # The initiating bearer can retry for 24h if the success response was lost.
    # This receipt cannot authorize any other API or identify a former user.
    db.execute('INSERT INTO account_deletion_receipts VALUES(?,?,?)',
               (session_hash, deletion_id, int(time.time()) + 86400))


def record_deleted_payment(db, order_id, provider, amount, trade_no, status):
    """For already signature-verified callbacks only; never restore a member."""
    row = db.execute('SELECT * FROM deleted_account_payments WHERE id=? AND provider=?',
                     (order_id, provider)).fetchone()
    if row is None:
        return False
    if row['amount_fen'] != amount or (row['provider_trade_no'] and
                                      row['provider_trade_no'] != trade_no):
        raise ValueError('已删除账号的订单校验失败')
    if db.execute('SELECT 1 FROM payment_orders WHERE provider_trade_no=?', (trade_no,)).fetchone():
        raise ValueError('交易号已关联其他订单')
    now = datetime.now(timezone.utc).isoformat(timespec='seconds')
    paid = status in ('TRADE_SUCCESS', 'TRADE_FINISHED', 'SUCCESS')
    new_status = row['status']
    if paid and new_status in ('created', 'closed'):
        new_status = 'paid'
    elif status == 'TRADE_CLOSED' and new_status == 'created':
        new_status = 'closed'
    db.execute('''UPDATE deleted_account_payments SET status=?,provider_trade_no=?,
        paid_at=?,last_provider_status=?,last_notified_at=?,needs_review=1 WHERE id=?''',
               (new_status, trade_no, row['paid_at'] or (now if paid else None),
                status, now, order_id))
    return True
