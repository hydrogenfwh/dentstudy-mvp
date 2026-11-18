import hashlib
import json
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest import mock
from urllib import request, error

import server
import settle_stone_leaderboard as settle_cli
import stones


class StoneTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        patch = mock.patch.multiple(server, DB=Path(self.temp.name) / 'db.sqlite',
            SUBMISSIONS=Path(self.temp.name) / 'uploads', STONE_REDEMPTIONS_OPEN=True,
            MEMBERSHIP_PURCHASES_OPEN=True, ALIPAY_PAYMENTS_LIVE=False,
            PAYMENT_AUTHOR_EMAIL='a@example.test', PAYMENT_AUTHOR_USER_ID='a')
        patch.start()
        self.addCleanup(patch.stop)
        server.initialize()
        self.handler = server.Handler.__new__(server.Handler)
        with server.connect() as db:
            for uid in ('a', 'b'):
                db.execute('INSERT INTO users VALUES(?,?,?,?)', (uid, uid + '@example.test', 'salt', 'hash'))
                db.execute('INSERT INTO sessions VALUES(?,?,?)',
                    (hashlib.sha256((uid + '-token').encode()).hexdigest(), uid, 9999999999))
        self.day = server.beijing_today().isoformat()

    def seed(self, amount=1000):
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            stones.change(db, 'a', amount, 'test seed', 'test-seed', self.day)

    def call_api(self, path, body=None, token='a-token'):
        if not hasattr(self, 'http'):
            self.http = ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
            self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
            self.thread.start()
            self.addCleanup(self.stop_http)
        req = request.Request(f'http://127.0.0.1:{self.http.server_port}' + path,
            data=None if body is None else json.dumps(body).encode(),
            headers={'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + token} if token else {})})
        try:
            with request.urlopen(req) as r: return r.status, json.load(r)
        except error.HTTPError as r: return r.code, json.load(r)

    def stop_http(self):
        self.http.shutdown(); self.http.server_close(); self.thread.join()

    def test_auth_daily_share_checkin_and_private_ledger(self):
        self.assertEqual(self.call_api('/v1/stones', token=None)[0], 401)
        self.assertEqual(self.call_api('/v1/stones/share', {})[0], 400)
        for path, body in [('/v1/checkins', {}), ('/v1/stones/share', {'systemShareCompleted': True})]:
            first = self.call_api(path, body)[1]
            again = self.call_api(path, body)[1]
            self.assertEqual(sum(r['amount'] for r in first['stoneRewards']), 1)
            self.assertEqual(again['stoneRewards'], [])
        wallet = self.call_api('/v1/stones')[1]
        self.assertEqual(wallet['balance'], 2)
        self.assertTrue(wallet['shareClaimedToday'])
        other_wallet = self.call_api('/v1/stones', token='b-token')[1]
        self.assertEqual(other_wallet['balance'], 0)
        self.assertFalse(other_wallet['shareClaimedToday'])

    def test_every_seven_days_and_break_in_streak(self):
        start = server.beijing_today() - timedelta(days=20)
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            for i in range(1, 15):
                day = (start + timedelta(days=i)).isoformat()
                stones.checkin(db, 'a', day, i)
                self.assertEqual(stones.checkin(db, 'a', day, i), [])
            self.assertEqual(stones.balance(db, 'a'), 28)
            stones.checkin(db, 'a', self.day, 1)
            self.assertEqual(stones.balance(db, 'a'), 29)

    def test_makeup_checkin_costs_five_obeys_limits_and_restores_seven_day_bonus(self):
        today = date(2026, 10, 23)
        self.seed(20)
        # Restoring 10/19 reconnects 10/17–10/23 into exactly seven days.
        with server.connect() as db:
            for signed_day in ('2026-10-17', '2026-10-18', '2026-10-20',
                               '2026-10-21', '2026-10-22', '2026-10-23'):
                db.execute('INSERT INTO daily_checkins VALUES(?,?,?)',
                           ('a', signed_day, '2026-10-23T00:00:00+08:00'))

        with mock.patch.object(server, 'beijing_today', return_value=today):
            status, result = self.call_api('/v1/checkins/makeup',
                                           {'date': '2026-10-19'})
            self.assertEqual(status, 200)
            self.assertEqual([entry['amount'] for entry in result['stoneRewards']],
                             [-5, 7])
            self.assertEqual(result['currentStreak'], 7)
            self.assertEqual(result['makeupUsedToday'], 1)
            self.assertEqual(result['makeupRemaining'], 2)
            self.assertIn('2026-10-19', result['dates'])
            self.assertEqual(self.call_api('/v1/checkins/makeup',
                                           {'date': '2026-10-19'})[0], 400)
            self.assertEqual(self.call_api('/v1/checkins/makeup',
                                           {'date': '2026-10-23'})[0], 400)
            self.assertEqual(self.call_api('/v1/checkins/makeup',
                                           {'date': '2026-10-24'})[0], 400)
            self.assertEqual(self.call_api('/v1/checkins/makeup',
                                           {'date': '2026-10-20'})[0], 400)
            # Two more valid dates reach the daily limit; a fourth is rejected
            # before any stones or check-in rows change.
            self.assertEqual(self.call_api('/v1/checkins/makeup',
                                           {'date': '2026-10-01'})[0], 200)
            self.assertEqual(self.call_api('/v1/checkins/makeup',
                                           {'date': '2026-10-02'})[0], 200)
            self.assertEqual(self.call_api('/v1/checkins/makeup',
                                           {'date': '2026-10-03'})[0], 400)
            summary = self.call_api('/v1/checkins?year=2026')[1]
            self.assertEqual(summary['makeupCost'], 5)
            self.assertEqual(summary['makeupDailyLimit'], 3)
            self.assertEqual(summary['makeupUsedToday'], 3)
            self.assertEqual(summary['makeupRemaining'], 0)

        with server.connect() as db:
            self.assertEqual(stones.balance(db, 'a'), 12)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM stone_checkin_makeups')
                             .fetchone()[0], 3)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM daily_checkins '
                                        "WHERE user_id='a' AND checkin_date='2026-10-03'")
                             .fetchone()[0], 0)

        with mock.patch.object(server, 'beijing_today', return_value=today):
            # A user without five stones cannot create either half of a makeup.
            self.assertEqual(self.call_api('/v1/checkins/makeup',
                                           {'date': '2026-10-19'}, token='b-token')[0], 400)
        with server.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM stone_checkin_makeups '
                                        "WHERE user_id='b'").fetchone()[0], 0)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM daily_checkins '
                                        "WHERE user_id='b'").fetchone()[0], 0)

    def test_concurrent_makeup_claims_charge_once(self):
        self.seed(10)
        today = date(2026, 10, 23)

        def claim(_):
            try:
                with server.connect() as db:
                    db.execute('BEGIN IMMEDIATE')
                    return stones.makeup_checkin(db, 'a', '2026-10-22', today)
            except ValueError:
                return None

        with ThreadPoolExecutor(max_workers=5) as pool:
            results = list(pool.map(claim, range(8)))
        self.assertEqual(sum(result is not None for result in results), 1)
        self.assertEqual(sum(len(result or []) for result in results), 1)
        with server.connect() as db:
            self.assertEqual(stones.balance(db, 'a'), 5)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM stone_checkin_makeups')
                             .fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM daily_checkins').fetchone()[0], 1)

    def test_leaderboard_defaults_to_participating_is_scoped_and_exposes_only_opaque_profile_ids(self):
        today = date(2026, 10, 23)  # Thursday; the week starts on Monday 10/20.
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute('INSERT INTO profiles VALUES(?,?,?,?,?)',
                       ('a', '阿甲', 'book', '', 'now'))
            db.execute('INSERT INTO profiles VALUES(?,?,?,?,?)',
                       ('b', '阿乙', 'tooth', '', 'now'))
            # a: today=2, week=3, month=4, all=5.  The test seed is excluded.
            stones.change(db, 'a', 1, '每日签到', 'checkin:2026-10-23', '2026-10-23')
            stones.change(db, 'a', 1, '每日首次分享', 'share:2026-10-23', '2026-10-23')
            stones.change(db, 'a', 1, '每日复习完成', 'review:2026-10-22', '2026-10-22')
            stones.change(db, 'a', 1, '上传题库', 'upload:oct', '2026-10-18')
            stones.change(db, 'a', 1, '每日学习完成', 'learn:sep', '2026-09-30')
            stones.change(db, 'a', 99, 'test seed', 'leaderboard-seed-a', '2026-10-23')
            stones.change(db, 'b', 1, '每日签到', 'checkin:2026-10-23:b', '2026-10-23')

        with mock.patch.object(server, 'beijing_today', return_value=today):
            self.assertEqual(self.call_api('/v1/stones/leaderboard', token=None)[0], 401)
            before = self.call_api('/v1/stones/leaderboard?scope=today')[1]
            self.assertEqual(
                [(item['rank'], item['userId'], item['nickname'], item['avatar'], item['score'])
                 for item in before['entries']],
                [(1, 'a', '阿甲', 'book', 2), (2, 'b', '阿乙', 'tooth', 1)])
            self.assertTrue(before['self']['participating'])
            self.assertEqual(before['self']['score'], 2)
            self.assertEqual(before['me'], before['self'])
            self.assertEqual(before['self']['displayRank'], '1')
            self.assertEqual(before['range'], '北京时间 2026-10-23')
            self.assertEqual(self.call_api('/v1/stones/leaderboard/participation',
                                           {'enabled': 1})[0], 400)
            self.assertEqual(self.call_api('/v1/stones/leaderboard/participation',
                                           {'enabled': True})[1], {'enabled': True})
            self.assertEqual(self.call_api('/v1/stones/leaderboard/participation',
                                           {'enabled': True}, token='b-token')[1],
                             {'enabled': True})

            scores = {}
            for scope in ('today', 'week', 'month', 'all'):
                board = self.call_api(f'/v1/stones/leaderboard?scope={scope}')[1]
                scores[scope] = board['self']['score']
            self.assertEqual(scores, {'today': 2, 'week': 3, 'month': 4, 'all': 5})
            today_board = self.call_api('/v1/stones/leaderboard?scope=today')[1]
            self.assertEqual(
                [(item['rank'], item['userId'], item['nickname'], item['avatar'], item['score'])
                 for item in today_board['entries']],
                [(1, 'a', '阿甲', 'book', 2), (2, 'b', '阿乙', 'tooth', 1)])
            self.assertEqual(today_board['entries'][0]['userId'], 'a')
            self.assertNotIn('email', today_board['entries'][0])
            self.assertNotIn('id', today_board['entries'][0])
            self.assertEqual(today_board['me'], today_board['self'])
            self.assertEqual(today_board['self']['rank'], 1)
            self.assertEqual(today_board['tieBreak'], '同分按最早获得有效石头的时间排序')

            self.assertEqual(self.call_api('/v1/stones/leaderboard/participation',
                                           {'enabled': False}, token='b-token')[1],
                             {'enabled': False})
            self.assertEqual(len(self.call_api('/v1/stones/leaderboard?scope=today')[1]
                                 ['entries']), 1)
            self.assertEqual(self.call_api('/v1/stones/leaderboard?scope=bad')[0], 400)

    def test_practice_leaderboard_counts_each_verified_answer_event_once(self):
        now = datetime.now(timezone.utc) - timedelta(minutes=2)
        today = now.astimezone(server.BEIJING).date()
        questions = [q for q in server.questions() if q['answer'] is not None][:3]
        self.assertEqual(len(questions), 3)

        def stamp(moment):
            return moment.isoformat(timespec='microseconds').replace('+00:00', 'Z')

        def review(event_id, question, moment, mode='practice'):
            return {
                'id': event_id,
                'at': stamp(moment),
                'questionId': question['id'],
                'kind': 'review',
                'value': {
                    'answer': question['answer'],
                    'grade': 'mastered',
                    'mode': mode,
                },
            }

        a_events = [
            # A second server-validated answer to the same question is a
            # second completed practice action and must count independently.
            review('practice-rank-a-first-0001', questions[0], now - timedelta(seconds=30)),
            review('practice-rank-a-repeat-0002', questions[0], now - timedelta(seconds=20),
                   mode='review'),
            review('practice-rank-a-second-0003', questions[1], now - timedelta(seconds=10)),
            # Re-reviewing it tomorrow/yesterday is a distinct study day and
            # therefore contributes to the all-time count only.
            review('practice-rank-a-yesterday-0004', questions[0], now - timedelta(days=1)),
            {
                'id': 'practice-rank-a-favorite-0005',
                'at': stamp(now - timedelta(seconds=5)),
                'questionId': questions[0]['id'],
                'kind': 'favorite',
                'value': True,
            },
            {
                'id': 'practice-rank-a-note-0006',
                'at': stamp(now - timedelta(seconds=4)),
                'questionId': questions[0]['id'],
                'kind': 'note',
                'value': '不应计入刷题榜',
            },
        ]
        b_events = [
            review('practice-rank-b-only-0001', questions[2], now - timedelta(seconds=15)),
        ]
        with server.connect() as db:
            db.execute('INSERT INTO profiles VALUES(?,?,?,?,?)',
                       ('a', '勤奋甲', 'book', '', 'now'))
            db.execute('INSERT INTO profiles VALUES(?,?,?,?,?)',
                       ('b', '勤奋乙', 'tooth', '', 'now'))

        with mock.patch.object(server, 'beijing_today', return_value=today):
            self.assertEqual(self.call_api('/v1/practice/leaderboard', token=None)[0], 401)
            self.assertEqual(self.call_api('/v1/sync', {'events': a_events})[0], 200)
            self.assertEqual(self.call_api('/v1/sync', {'events': b_events},
                                           token='b-token')[0], 200)
            board = self.call_api('/v1/practice/leaderboard?scope=today')[1]
            self.assertEqual(
                [(row['rank'], row['userId'], row['nickname'], row['score'])
                 for row in board['entries']],
                [(1, 'a', '勤奋甲', 3), (2, 'b', '勤奋乙', 1)])
            self.assertEqual(board['me']['score'], 3)
            self.assertEqual(board['countingRule'],
                             '每次服务器确认的学习或复习答题计 1；0 题暂不排名')
            self.assertNotIn('email', board['entries'][0])
            self.assertEqual(self.call_api('/v1/practice/leaderboard?scope=all')[1]
                             ['me']['score'], 4)
            self.assertEqual(self.call_api('/v1/practice/leaderboard?scope=bad')[0], 400)

            # A sync retry carries the same immutable event IDs, so neither
            # the source events table nor its ranking projection grows.
            self.assertEqual(self.call_api('/v1/sync', {'events': a_events})[0], 200)
            self.assertEqual(self.call_api('/v1/practice/leaderboard?scope=today')[1]
                             ['me']['score'], 3)

            # The same existing participation preference applies to both
            # boards.  A zero/opted-out learner is absent rather than ranked.
            self.assertEqual(self.call_api('/v1/stones/leaderboard/participation',
                                           {'enabled': False}, token='b-token')[1],
                             {'enabled': False})
            hidden = self.call_api('/v1/practice/leaderboard?scope=today',
                                   token='b-token')[1]
            self.assertEqual([(row['userId'], row['score']) for row in hidden['entries']],
                             [('a', 3)])
            self.assertEqual(hidden['me']['participating'], False)
            self.assertEqual(hidden['me']['score'], 0)

        with server.connect() as db:
            # Five valid answer events were materialized: four for A (three
            # today, including a repeat, plus one yesterday) and one for B.
            # Favorites and notes do not create leaderboard activity.
            self.assertEqual(db.execute(
                'SELECT COUNT(*) FROM practice_leaderboard_answer_events')
                .fetchone()[0], 5)

    def test_practice_leaderboard_backfill_is_bounded_and_idempotent(self):
        now = datetime.now(timezone.utc) - timedelta(minutes=2)
        question = next(q for q in server.questions() if q['answer'] is not None)
        event = {
            'id': 'practice-backfill-review-0001',
            'at': now.isoformat(timespec='microseconds').replace('+00:00', 'Z'),
            'questionId': question['id'],
            'kind': 'review',
            'value': {'answer': question['answer'], 'grade': 'mastered'},
        }
        repeat = {**event,
                  'id': 'practice-backfill-repeat-0002',
                  'at': (now + timedelta(seconds=1)).isoformat(
                      timespec='microseconds').replace('+00:00', 'Z')}
        with server.connect() as db:
            # Simulate an existing installation before the compact projection
            # was introduced.  A completed v1 marker must not suppress the
            # additive v2 migration, which starts from immutable source events
            # and records a separate durable completion marker.
            db.execute('DELETE FROM practice_leaderboard_answer_events')
            db.execute('DELETE FROM practice_leaderboard_backfills')
            db.execute('''INSERT INTO practice_leaderboard_backfills(name,completed_at)
                          VALUES(?,?)''',
                       ('validated-review-events-v1', '2026-10-01T00:00:00Z'))
            db.execute('INSERT INTO events VALUES(?,?,?)',
                       ('a', event['id'], json.dumps(event, ensure_ascii=False)))
            db.execute('INSERT INTO events VALUES(?,?,?)',
                       ('a', repeat['id'], json.dumps(repeat, ensure_ascii=False)))
        server.initialize()
        server.initialize()
        with server.connect() as db:
            rows = db.execute('''SELECT user_id,event_id,question_id,day
                                 FROM practice_leaderboard_answer_events
                                 ORDER BY user_id,event_id''').fetchall()
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]['user_id'], 'a')
            self.assertEqual([row['event_id'] for row in rows],
                             sorted([event['id'], repeat['id']]))
            self.assertEqual(db.execute('''SELECT COUNT(*) FROM practice_leaderboard_backfills
                                            WHERE name=?''',
                                          (stones.PRACTICE_LEADERBOARD_BACKFILL_NAME,)).fetchone()[0], 1)

    def test_leaderboard_counts_stable_earned_sources_and_bounds_public_avatars(self):
        today = date(2026, 10, 23)
        approved_avatar = 'data:image/png;base64,' + 'a' * (128 * 1024)
        oversized_avatar = ('data:image/png;base64,' +
                            'x' * stones.MAX_PUBLIC_LEADERBOARD_AVATAR_CHARS)
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute('INSERT INTO profiles VALUES(?,?,?,?,?)',
                       ('a', '阿甲', approved_avatar, '', 'now'))
            db.execute('INSERT INTO profiles VALUES(?,?,?,?,?)',
                       ('b', '阿乙', oversized_avatar, '', 'now'))
            db.execute('''INSERT INTO vip_memberships(
                    user_id,status,source,started_at,expires_at,updated_at)
                VALUES(?,?,?,?,?,?)''',
                       ('a', 'active', 'test', '2026-10-01T00:00:00Z', None,
                        '2026-10-01T00:00:00Z'))
            stones.set_leaderboard_participation(db, 'a', True)
            stones.set_leaderboard_participation(db, 'b', True)
            # A copy change must not silently remove a valid earn source.
            stones.change(db, 'a', 2, '新版学习文案', 'learn:2026-10-23', today.isoformat())
            stones.change(db, 'b', 1, '每日签到', 'checkin:2026-10-23:b', today.isoformat())
            # These positive rows are deliberately not competitive score.
            stones.change(db, 'a', 9, '订单关闭或退款返还', 'release:test', today.isoformat())
            stones.change(db, 'a', 5, '月榜奖励', 'leaderboard:2026-09:a', today.isoformat())
            board = stones.leaderboard(db, 'a', 'today', today)
        self.assertEqual(board['me']['score'], 2)
        self.assertEqual(board['entries'], [
            {'rank': 1, 'userId': 'a', 'nickname': '阿甲',
             'avatar': approved_avatar, 'vipBadge': True, 'score': 2},
            {'rank': 2, 'userId': 'b', 'nickname': '阿乙', 'avatar': 'book',
             'vipBadge': False, 'score': 1},
        ])

    def test_leaderboard_same_score_uses_first_earning_in_the_requested_scope(self):
        """A prior month's earning must not decide a tie in today's board."""
        today = date(2026, 10, 23)
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute('INSERT INTO profiles VALUES(?,?,?,?,?)',
                       ('a', '后到甲', 'book', '', 'now'))
            db.execute('INSERT INTO profiles VALUES(?,?,?,?,?)',
                       ('b', '先到乙', 'tooth', '', 'now'))
            stones.set_leaderboard_participation(db, 'a', True)
            stones.set_leaderboard_participation(db, 'b', True)
            # This older row has the smallest ledger ID overall, but lies
            # outside today's board and must not win today's same-score tie.
            stones.change(db, 'a', 1, '每日学习完成', 'learn:2026-10-22',
                          '2026-10-22')
            stones.change(db, 'b', 1, '每日首次分享', 'share:2026-10-23:b',
                          today.isoformat())
            stones.change(db, 'a', 1, '每日首次分享', 'share:2026-10-23:a',
                          today.isoformat())
            board = stones.leaderboard(db, 'a', 'today', today)

        self.assertEqual(
            [(entry['rank'], entry['nickname'], entry['score'])
             for entry in board['entries']],
            [(1, '先到乙', 1), (2, '后到甲', 1)])
        self.assertEqual(board['me']['rank'], 2)
        self.assertEqual(board['me']['displayRank'], '2')

    def test_concurrent_monthly_settlement_awards_once(self):
        month, settled_day = '2026-10', date(2026, 11, 1)
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            for uid, points in (('a', 2), ('b', 1)):
                stones.set_leaderboard_participation(db, uid, True)
                stones.change(db, uid, points, '每日签到',
                              f'checkin:{uid}:october', '2026-10-31')

        def settle(_):
            with server.connect() as db:
                db.execute('BEGIN IMMEDIATE')
                return stones.settle_monthly_leaderboard(db, month, settled_day)

        with ThreadPoolExecutor(max_workers=5) as pool:
            results = list(pool.map(settle, range(8)))
        self.assertEqual(sum(not result['alreadySettled'] for result in results), 1)
        with server.connect() as db:
            self.assertEqual(db.execute('''SELECT COUNT(*) FROM stone_ledger
                                            WHERE reason='月榜奖励' ''').fetchone()[0], 2)
            self.assertEqual(db.execute('''SELECT COUNT(*) FROM
                                            stone_monthly_leaderboard_awards''').fetchone()[0], 2)

    def test_monthly_settlement_cli_catches_up_only_after_first_settlement(self):
        with server.connect() as db:
            self.assertEqual(settle_cli.completed_months_to_settle(
                db, date(2026, 11, 1)), ['2026-10'])
            db.execute('''INSERT INTO stone_monthly_leaderboard_settlements(
                            month,settled_at,award_count) VALUES(?,?,?)''',
                       ('2026-10', '2026-11-01T00:10:00Z', 0))
            self.assertEqual(settle_cli.completed_months_to_settle(
                db, date(2027, 1, 1)), ['2026-11', '2026-12'])

    def test_monthly_leaderboard_settlement_tiers_idempotency_and_anonymous_audit(self):
        month = '2026-10'
        settled_day = date(2026, 11, 1)
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            for rank in range(1, 52):
                uid = f'rank-{rank:02d}'
                db.execute('INSERT INTO users VALUES(?,?,?,?)',
                           (uid, uid + '@example.test', 'salt', 'hash'))
                stones.set_leaderboard_participation(db, uid, True)
                # Distinct descending scores make rank order unambiguous.
                stones.change(db, uid, 1_000 - rank, '每日签到',
                              f'checkin:{uid}', '2026-10-15')

        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            first = stones.settle_monthly_leaderboard(db, month, settled_day)
            self.assertEqual(first, {'month': month, 'alreadySettled': False,
                                     'awardCount': 50})
            rows = db.execute('''SELECT rank,reward FROM stone_monthly_leaderboard_awards
                                 WHERE month=? ORDER BY rank''', (month,)).fetchall()
            self.assertEqual(len(rows), 50)
            rewards = {row['rank']: row['reward'] for row in rows}
            self.assertEqual(
                {rank: rewards[rank] for rank in (1, 2, 3, 4, 10, 11, 50)},
                {1: 30, 2: 20, 3: 10, 4: 5, 10: 5, 11: 2, 50: 2})
            # The payout uses a non-earning reason, so it never increases
            # the score shown in the next leaderboard period.
            all_time = stones.leaderboard(db, 'rank-01', 'all', settled_day)
            self.assertEqual(all_time['self']['score'], 999)
            self.assertEqual(stones.balance(db, 'rank-01'), 1_029)
            self.assertEqual(stones.balance(db, 'rank-51'), 949)
            last_place = stones.leaderboard(db, 'rank-51', 'all', settled_day)
            self.assertEqual(len(last_place['entries']), 50)
            self.assertEqual(last_place['me'], {
                'userId': 'rank-51', 'participating': True,
                'rank': None, 'displayRank': '50+', 'score': 949,
                'nickname': '齿间同学', 'avatar': 'book', 'vipBadge': False,
            })

        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            second = stones.settle_monthly_leaderboard(db, month, settled_day)
            self.assertEqual(second, {'month': month, 'alreadySettled': True,
                                      'awardCount': 50})
            self.assertEqual(db.execute('''SELECT COUNT(*) FROM stone_ledger
                                            WHERE reason='月榜奖励' ''').fetchone()[0], 50)
            with self.assertRaises(ValueError):
                stones.settle_monthly_leaderboard(db, '2026-11', settled_day)
            db.rollback()

        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute('''INSERT INTO practice_leaderboard_events(
                    user_id,question_id,day,first_event_at,first_event_id)
                    VALUES(?,?,?,?,?)''',
                       ('rank-01', 'deleted-practice-question', '2026-10-15',
                        '2026-10-15T00:00:00.000000Z', 'deleted-practice-event'))
            db.execute('''INSERT INTO practice_leaderboard_answer_events(
                    user_id,event_id,question_id,day,completed_at)
                    VALUES(?,?,?,?,?)''',
                       ('rank-01', 'deleted-practice-answer-event',
                        'deleted-practice-question', '2026-10-15',
                        '2026-10-15T00:00:00.000000Z'))
            stones.delete_account(db, 'rank-01', '2026-11-02T00:00:00Z')
            self.assertIsNone(db.execute('''SELECT 1 FROM stone_leaderboard_preferences
                                             WHERE user_id='rank-01' ''').fetchone())
            self.assertIsNone(db.execute('''SELECT 1 FROM stone_monthly_leaderboard_awards
                                             WHERE user_id='rank-01' ''').fetchone())
            self.assertIsNone(db.execute('''SELECT 1 FROM practice_leaderboard_events
                                             WHERE user_id='rank-01' ''').fetchone())
            self.assertIsNone(db.execute('''SELECT 1 FROM practice_leaderboard_answer_events
                                             WHERE user_id='rank-01' ''').fetchone())
            audit = db.execute('''SELECT month,rank,score,reward FROM
                                  deleted_stone_monthly_leaderboard_awards''').fetchone()
            self.assertEqual(dict(audit),
                             {'month': month, 'rank': 1, 'score': 999, 'reward': 30})
            self.assertNotIn('user_id', [row['name'] for row in db.execute(
                'PRAGMA table_info(deleted_stone_monthly_leaderboard_awards)')])

    def test_upload_cap_fingerprint_and_new_day(self):
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            for i in range(5):
                result = stones.upload(db, 'a', {'questions': [{'id': str(i), 'stem': 'question' + str(i)}]}, self.day)
                self.assertEqual(len(result), 1 if i < 3 else 0)
            # Renamed and reformatted submissions do not pay again, even tomorrow.
            tomorrow = (server.beijing_today() + timedelta(days=1)).isoformat()
            self.assertEqual(stones.upload(db, 'a', {'questions': [{'id': 'renamed', 'stem': 'question0'}]}, tomorrow), [])
            self.assertEqual(len(stones.upload(db, 'a', {'questions': [{'stem': 'new question'}]}, tomorrow)), 1)
            self.assertEqual(stones.balance(db, 'a'), 4)

    def test_wallet_upload_reward_count_is_not_limited_to_first_ledger_page(self):
        """The compact upload counter stays correct after heavy wallet use."""
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            for index in range(3):
                stones.change(db, 'a', 1, '上传题库', f'upload:today-{index}', self.day)
            # These newer rows deliberately push every upload reward beyond the
            # 50-entry wallet response page.
            for index in range(55):
                stones.change(db, 'a', 1, '测试奖励', f'newer-ledger:{index}', self.day)

        wallet = self.call_api('/v1/stones')[1]
        self.assertEqual(wallet['uploadRewardCountToday'], 3)
        self.assertNotIn('上传题库', [item['reason'] for item in wallet['items']])

    def test_learning_and_review_only_first_completion_per_day(self):
        today = server.beijing_today()
        now = datetime.now(timezone.utc) - timedelta(seconds=1)
        old = (now - timedelta(days=2)).isoformat()
        bank = [dict(id=str(i), answer='A', modes=['考研']) for i in range(4)]
        def event(ident, q, at):
            return dict(id=ident, questionId=str(q), at=at, kind='review', value={'answer': 'A', 'grade': 'mastered'})
        with server.connect() as db:
            db.execute('INSERT INTO settings VALUES(?,?,?,?)', ('a', 2, 1, old))
            prior = event('prior', 0, old)
            db.execute('INSERT INTO events VALUES(?,?,?)', ('a', 'prior', json.dumps(prior)))
            self.assertEqual(stones.learning(db, 'a', bank, self.day), [])
            for i, q in enumerate([1, 1, 0, 2]):
                e = event('today' + str(i), q, now.isoformat())
                db.execute('INSERT INTO events VALUES(?,?,?)', ('a', e['id'], json.dumps(e)))
                rewards = stones.learning(db, 'a', bank, self.day)
                self.assertEqual(len(rewards), 1 if i in (2, 3) else 0)
            self.assertEqual(stones.learning(db, 'a', bank, self.day), [])
            self.assertEqual(stones.balance(db, 'a'), 2)
            # With no current-day events the next day is not rewarded.
            self.assertEqual(stones.learning(db, 'a', bank, (today + timedelta(days=1)).isoformat()), [])

    def test_zero_goal_no_rewards_and_future_events_do_not_count(self):
        with server.connect() as db:
            db.execute('INSERT INTO settings VALUES(?,?,?,?)', ('a', 0, 0, 'now'))
            future = dict(id='future', questionId='q', at=(datetime.now(timezone.utc) + timedelta(days=1)).isoformat(),
                          kind='review', value={'answer': 'A', 'grade': 'mastered'})
            db.execute('INSERT INTO events VALUES(?,?,?)', ('a', 'future', json.dumps(future)))
            self.assertEqual(stones.learning(db, 'a', [dict(id='q', answer='A', modes=['考研'])], self.day), [])

    def test_concurrent_claims_and_spends_never_double_credit_or_go_negative(self):
        def claim(_):
            with server.connect() as db:
                db.execute('BEGIN IMMEDIATE')
                return stones.checkin(db, 'a', self.day, 1)
        with ThreadPoolExecutor(max_workers=5) as pool:
            results = list(pool.map(claim, range(8)))
        self.assertEqual(sum(len(r) for r in results), 1)
        def spend(i):
            try:
                with server.connect() as db:
                    db.execute('BEGIN IMMEDIATE')
                    stones.change(db, 'a', -1, 'test spend', 'spend' + str(i), self.day)
                return True
            except ValueError: return False
        with ThreadPoolExecutor(max_workers=5) as pool:
            self.assertEqual(sum(pool.map(spend, range(8))), 1)
        with server.connect() as db: self.assertEqual(stones.balance(db, 'a'), 0)

    def test_full_redemption_exact_price_idempotency_and_renewal(self):
        self.seed()
        data = {'planId': 'month', 'requestKey': 'redeem-test-key-0001', 'expectedPriceFen': 100}
        with server.connect() as db:
            first = self.handler.stone_redeem(db, 'a', data)
            self.assertEqual(first['stones'], 50)
            self.assertEqual(first, self.handler.stone_redeem(db, 'a', data))
            self.assertEqual(stones.balance(db, 'a'), 950)
            expiry = db.execute('SELECT expires_at FROM vip_memberships WHERE user_id=?', ('a',)).fetchone()[0]
            second = self.handler.stone_redeem(db, 'a', {**data, 'requestKey': 'redeem-test-key-0002', 'expectedPriceFen': 690})
            self.assertEqual(second['stones'], 345)
            self.assertEqual(stones.balance(db, 'a'), 605)
            self.assertGreater(db.execute('SELECT expires_at FROM vip_memberships WHERE user_id=?', ('a',)).fetchone()[0], expiry)

    def test_redemption_gate_balance_and_stale_quote(self):
        data = {'planId': 'month', 'requestKey': 'redeem-test-key-0001'}
        with server.connect() as db:
            with self.assertRaises(ValueError): self.handler.stone_redeem(db, 'a', data)
            db.rollback()
            self.assertEqual(db.execute('SELECT COUNT(*) FROM stone_redemptions').fetchone()[0], 0)
        self.seed()
        with server.connect() as db:
            with mock.patch.object(server, 'STONE_REDEMPTIONS_OPEN', False):
                with self.assertRaises(ValueError): self.handler.stone_redeem(db, 'a', data)
            with self.assertRaises(ValueError): self.handler.stone_redeem(db, 'a', {**data, 'expectedPriceFen': 690})
            db.rollback()
            self.assertEqual(stones.balance(db, 'a'), 1000)

    def checkout(self, db, count=20):
        with mock.patch.object(server, 'alipay_config', return_value={}), \
             mock.patch.object(server, 'alipay_page_pay_url', return_value='https://example.test/cashier'):
            return self.handler.alipay_checkout(db, 'a', {'planId': 'month', 'stoneCount': count})

    def test_combo_reserves_once_and_closed_order_refunds_once(self):
        self.seed(50)
        with server.connect() as db:
            first = self.checkout(db)
            self.assertEqual(first['amountFen'], 60)  # ¥1 intro - 20 stones * 2 fen
            self.assertEqual(self.checkout(db)['orderId'], first['orderId'])
            self.assertEqual(stones.balance(db, 'a'), 30)
            with self.assertRaises(ValueError): self.checkout(db, 21)
            with mock.patch.object(server, 'alipay_config', return_value={}), \
                 mock.patch.object(server, 'call_alipay_api', return_value={'out_trade_no': first['orderId']}):
                self.handler.alipay_close(db, 'a', {'orderId': first['orderId']})
            self.assertEqual(stones.balance(db, 'a'), 50)
            db.execute('BEGIN IMMEDIATE')
            stones.release(db, first['orderId'], self.day)
            self.assertEqual(stones.balance(db, 'a'), 50)

    def test_combo_verified_payment_does_not_deduct_again_and_refund_returns_stones(self):
        self.seed(50)
        with server.connect() as db:
            checkout = self.checkout(db)
            order = db.execute('SELECT * FROM payment_orders WHERE id=?', (checkout['orderId'],)).fetchone()
            now = datetime.now(timezone.utc)
            server.apply_paid_membership(db, order, 'alipay', 'trade_12345678', now)
            server.apply_paid_membership(db, order, 'alipay', 'trade_12345678', now)
            self.assertEqual(stones.balance(db, 'a'), 30)
            db.commit()
            with mock.patch.object(server, 'alipay_config', return_value={}), \
                 mock.patch.object(server, 'call_alipay_api', return_value={
                     'out_trade_no': order['id'], 'refund_fee': '0.60', 'fund_change': 'Y'}):
                self.handler.alipay_refund(db, 'a', {'orderId': order['id']})
            self.assertEqual(stones.balance(db, 'a'), 50)

    def test_invalid_combo_and_failed_transaction_leave_balance_intact(self):
        self.seed(10)
        for count in [-1, True, 0.5, 11, 50, 51]:
            with server.connect() as db:
                with self.assertRaises(ValueError): self.checkout(db, count)
                db.rollback()
                self.assertEqual(stones.balance(db, 'a'), 10)
                self.assertEqual(db.execute('SELECT COUNT(*) FROM payment_orders').fetchone()[0], 0)

    def test_deletion_clears_wallet_and_archives_only_unlinked_redemption(self):
        self.seed()
        with server.connect() as db:
            self.handler.stone_redeem(db, 'a', {'planId': 'month', 'requestKey': 'redeem-test-key-0001'})
            db.execute('BEGIN IMMEDIATE')
            server.erase_account(db, 'a', 'session-hash', 'deletion-id')
            self.assertEqual(stones.balance(db, 'a'), 0)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM stone_redemptions').fetchone()[0], 0)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM deleted_stone_redemptions').fetchone()[0], 1)
            self.assertEqual(list(db.execute('PRAGMA foreign_key_check')), [])

    def test_pagination_covers_ledger_without_duplicates(self):
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            for i in range(60): stones.change(db, 'a', 1, 'seed', str(i), self.day)
            page = stones.snapshot(db, 'a')
            second = stones.snapshot(db, 'a', page['nextCursor'])
            self.assertEqual(len(page['items']), 50)
            self.assertEqual(len(second['items']), 10)
            self.assertFalse(set(e['id'] for e in page['items']) & set(e['id'] for e in second['items']))
            self.assertIsNone(second['nextCursor'])
