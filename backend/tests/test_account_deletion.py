import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest import mock
from http.server import ThreadingHTTPServer
from urllib import request, error, parse

import server


class AccountDeletionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.patch = mock.patch.multiple(server, DB=Path(self.temp.name) / 'db.sqlite',
                                        SUBMISSIONS=Path(self.temp.name) / 'submissions')
        self.patch.start()
        self.addCleanup(self.patch.stop)
        server.initialize()
        self.http = ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)
        self.url = f'http://127.0.0.1:{self.http.server_port}'
        self.password = 'deletion-test-password'
        self.first = self.register('first')
        self.other = self.register('other')

    def stop(self):
        self.http.shutdown()
        self.http.server_close()
        self.thread.join()

    def call(self, path, body=None, token=None):
        req = request.Request(self.url + path,
                              data=json.dumps(body).encode() if body is not None else None,
                              headers={'Content-Type': 'application/json',
                                       **({'Authorization': 'Bearer ' + token} if token else {})})
        try:
            with request.urlopen(req) as response:
                return response.status, json.load(response)
        except error.HTTPError as response:
            return response.code, json.load(response)

    def register(self, name):
        status, account = self.call('/v1/auth/register',
                                    {'email': name + '@example.test', 'password': self.password})
        self.assertEqual(status, 200)
        return account

    def delete(self, **values):
        return self.call('/v1/account/delete',
                         {'confirmation': 'DELETE', 'password': self.password, **values},
                         self.first['token'])

    def seed_related_data(self):
        uid, other = self.first['userId'], self.other['userId']
        self.submission = 'submission_test_12345678'
        self.order = 'DS' + 'a' * 40
        with server.connect() as db:
            db.execute('INSERT INTO events VALUES(?,?,?)', (uid, 'event', '{}'))
            db.execute('INSERT INTO settings VALUES(?,?,?,?)', (uid, 20, None, '2026-10-22'))
            db.execute('INSERT INTO daily_checkins VALUES(?,?,?)', (uid, '2026-10-22', 'now'))
            db.execute('INSERT INTO question_bank_submissions VALUES(?,?,?,?,?,?,?)',
                       (self.submission, uid, 'private.json', 2, 0, 'checksum', 'now'))
            for ident, who, parent in [('mine', uid, None), ('reply', other, 'mine')]:
                db.execute('''INSERT INTO question_comments
                    (id,user_id,question_id,body,created_at,parent_id) VALUES(?,?,?,?,?,?)''',
                           (ident, who, 'question', ident, 'now', parent))
            db.execute('INSERT INTO comment_votes VALUES(?,?,?)', ('mine', other, 1))
            db.execute('INSERT INTO comment_votes VALUES(?,?,?)', ('reply', uid, 1))
            db.execute('INSERT INTO friend_connections VALUES(?,?,?,?,?,?,?)',
                       ('connection', min(uid, other), max(uid, other), uid, 'accepted', 'now', 'now'))
            for ident, sender, recipient in [('sent', uid, other), ('received', other, uid)]:
                db.execute('''INSERT INTO direct_messages(
                        id,conversation_key,sender_id,recipient_id,body,created_at,read_at)
                        VALUES(?,?,?,?,?,?,?)''',
                           (ident, 'conversation', sender, recipient, 'private', 'now', None))
            db.execute('INSERT INTO social_blocks VALUES(?,?,?)', (uid, other, 'now'))
            db.execute('INSERT INTO social_removed_contacts VALUES(?,?,?)',
                       (min(uid, other), max(uid, other), 'now'))
            db.execute('''INSERT INTO notifications
                (id,user_id,type,actor_id,comment_id,connection_id,message_id,created_at)
                VALUES(?,?,?,?,?,?,?,?)''',
                       ('notice', other, 'direct_message', uid, 'mine', 'connection', 'sent', 'now'))
            db.execute('INSERT INTO ai_question_bank_requests VALUES(?,?,?,?,?,?,?,?)',
                       ('ai', uid, 'now', 1, 1, 1, 1, 'done'))
            db.execute('INSERT INTO assistant_chat_requests VALUES(?,?,?,?,?,?,?,?,?,?)',
                       ('chat', 'fingerprint', uid, 'casual', 'now', 1, 1, 1, 1, 'done'))
            db.execute('''INSERT INTO payment_orders
                (id,user_id,provider,amount_fen,status,created_at,membership_plan)
                VALUES(?,?,?,?,?,?,?)''', (self.order, uid, 'alipay', 100, 'created', 'now', 'month'))
        self.file = server.SUBMISSIONS / (self.submission + '.json')
        self.file.write_text('{}')
        self.unrelated_file = server.SUBMISSIONS / 'unrelated.json'
        self.unrelated_file.write_text('other user content')

    def test_requires_session_password_confirmation_and_limits_attempts(self):
        self.assertEqual(self.call('/v1/account/delete',
                                  {'confirmation': 'DELETE', 'password': self.password})[0], 401)
        self.assertEqual(self.delete(confirmation=False)[0], 400)
        for _ in range(5):
            self.assertEqual(self.delete(password='wrong-password-test')[0], 401)
        self.assertEqual(self.delete()[0], 401)
        with server.connect() as db:
            self.assertIsNotNone(db.execute('SELECT id FROM users WHERE id=?',
                                            (self.first['userId'],)).fetchone())
            db.execute('UPDATE account_deletion_attempts SET locked_until=0')
        self.assertEqual(self.delete()[0], 200)

    def test_deletes_all_owned_data_preserves_other_user_and_retries(self):
        self.seed_related_data()
        _, second_login = self.call('/v1/auth/login',
                                   {'email': self.first['email'], 'password': self.password})
        status, response = self.delete(userId=self.other['userId'])
        self.assertEqual(status, 200, response)
        self.assertFalse(response['fileCleanupPending'])
        self.assertFalse(self.file.exists())
        self.assertTrue(self.unrelated_file.exists())
        with server.connect() as db:
            self.assertIsNone(db.execute('SELECT * FROM users WHERE id=?',
                                         (self.first['userId'],)).fetchone())
            for table in ('events', 'settings', 'daily_checkins', 'question_bank_submissions',
                          'comment_votes', 'direct_messages', 'friend_connections', 'notifications',
                          'social_blocks', 'social_removed_contacts',
                          'ai_question_bank_requests', 'assistant_chat_requests',
                          'payment_orders'):
                self.assertEqual(db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0], 0, table)
            self.assertEqual([row[0] for row in db.execute('SELECT user_id FROM vip_memberships')],
                             [self.other['userId']])
            reply = db.execute('SELECT * FROM question_comments').fetchone()
            self.assertEqual(reply['body'], 'reply')
            self.assertIsNone(reply['parent_id'])
            archive = dict(db.execute('SELECT * FROM deleted_account_payments').fetchone())
            self.assertNotIn('user_id', archive)
            self.assertNotIn(self.first['email'], json.dumps(archive))
            self.assertEqual(list(db.execute('PRAGMA foreign_key_check')), [])
        for token in (self.first['token'], second_login['token']):
            self.assertEqual(self.call('/v1/profile', token=token)[0], 401)
        self.assertEqual(self.call('/v1/profile', token=self.other['token'])[0], 200)
        self.assertEqual(self.delete(), (200, response))  # lost response/retry
        self.assertEqual(self.call('/v1/auth/login',
                                  {'email': self.first['email'], 'password': self.password})[0], 401)
        fresh = self.register('first')
        self.assertNotEqual(fresh['userId'], self.first['userId'])

    def test_failed_transaction_does_not_revoke_or_unlink(self):
        self.seed_related_data()
        erase = server.erase_account
        def fail_after_changes(*args):
            erase(*args)
            raise sqlite3.IntegrityError('injected transaction failure')
        with mock.patch.object(server, 'erase_account', side_effect=fail_after_changes):
            self.assertEqual(self.delete()[0], 400)
        self.assertTrue(self.file.exists())
        self.assertEqual(self.call('/v1/profile', token=self.first['token'])[0], 200)
        with server.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM deleted_account_payments').fetchone()[0], 0)

    def test_reregistered_operator_does_not_inherit_admin_access(self):
        with mock.patch.object(server, 'ADMIN_EMAIL', self.first['email']):
            self.assertTrue(self.call('/v1/question-bank-submissions', token=self.first['token'])[1]['isAdmin'])
            self.assertEqual(self.delete()[0], 200)
            fresh = self.register('first')
            self.assertFalse(self.call('/v1/question-bank-submissions', token=fresh['token'])[1]['isAdmin'])

    def test_concurrent_retry_has_one_tombstone(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.delete(), range(2)))
        self.assertTrue(all(status == 200 and body['deleted'] for status, body in results), results)
        with server.connect() as db:
            hashes = [row[0] for row in db.execute('SELECT user_hash FROM deleted_account_tombstones')]
        self.assertEqual(hashes, [hashlib.sha256(self.first['userId'].encode()).hexdigest()])

    def test_file_cleanup_is_durable_and_retried_after_restart(self):
        self.seed_related_data()
        with mock.patch.object(Path, 'unlink', side_effect=PermissionError('busy')):
            status, response = self.delete()
        self.assertEqual(status, 200)
        self.assertTrue(response['fileCleanupPending'])
        self.assertTrue(self.file.exists())
        server.initialize()
        self.assertFalse(self.file.exists())
        self.assertFalse(self.delete()[1]['fileCleanupPending'])

    def test_late_signed_payment_is_recorded_without_restoring_account(self):
        self.seed_related_data()
        self.assertEqual(self.delete()[0], 200)
        payload = dict(app_id='app', seller_id='seller', out_trade_no=self.order,
                       trade_no='trade_123456', total_amount='1.00',
                       trade_status='TRADE_SUCCESS', sign='test', sign_type='RSA2')
        with mock.patch.object(server, 'alipay_config', return_value={'app_id': 'app', 'seller_id': 'seller'}):
            with mock.patch.object(server, 'alipay_signature_valid', return_value=False):
                with self.assertRaises(ValueError):
                    server.Handler.alipay_notification(None, payload)
            with mock.patch.object(server, 'alipay_signature_valid', return_value=True):
                server.Handler.alipay_notification(None, payload)
                server.Handler.alipay_notification(None, payload)
                with self.assertRaises(ValueError):
                    server.Handler.alipay_notification(None, {**payload, 'total_amount': '2.00'})
        with server.connect() as db:
            row = db.execute('SELECT * FROM deleted_account_payments').fetchone()
            self.assertEqual(row['status'], 'paid')
            self.assertEqual(row['needs_review'], 1)
            self.assertEqual([row[0] for row in db.execute('SELECT user_id FROM vip_memberships')],
                             [self.other['userId']])
            self.assertIsNone(db.execute('SELECT id FROM users WHERE id=?',
                                         (self.first['userId'],)).fetchone())


if __name__ == '__main__':
    unittest.main()
