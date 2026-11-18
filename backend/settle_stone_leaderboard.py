#!/usr/bin/env python3
"""Restricted month-end stone leaderboard settlement entry point.

This program is deliberately not exposed through the HTTP API.  Run it from
the root-owned systemd timer on the first Beijing calendar day of each month;
the default is the just-completed month.  An explicit older month supports a
supervised recovery run, but current/future months are rejected by the ledger.
"""
import argparse
import json
import sys

import server
import stones


def previous_month(today):
    if today.month == 1:
        return f'{today.year - 1:04d}-12'
    return f'{today.year:04d}-{today.month - 1:02d}'


def month_after(month):
    """Return the canonical month after a validated YYYY-MM value."""
    start, _ = stones.leaderboard_month_bounds(month)
    if start.month == 12:
        return f'{start.year + 1:04d}-01'
    return f'{start.year:04d}-{start.month + 1:02d}'


def completed_months_to_settle(db, today):
    """Return safe monthly catch-up work, without retroactive first-run awards.

    A new installation settles just the recently completed month.  Once a
    settlement history exists, a delayed timer fills every subsequent finished
    month in chronological order.  Older one-off recovery remains explicit via
    --month so enabling the feature cannot unexpectedly reward old activity.
    """
    completed = previous_month(today)
    latest = db.execute('''SELECT month FROM stone_monthly_leaderboard_settlements
                           ORDER BY month DESC LIMIT 1''').fetchone()
    if latest is None:
        return [completed]
    month = month_after(latest['month'])
    months = []
    while month <= completed:
        months.append(month)
        month = month_after(month)
    return months


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Settle the completed monthly DentStudy stone leaderboard.')
    choices = parser.add_mutually_exclusive_group()
    choices.add_argument('--month', metavar='YYYY-MM',
                         help='A completed month for a supervised recovery run.')
    choices.add_argument('--catch-up', action='store_true',
                         help='Settle each missed completed month after the last run.')
    args = parser.parse_args(argv)

    server.initialize()
    today = server.beijing_today()
    try:
        with server.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            months = (completed_months_to_settle(db, today) if args.catch_up
                      else [args.month or previous_month(today)])
            results = [stones.settle_monthly_leaderboard(db, month, today)
                       for month in months]
            db.commit()
    except ValueError as error:
        parser.error(str(error))
    result = (results[0] if len(results) == 1 else {'settlements': results})
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
