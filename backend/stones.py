"""Integer-only loyalty ledger. Call mutations inside BEGIN IMMEDIATE.

These are non-transferable reward points, not deposits or a cash-out balance.
The ledger and the action granting/spending points commit in one transaction.
"""
import hashlib
import json
import secrets
from datetime import date, datetime, timedelta, timezone
from core import business_day, reduce_events

FEN_PER_STONE = 2
CHECKIN_MAKEUP_COST = 5
CHECKIN_MAKEUP_DAILY_LIMIT = 3
LEADERBOARD_SCOPES = ('today', 'week', 'month', 'all')
# Score only the server-owned sources for the product's earn actions.  A
# source is an immutable action identifier, unlike a human-facing reason that
# may be edited during a copy refresh.  Refunds, reserves, operator seeds and
# month-end prizes therefore cannot accidentally become leaderboard points.
LEADERBOARD_EARNED_SOURCE_PREFIXES = (
    'checkin:', 'streak:', 'makeup:streak:', 'learn:', 'review:', 'share:',
    'upload:',
)
# A valid answer event is persisted only after ``server.validate_event`` has
# checked its question, answer and timestamp.  The practice leaderboard uses a
# compact projection of those server-owned events rather than accepting a
# client-reported counter.  Every accepted learning/review answer counts; a
# retry is idempotent only when it reuses the same immutable source event ID.
#
# ``practice_leaderboard_events`` is the deployed v1 per-question/day table.
# Never mutate it in place: live databases may already contain it, and its
# uniqueness constraint cannot represent the product's new per-answer rule.
# The additive v2 projection below is the authoritative source for reads.
PRACTICE_LEADERBOARD_BACKFILL_NAME = 'validated-review-events-v2'
PRACTICE_LEADERBOARD_EVENT_INSERT = '''INSERT OR IGNORE INTO
    practice_leaderboard_answer_events(
      user_id,event_id,question_id,day,completed_at)
    VALUES(?,?,?,?,?)'''
# Profiles may contain a 512 KiB data URL.  Returning 50 such values would
# make a public ranking response impractically large, so fall back to the
# default avatar for unusually large custom images.  Existing approved
# profile images are about 102–129 KiB, so keep enough room for them instead
# of unexpectedly replacing them with the generic book avatar.
MAX_PUBLIC_LEADERBOARD_AVATAR_CHARS = 192 * 1024


def initialize(db, practice_event_cutoff=None):
    db.executescript('''
      CREATE TABLE IF NOT EXISTS stone_ledger(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL REFERENCES users(id),
        delta INTEGER NOT NULL CHECK(delta<>0),
        reason TEXT NOT NULL, source TEXT NOT NULL, day TEXT NOT NULL,
        created_at TEXT NOT NULL, UNIQUE(user_id,source));
      CREATE INDEX IF NOT EXISTS stone_ledger_user ON stone_ledger(user_id,id);
      CREATE TABLE IF NOT EXISTS stone_uploads(
        user_id TEXT NOT NULL REFERENCES users(id), fingerprint TEXT NOT NULL,
        day TEXT NOT NULL, PRIMARY KEY(user_id,fingerprint));
      CREATE TABLE IF NOT EXISTS stone_daily_tasks(
        user_id TEXT NOT NULL REFERENCES users(id), day TEXT NOT NULL,
        new_target INTEGER NOT NULL, review_target INTEGER NOT NULL,
        review_ids TEXT NOT NULL, eligible_ids TEXT NOT NULL,
        PRIMARY KEY(user_id,day));
      CREATE TABLE IF NOT EXISTS stone_checkin_makeups(
        user_id TEXT NOT NULL REFERENCES users(id), checkin_date TEXT NOT NULL,
        made_on TEXT NOT NULL, created_at TEXT NOT NULL,
        PRIMARY KEY(user_id,checkin_date));
      CREATE INDEX IF NOT EXISTS stone_checkin_makeups_user_day
        ON stone_checkin_makeups(user_id,made_on);
      CREATE TABLE IF NOT EXISTS stone_leaderboard_preferences(
        user_id TEXT PRIMARY KEY REFERENCES users(id),
        enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),
        updated_at TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS stone_leaderboard_preferences_enabled
        ON stone_leaderboard_preferences(enabled,user_id);
      CREATE TABLE IF NOT EXISTS practice_leaderboard_events(
        user_id TEXT NOT NULL REFERENCES users(id),
        question_id TEXT NOT NULL, day TEXT NOT NULL,
        first_event_at TEXT NOT NULL, first_event_id TEXT NOT NULL,
        PRIMARY KEY(user_id,day,question_id));
      CREATE INDEX IF NOT EXISTS practice_leaderboard_events_day_user
        ON practice_leaderboard_events(day,user_id,first_event_at);
      -- V2 intentionally records every accepted answer event.  Keep v1 above
      -- intact for a safe, additive production migration.
      CREATE TABLE IF NOT EXISTS practice_leaderboard_answer_events(
        user_id TEXT NOT NULL REFERENCES users(id),
        event_id TEXT NOT NULL, question_id TEXT NOT NULL, day TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        PRIMARY KEY(user_id,event_id));
      CREATE INDEX IF NOT EXISTS practice_leaderboard_answer_events_day_user
        ON practice_leaderboard_answer_events(day,user_id,completed_at,event_id);
      CREATE TABLE IF NOT EXISTS practice_leaderboard_backfills(
        name TEXT PRIMARY KEY, completed_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS stone_monthly_leaderboard_settlements(
        month TEXT PRIMARY KEY, settled_at TEXT NOT NULL,
        award_count INTEGER NOT NULL CHECK(award_count>=0));
      CREATE TABLE IF NOT EXISTS stone_monthly_leaderboard_awards(
        month TEXT NOT NULL REFERENCES stone_monthly_leaderboard_settlements(month),
        user_id TEXT NOT NULL REFERENCES users(id),
        rank INTEGER NOT NULL CHECK(rank BETWEEN 1 AND 50),
        score INTEGER NOT NULL CHECK(score>0), reward INTEGER NOT NULL CHECK(reward>0),
        settled_at TEXT NOT NULL, PRIMARY KEY(month,user_id), UNIQUE(month,rank));
      CREATE INDEX IF NOT EXISTS stone_monthly_leaderboard_awards_user
        ON stone_monthly_leaderboard_awards(user_id);
      CREATE TABLE IF NOT EXISTS deleted_stone_monthly_leaderboard_awards(
        id INTEGER PRIMARY KEY AUTOINCREMENT, month TEXT NOT NULL,
        rank INTEGER NOT NULL, score INTEGER NOT NULL, reward INTEGER NOT NULL,
        settled_at TEXT NOT NULL, deleted_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS stone_redemptions(
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
        request_key TEXT NOT NULL, plan_id TEXT NOT NULL, stones INTEGER NOT NULL,
        price_fen INTEGER NOT NULL, created_at TEXT NOT NULL,
        expires_at TEXT, UNIQUE(user_id,request_key));
      CREATE TABLE IF NOT EXISTS deleted_stone_redemptions(
        id TEXT PRIMARY KEY, plan_id TEXT NOT NULL, stones INTEGER NOT NULL,
        price_fen INTEGER NOT NULL, created_at TEXT NOT NULL, deleted_at TEXT NOT NULL);
    ''')
    # Use a new name so an early preview build's reason-based index is not
    # mistaken for this source-based index during an in-place upgrade.
    db.execute('''CREATE INDEX IF NOT EXISTS stone_ledger_leaderboard_source
                  ON stone_ledger(day,source,user_id)''')
    columns = {r['name'] for r in db.execute('PRAGMA table_info(payment_orders)')}
    if 'stone_count' not in columns:
        db.execute('ALTER TABLE payment_orders ADD COLUMN stone_count INTEGER NOT NULL DEFAULT 0')
    if 'total_fen' not in columns:
        db.execute('ALTER TABLE payment_orders ADD COLUMN total_fen INTEGER')
    # Existing installations already have validated answer events in the
    # source-of-truth `events` table.  Backfill exactly once, within this same
    # migration transaction, so a restart never double counts historical work.
    _backfill_practice_leaderboard_answer_events(db, practice_event_cutoff)


def balance(db, uid):
    return db.execute('SELECT COALESCE(SUM(delta),0) FROM stone_ledger WHERE user_id=?',
                      (uid,)).fetchone()[0]


def entry(row):
    return dict(id=row['id'], amount=row['delta'], reason=row['reason'],
                createdAt=row['created_at'])


def change(db, uid, delta, reason, source, day):
    if not db.in_transaction:
        raise RuntimeError('Stone writes require an explicit transaction')
    if type(delta) is not int or delta == 0:
        raise ValueError('石头数量须为非零整数')
    existing = db.execute('SELECT * FROM stone_ledger WHERE user_id=? AND source=?',
                          (uid, source)).fetchone()
    if existing:
        if existing['delta'] != delta or existing['reason'] != reason:
            raise ValueError('石头交易编号冲突')
        return []
    if balance(db, uid) + delta < 0:
        raise ValueError('石头还差一点，先学习攒一攒吧')
    now = datetime.now(timezone.utc).isoformat(timespec='seconds')
    cur = db.execute('''INSERT INTO stone_ledger(user_id,delta,reason,source,day,created_at)
                        VALUES(?,?,?,?,?,?)''', (uid, delta, reason, source, day, now))
    return [dict(id=cur.lastrowid, amount=delta, reason=reason, createdAt=now)]


def checkin(db, uid, day, streak):
    rewards = change(db, uid, 1, '每日签到', 'checkin:' + day, day)
    if streak > 0 and streak % 7 == 0:
        rewards += change(db, uid, 7, '连续签到满七天', 'streak:' + day, day)
    return rewards


def _current_checkin_streak(db, uid, today):
    """Return the displayed consecutive streak and the day it ends on."""
    signed = {date.fromisoformat(row['checkin_date']) for row in db.execute(
        'SELECT checkin_date FROM daily_checkins WHERE user_id=?', (uid,))}
    anchor = today if today in signed else today - timedelta(days=1)
    streak = 0
    while anchor in signed:
        streak += 1
        anchor -= timedelta(days=1)
    return streak, anchor + timedelta(days=1)


def makeup_checkin(db, uid, target_day, today):
    """Spend stones to mark one missed past check-in, atomically.

    The caller must own a SQLite writer transaction.  A restored date never
    receives the normal +1 check-in reward: it costs five stones.  It can,
    however, repair the currently displayed streak and unlock the same +7
    seven-day milestone that an uninterrupted streak would have earned.
    """
    if not db.in_transaction:
        raise RuntimeError('补签须在显式事务中执行')
    if type(target_day) is not str or type(today) is not date:
        raise ValueError('补签日期无效')
    try:
        target = date.fromisoformat(target_day)
    except ValueError as error:
        raise ValueError('补签日期无效') from error
    if target.isoformat() != target_day or not 2026 <= target.year <= 2035:
        raise ValueError('补签日期无效')
    if target >= today:
        raise ValueError('仅可补签过去未签到的日期')
    if db.execute('''SELECT 1 FROM daily_checkins
                   WHERE user_id=? AND checkin_date=?''',
                  (uid, target_day)).fetchone():
        raise ValueError('该日期已经签到，无需补签')
    used = db.execute('''SELECT COUNT(*) FROM stone_checkin_makeups
                         WHERE user_id=? AND made_on=?''',
                      (uid, today.isoformat())).fetchone()[0]
    if used >= CHECKIN_MAKEUP_DAILY_LIMIT:
        raise ValueError(f'每天最多补签 {CHECKIN_MAKEUP_DAILY_LIMIT} 次')

    # The debit, restored date and audit record are one transaction.  The
    # unique keys plus BEGIN IMMEDIATE make retried or concurrent claims safe.
    # Keep the pre-makeup streak so an unrelated old date cannot repeatedly
    # mint a reward merely because the user already has a seven-day streak.
    prior_streak, _ = _current_checkin_streak(db, uid, today)
    rewards = change(db, uid, -CHECKIN_MAKEUP_COST, '补签消耗',
                     'makeup:cost:' + target_day, today.isoformat())
    now = datetime.now(timezone.utc).isoformat(timespec='seconds')
    db.execute('''INSERT INTO daily_checkins(user_id,checkin_date,created_at)
                  VALUES(?,?,?)''', (uid, target_day, now))
    db.execute('''INSERT INTO stone_checkin_makeups(
                    user_id,checkin_date,made_on,created_at) VALUES(?,?,?,?)''',
               (uid, target_day, today.isoformat(), now))

    streak, streak_end = _current_checkin_streak(db, uid, today)
    if streak > prior_streak and streak % 7 == 0:
        rewards += change(
            db, uid, 7, '补签后连续签到满七天',
            f'makeup:streak:{target_day}:{streak_end.isoformat()}:{streak}',
            today.isoformat())
    return rewards


def _leaderboard_scope_bounds(scope, today):
    if scope not in LEADERBOARD_SCOPES:
        raise ValueError('排行榜范围无效')
    if type(today) is not date:
        raise ValueError('排行榜日期无效')
    if scope == 'all':
        return None, None
    if scope == 'today':
        return today, today
    if scope == 'week':
        return today - timedelta(days=today.weekday()), today
    return date(today.year, today.month, 1), today


def _practice_event_details(event, cutoff=None):
    """Project one already-validated answer event into a leaderboard row.

    This deliberately does not look at client-provided counters.  A malformed
    legacy database row is ignored defensively, while normal rows have already
    passed `server.validate_event` before entering the immutable events table.
    """
    if not isinstance(event, dict) or event.get('kind') != 'review':
        return None
    question_id = event.get('questionId')
    event_id = event.get('id')
    if (not isinstance(question_id, str) or not question_id or
            not isinstance(event_id, str) or not event_id or
            not isinstance(event.get('value'), dict)):
        return None
    timestamp = event.get('at')
    if not isinstance(timestamp, str):
        return None
    try:
        parsed = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    # Normalize before comparing with the optional one-time history-reset
    # cutoff.  The server stores answer timestamps in this canonical UTC form.
    parsed = parsed.astimezone(timezone.utc)
    if cutoff:
        try:
            reset_at = datetime.fromisoformat(cutoff.replace('Z', '+00:00'))
            if reset_at.tzinfo is not None and parsed < reset_at.astimezone(timezone.utc):
                return None
        except (TypeError, ValueError):
            # The deployment setting is validated where it is used for sync;
            # do not let a malformed optional value erase historical ranking.
            pass
    at = parsed.isoformat(timespec='microseconds').replace('+00:00', 'Z')
    return question_id, business_day(at).isoformat(), at, event_id


def record_practice_leaderboard_event(db, uid, event, cutoff=None):
    """Record one validated answer event exactly once.

    The caller normally runs inside the `/v1/sync` writer transaction.  Keeping
    this compact projection in the same transaction makes ranking reads fast
    while preserving the original answer event as the source of truth.  The
    source `events` table identifies events by `(user_id, id)`, so the v2
    projection uses that same account-scoped identity for idempotence.
    """
    details = _practice_event_details(event, cutoff)
    if details is None:
        return False
    question_id, day, at, event_id = details
    return db.execute(PRACTICE_LEADERBOARD_EVENT_INSERT,
                      (uid, event_id, question_id, day, at)).rowcount == 1


def _backfill_practice_leaderboard_answer_events(db, cutoff=None):
    """Backfill the additive v2 projection from immutable answer events."""
    done = db.execute('''SELECT 1 FROM practice_leaderboard_backfills
                         WHERE name=?''',
                      (PRACTICE_LEADERBOARD_BACKFILL_NAME,)).fetchone()
    if done:
        return
    # Page through older events.  Production history can be large, and this
    # one-time migration must not hold every payload in memory or issue an
    # unbounded query while it writes the compact projection.
    last_rowid = 0
    while True:
        rows = db.execute('''SELECT rowid,user_id,id,payload FROM events
                             WHERE rowid>? ORDER BY rowid LIMIT 500''',
                          (last_rowid,)).fetchall()
        if not rows:
            break
        values = []
        for row in rows:
            try:
                event = json.loads(row['payload'])
            except (TypeError, json.JSONDecodeError):
                continue
            details = _practice_event_details(event, cutoff)
            # A server-created source row always has the same ID in its
            # primary-key column and payload.  Keep that invariant during a
            # migration too, so a corrupted legacy payload cannot create an
            # unrelated ranking event.
            if details is not None and details[-1] == row['id']:
                question_id, day, at, event_id = details
                values.append((row['user_id'], event_id, question_id, day, at))
        if values:
            db.executemany(PRACTICE_LEADERBOARD_EVENT_INSERT, values)
        last_rowid = rows[-1]['rowid']
    db.execute('''INSERT INTO practice_leaderboard_backfills(name,completed_at)
                  VALUES(?,?)''',
               (PRACTICE_LEADERBOARD_BACKFILL_NAME,
                datetime.now(timezone.utc).isoformat(timespec='seconds')))


def _practice_leaderboard_rows(db, start=None, end=None):
    """Return public practice ranking rows from server-validated events only."""
    clauses = ['COALESCE(preference.enabled,1)=1']
    now = datetime.now(timezone.utc).isoformat(timespec='seconds')
    values = [MAX_PUBLIC_LEADERBOARD_AVATAR_CHARS, now]
    if start is not None:
        clauses.append('e.day>=?')
        values.append(start.isoformat())
    if end is not None:
        clauses.append('e.day<=?')
        values.append(end.isoformat())
    return db.execute(f'''SELECT e.user_id,
            COALESCE(NULLIF(p.nickname,''),'齿间同学') AS nickname,
            CASE WHEN p.avatar IS NULL OR p.avatar='' THEN 'book'
                 WHEN length(p.avatar)<=? THEN p.avatar ELSE 'book' END AS avatar,
            EXISTS(SELECT 1 FROM vip_memberships vip
                   WHERE vip.user_id=e.user_id AND vip.status='active'
                     AND (vip.expires_at IS NULL OR vip.expires_at>?)) AS vipBadge,
            COUNT(*) AS score,
            MIN(e.completed_at || '/' || e.event_id) AS first_event_key
        FROM practice_leaderboard_answer_events e
        LEFT JOIN stone_leaderboard_preferences preference
          ON preference.user_id=e.user_id
        LEFT JOIN profiles p ON p.user_id=e.user_id
        WHERE {' AND '.join(clauses)}
        GROUP BY e.user_id
        HAVING COUNT(*)>0
        -- Same score: the first eligible answer wins.  Event IDs only settle
        -- an exact-timestamp tie and are never returned to a client.
        ORDER BY score DESC,first_event_key ASC''',
                      values).fetchall()


def _earned_leaderboard_rows(db, start=None, end=None):
    """Return participating earners, sorted without public account IDs.

    The ranking is on by default.  A missing preference is intentionally
    treated as enabled so that existing users receive the new default without
    an intrusive migration; only an explicit ``enabled=0`` opts someone out.
    """
    source_conditions = ' OR '.join(
        'l.source LIKE ?' for _ in LEADERBOARD_EARNED_SOURCE_PREFIXES)
    clauses = [
        'l.delta>0',
        '(' + source_conditions + ')',
    ]
    now = datetime.now(timezone.utc).isoformat(timespec='seconds')
    values = [MAX_PUBLIC_LEADERBOARD_AVATAR_CHARS, now]
    values += [prefix + '%' for prefix in LEADERBOARD_EARNED_SOURCE_PREFIXES]
    if start is not None:
        clauses.append('l.day>=?')
        values.append(start.isoformat())
    if end is not None:
        clauses.append('l.day<=?')
        values.append(end.isoformat())
    return db.execute(f'''SELECT l.user_id,
            COALESCE(NULLIF(p.nickname,''),'齿间同学') AS nickname,
            CASE WHEN p.avatar IS NULL OR p.avatar='' THEN 'book'
                 WHEN length(p.avatar)<=? THEN p.avatar ELSE 'book' END AS avatar,
            EXISTS(SELECT 1 FROM vip_memberships vip
                   WHERE vip.user_id=l.user_id AND vip.status='active'
                     AND (vip.expires_at IS NULL OR vip.expires_at>?)) AS vipBadge,
            SUM(l.delta) AS score,
            MIN(l.id) AS first_earned_id
        FROM stone_ledger l
        LEFT JOIN stone_leaderboard_preferences preference
          ON preference.user_id=l.user_id
        LEFT JOIN profiles p ON p.user_id=l.user_id
        WHERE {' AND '.join(clauses)} AND COALESCE(preference.enabled,1)=1
        GROUP BY l.user_id
        HAVING SUM(l.delta)>0
        -- Same score: the first qualifying stone received wins.  Ledger IDs
        -- are globally unique and chronological, avoiding a hidden account-ID
        -- tie-breaker for a monetary monthly prize.
        ORDER BY score DESC,first_earned_id ASC''', values).fetchall()


def _leaderboard_range_label(scope, start, end):
    if scope == 'all':
        return '累计获得的有效石头'
    if start == end:
        return f'北京时间 {start.isoformat()}'
    return f'北京时间 {start.isoformat()} 至 {end.isoformat()}'


def leaderboard(db, uid, scope, today):
    """Build a privacy-safe top-50 plus the requesting user's own position."""
    start, end = _leaderboard_scope_bounds(scope, today)
    rows = _earned_leaderboard_rows(db, start, end)
    own_preference = db.execute('''SELECT enabled FROM stone_leaderboard_preferences
                                   WHERE user_id=?''', (uid,)).fetchone()
    participating = own_preference is None or bool(own_preference['enabled'])
    now = datetime.now(timezone.utc).isoformat(timespec='seconds')
    own_profile = db.execute('''SELECT
            COALESCE(NULLIF(nickname,''),'齿间同学') AS nickname,
            CASE WHEN avatar IS NULL OR avatar='' THEN 'book'
                 WHEN length(avatar)<=? THEN avatar ELSE 'book' END AS avatar,
            EXISTS(SELECT 1 FROM vip_memberships vip
                   WHERE vip.user_id=profiles.user_id AND vip.status='active'
                     AND (vip.expires_at IS NULL OR vip.expires_at>?)) AS vipBadge
        FROM profiles WHERE user_id=?''',
                             (MAX_PUBLIC_LEADERBOARD_AVATAR_CHARS, now, uid)).fetchone()
    own_rank = None
    own_score = 0
    for index, row in enumerate(rows, 1):
        if row['user_id'] == uid:
            own_rank, own_score = index, row['score']
            break
    entries = [
        {'rank': index, 'userId': row['user_id'], 'nickname': row['nickname'],
         'avatar': row['avatar'], 'vipBadge': bool(row['vipBadge']),
         'score': row['score']}
        for index, row in enumerate(rows[:50], 1)
    ]
    me = {
        # This is the account's opaque random identifier, not an email.  It
        # lets authenticated clients open a public profile card from an avatar
        # without adding a lookup by nickname.
        'userId': uid,
        'participating': participating,
        # Do not disclose an exact position outside the public top 50.
        'rank': own_rank if own_rank is not None and own_rank <= 50 else None,
        'displayRank': (str(own_rank) if own_rank is not None and own_rank <= 50
                        else '50+'),
        'score': own_score,
        # This projection belongs only to the authenticated requester.  It
        # lets the app render the self row with the same actual avatar and
        # nickname as a public row, without adding a separate profile fetch
        # or returning a hidden account identifier.
        'nickname': own_profile['nickname'] if own_profile else '齿间同学',
        'avatar': own_profile['avatar'] if own_profile else 'book',
        'vipBadge': bool(own_profile['vipBadge']) if own_profile else False,
    }
    return {
        'scope': scope,
        'today': today.isoformat(),
        'rangeStart': start.isoformat() if start else None,
        'rangeEnd': end.isoformat() if end else None,
        # `range` and `me` are the mobile contract.  Retain `self` during
        # rollout so an already-cached older client remains compatible.
        'range': _leaderboard_range_label(scope, start, end),
        'tieBreak': '同分按最早获得有效石头的时间排序',
        'entries': entries,
        'me': me,
        'self': me,
    }


def _practice_leaderboard_range_label(scope, start, end):
    if scope == 'all':
        return '累计完成的有效题目'
    if start == end:
        return f'北京时间 {start.isoformat()}'
    return f'北京时间 {start.isoformat()} 至 {end.isoformat()}'


def practice_leaderboard(db, uid, scope, today):
    """Build the public top-50 for server-verified completed questions.

    This deliberately shares the stone board's participation preference and
    profile projection.  Opting out hides a learner from both boards, while a
    zero score never creates a row in either one.
    """
    start, end = _leaderboard_scope_bounds(scope, today)
    rows = _practice_leaderboard_rows(db, start, end)
    own_preference = db.execute('''SELECT enabled FROM stone_leaderboard_preferences
                                   WHERE user_id=?''', (uid,)).fetchone()
    participating = own_preference is None or bool(own_preference['enabled'])
    now = datetime.now(timezone.utc).isoformat(timespec='seconds')
    own_profile = db.execute('''SELECT
            COALESCE(NULLIF(nickname,''),'齿间同学') AS nickname,
            CASE WHEN avatar IS NULL OR avatar='' THEN 'book'
                 WHEN length(avatar)<=? THEN avatar ELSE 'book' END AS avatar,
            EXISTS(SELECT 1 FROM vip_memberships vip
                   WHERE vip.user_id=profiles.user_id AND vip.status='active'
                     AND (vip.expires_at IS NULL OR vip.expires_at>?)) AS vipBadge
        FROM profiles WHERE user_id=?''',
                             (MAX_PUBLIC_LEADERBOARD_AVATAR_CHARS, now, uid)).fetchone()
    own_rank = None
    own_score = 0
    for index, row in enumerate(rows, 1):
        if row['user_id'] == uid:
            own_rank, own_score = index, row['score']
            break
    entries = [
        {'rank': index, 'userId': row['user_id'], 'nickname': row['nickname'],
         'avatar': row['avatar'], 'vipBadge': bool(row['vipBadge']),
         'score': row['score']}
        for index, row in enumerate(rows[:50], 1)
    ]
    me = {
        'userId': uid,
        'participating': participating,
        'rank': own_rank if own_rank is not None and own_rank <= 50 else None,
        'displayRank': (str(own_rank) if own_rank is not None and own_rank <= 50
                        else '50+'),
        'score': own_score,
        'nickname': own_profile['nickname'] if own_profile else '齿间同学',
        'avatar': own_profile['avatar'] if own_profile else 'book',
        'vipBadge': bool(own_profile['vipBadge']) if own_profile else False,
    }
    return {
        'scope': scope,
        'today': today.isoformat(),
        'rangeStart': start.isoformat() if start else None,
        'rangeEnd': end.isoformat() if end else None,
        'range': _practice_leaderboard_range_label(scope, start, end),
        'tieBreak': '同分按最早完成有效题目的时间排序',
        # The contract makes explicit that favorites/notes are absent.  Every
        # distinct server-confirmed answer event is one completed question.
        'countingRule': '每次服务器确认的学习或复习答题计 1；0 题暂不排名',
        'entries': entries,
        'me': me,
        'self': me,
    }


def set_leaderboard_participation(db, uid, enabled):
    if not db.in_transaction:
        raise RuntimeError('排行榜设置须在显式事务中执行')
    if type(enabled) is not bool:
        raise ValueError('排行榜参与设置无效')
    updated_at = datetime.now(timezone.utc).isoformat(timespec='seconds')
    db.execute('''INSERT INTO stone_leaderboard_preferences(user_id,enabled,updated_at)
                  VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET
                  enabled=excluded.enabled,updated_at=excluded.updated_at''',
               (uid, int(enabled), updated_at))
    return {'enabled': enabled}


def leaderboard_month_bounds(month):
    if type(month) is not str or len(month) != 7:
        raise ValueError('月榜月份无效')
    try:
        start = date.fromisoformat(month + '-01')
    except ValueError as error:
        raise ValueError('月榜月份无效') from error
    if start.strftime('%Y-%m') != month:
        raise ValueError('月榜月份无效')
    if start.month == 12:
        next_month = date(start.year + 1, 1, 1)
    else:
        next_month = date(start.year, start.month + 1, 1)
    return start, next_month - timedelta(days=1)


def monthly_leaderboard_reward(rank):
    if rank == 1:
        return 30
    if rank == 2:
        return 20
    if rank == 3:
        return 10
    if 4 <= rank <= 10:
        return 5
    if 11 <= rank <= 50:
        return 2
    return 0


def settle_monthly_leaderboard(db, month, settled_day):
    """Award one completed Beijing calendar month, atomically and idempotently."""
    if not db.in_transaction:
        raise RuntimeError('月榜结算须在显式事务中执行')
    if type(settled_day) is not date:
        raise ValueError('月榜结算日期无效')
    start, end = leaderboard_month_bounds(month)
    if start >= date(settled_day.year, settled_day.month, 1):
        raise ValueError('只能结算已经结束的月份')
    existing = db.execute('''SELECT award_count FROM stone_monthly_leaderboard_settlements
                             WHERE month=?''', (month,)).fetchone()
    if existing:
        return {'month': month, 'alreadySettled': True,
                'awardCount': existing['award_count']}

    rows = _earned_leaderboard_rows(db, start, end)
    settled_at = datetime.now(timezone.utc).isoformat(timespec='seconds')
    db.execute('''INSERT INTO stone_monthly_leaderboard_settlements(
                    month,settled_at,award_count) VALUES(?,?,0)''',
               (month, settled_at))
    award_count = 0
    for rank, row in enumerate(rows[:50], 1):
        reward = monthly_leaderboard_reward(rank)
        if reward == 0:
            continue
        change(db, row['user_id'], reward, '月榜奖励',
               f'leaderboard:{month}:{row["user_id"]}', settled_day.isoformat())
        db.execute('''INSERT INTO stone_monthly_leaderboard_awards(
                        month,user_id,rank,score,reward,settled_at)
                      VALUES(?,?,?,?,?,?)''',
                   (month, row['user_id'], rank, row['score'], reward, settled_at))
        award_count += 1
    db.execute('''UPDATE stone_monthly_leaderboard_settlements SET award_count=?
                  WHERE month=?''', (award_count, month))
    return {'month': month, 'alreadySettled': False, 'awardCount': award_count}


def upload(db, uid, bank, day):
    # Ignore JSON whitespace, filenames, bank metadata, question IDs and order.
    content = sorted(json.dumps({k: q.get(k) for k in ('stem', 'options', 'answer', 'type')},
                                ensure_ascii=False, sort_keys=True)
                     for q in bank['questions'])
    fingerprint = hashlib.sha256(json.dumps(content, ensure_ascii=False).encode()).hexdigest()
    inserted = db.execute('INSERT OR IGNORE INTO stone_uploads VALUES(?,?,?)',
                          (uid, fingerprint, day)).rowcount
    count = db.execute('''SELECT COUNT(*) FROM stone_ledger
                          WHERE user_id=? AND day=? AND reason='上传题库' ''', (uid, day)).fetchone()[0]
    if not inserted or not content or count >= 3:
        return []
    return change(db, uid, 1, '上传题库', 'upload:' + fingerprint, day)


def learning(db, uid, bank, day, mode='考研'):
    """Freeze daily targets from server-known history; no client completion flag.

    Only current Beijing-day, server-validated events count. Repeated answers
    to one question do not increment progress. Imported/local-only IDs cannot
    earn learning rewards. Zero-task days never mint points.
    """
    events = [json.loads(r['payload']) for r in db.execute(
        'SELECT payload FROM events WHERE user_id=?', (uid,))]
    now = datetime.now(timezone.utc)
    events = [e for e in events if datetime.fromisoformat(e['at'].replace('Z', '+00:00')) <= now]
    before = [e for e in events if business_day(e['at']).isoformat() < day]
    states, _ = reduce_events(before, bank)
    task = db.execute('SELECT * FROM stone_daily_tasks WHERE user_id=? AND day=?',
                      (uid, day)).fetchone()
    if task is None:
        eligible = [q for q in bank if not q.get('isDemo') and mode in q.get('modes', [])]
        fresh = [q['id'] for q in eligible if not states.get(q['id'], {}).get('lastDay')]
        due = [q['id'] for q in eligible if states.get(q['id'], {}).get('due')
               and states[q['id']]['due'] <= day]
        settings = db.execute('SELECT * FROM settings WHERE user_id=?', (uid,)).fetchone()
        new_limit = settings['daily_new_limit'] if settings else 20
        review_limit = settings['daily_review_target'] if settings else None
        db.execute('INSERT INTO stone_daily_tasks VALUES(?,?,?,?,?,?)',
                   (uid, day, min(new_limit, len(fresh)),
                    len(due) if review_limit is None else min(review_limit, len(due)),
                    json.dumps(due), json.dumps(fresh)))
        task = db.execute('SELECT * FROM stone_daily_tasks WHERE user_id=? AND day=?',
                          (uid, day)).fetchone()
    done = {e['questionId'] for e in events if e['kind'] == 'review'
            and business_day(e['at']).isoformat() == day}
    rewards = []
    for kind, title, target, ids in (
            ('learn', '每日学习完成', task['new_target'], task['eligible_ids']),
            ('review', '每日复习完成', task['review_target'], task['review_ids'])):
        if target > 0 and len(done.intersection(json.loads(ids))) >= target:
            rewards += change(db, uid, 1, title, kind + ':' + day, day)
    return rewards


def snapshot(db, uid, before=None, today=None):
    if before is not None and (type(before) is not int or before < 1):
        raise ValueError('明细分页编号无效')
    if today is None:
        today = datetime.now(timezone(timedelta(hours=8))).date()
    if type(today) is not date:
        raise ValueError('石头日期无效')
    rows = db.execute('''SELECT * FROM stone_ledger WHERE user_id=? AND id<?
                         ORDER BY id DESC LIMIT 51''', (uid, before or 9223372036854775807)).fetchall()
    reserved = db.execute('''SELECT COALESCE(SUM(stone_count),0) FROM payment_orders
                             WHERE user_id=? AND status='created' ''', (uid,)).fetchone()[0]
    # Do not infer today's share state from the most recent ledger page: a
    # prolific learner can push that row beyond the first fifty entries.
    # The immutable daily source is the authoritative one-claim-per-day flag.
    share_claimed_today = db.execute(
        '''SELECT 1 FROM stone_ledger WHERE user_id=? AND source=? LIMIT 1''',
        (uid, 'share:' + today.isoformat())).fetchone() is not None
    # This must not be inferred from the first ledger page: an active account
    # can have more than fifty newer transactions.  The immutable upload
    # source is the authoritative per-Beijing-day reward count.
    upload_reward_count_today = db.execute(
        '''SELECT COUNT(*) FROM stone_ledger
           WHERE user_id=? AND day=? AND delta>0 AND source LIKE 'upload:%' ''',
        (uid, today.isoformat())).fetchone()[0]
    return dict(balance=balance(db, uid), reserved=reserved, fenPerStone=FEN_PER_STONE,
                shareClaimedToday=share_claimed_today,
                uploadRewardCountToday=min(3, upload_reward_count_today),
                items=[entry(r) for r in rows[:50]],
                nextCursor=rows[49]['id'] if len(rows) > 50 else None)


def reserve(db, uid, count, order_id, total_fen, day):
    if type(count) is not int or count < 0 or count * FEN_PER_STONE >= total_fen:
        raise ValueError('组合支付石头数量无效；全额抵扣请选择石头兑换')
    if count:
        change(db, uid, -count, '组合支付预扣', 'reserve:' + order_id, day)


def release(db, order_id, day):
    order = db.execute('SELECT * FROM payment_orders WHERE id=?', (order_id,)).fetchone()
    if order and order['stone_count'] and order['status'] in ('closed', 'refunded'):
        change(db, order['user_id'], order['stone_count'], '订单关闭或退款返还',
               'release:' + order_id, day)


def delete_account(db, uid, now):
    db.execute('''INSERT INTO deleted_stone_redemptions
                  SELECT id,plan_id,stones,price_fen,created_at,? FROM stone_redemptions
                  WHERE user_id=?''', (now, uid))
    # Settlement audit remains useful for aggregate accounting, but it must
    # not retain a deleted account's ID, name, avatar or recoverable handle.
    db.execute('''INSERT INTO deleted_stone_monthly_leaderboard_awards(
                    month,rank,score,reward,settled_at,deleted_at)
                  SELECT month,rank,score,reward,settled_at,?
                  FROM stone_monthly_leaderboard_awards WHERE user_id=?''',
               (now, uid))
    for table in ('stone_ledger', 'stone_uploads', 'stone_daily_tasks',
                  'stone_checkin_makeups', 'stone_leaderboard_preferences',
                  'practice_leaderboard_events',
                  'practice_leaderboard_answer_events',
                  'stone_monthly_leaderboard_awards', 'stone_redemptions'):
        db.execute(f'DELETE FROM {table} WHERE user_id=?', (uid,))
