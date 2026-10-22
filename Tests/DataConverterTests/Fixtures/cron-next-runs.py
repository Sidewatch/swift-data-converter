# Writes cron-next-runs.json: 300 random schedules and their next five runs after a fixed time,
# from croniter (an independent implementation). Day fields never start with "*/": croniter
# treats that as a restriction (either day field matches), cronie as a star (both must) — the
# hand-written tests cover that rule. Ranges have two different ends: croniter 6.2.4 reads a
# one-value range wrongly (`48-48` as every minute, `3-3/3` as 3 and 6), which the hand-written
# tests pin as cron reads it. Run: pip install croniter; python3 cron-next-runs.py out.json
import random, json, datetime as dt, sys
from croniter import croniter
random.seed(20261022)
def field(lo, hi, names=None, allow_star_step=True):
    k = random.random()
    if k < 0.25: return "*"
    if k < 0.4 and allow_star_step: return f"*/{random.choice([2,3,5,10,15,20])}"
    if k < 0.6:
        a = random.randint(lo, hi - 1); b = random.randint(a + 1, hi); return f"{a}-{b}"
    if k < 0.75:
        a = random.randint(lo, hi - 1); b = random.randint(a + 1, hi); return f"{a}-{b}/{random.choice([2,3,4])}"
    vals = sorted(random.sample(range(lo, hi + 1), random.randint(1, 3)))
    return ",".join(map(str, vals))
cases = []
start = dt.datetime(2026, 10, 22, 14, 37, tzinfo=dt.timezone.utc)
while len(cases) < 300:
    s = " ".join([field(0, 59), field(0, 23), field(1, 31, allow_star_step=False), field(1, 12), field(0, 6, allow_star_step=False)])
    try:
        it = croniter(s, start)
        runs = [it.get_next(dt.datetime).astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") for _ in range(5)]
    except Exception:
        continue  # croniter gives up on schedules with no run soon enough
    if runs[-1] > "2034-01-01": continue
    cases.append({"schedule": s, "runs": runs})
json.dump({"after": start.strftime("%Y-%m-%dT%H:%M:%SZ"), "timeZone": "UTC", "oracle": "croniter, day_or", "cases": cases}, open(sys.argv[1], "w"), indent=1)
print(len(cases), "cases")
