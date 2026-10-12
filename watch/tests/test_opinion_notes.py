from datetime import date, timedelta
import json
import tempfile
import unittest

from watch.opinion.notes import new_polls_by_day, week_note, write_notes
from watch.store import connect


def body(average, seats, sim=None):
    found = {"average": {"CAN": average}, "seats": {"CAN": seats}}
    if sim is not None:
        found["sim"] = sim
    return found


def averages(lpc, cpc, ndp=10.0, bq=7.0, gpc=3.0, oth=3.9):
    return {"LPC": lpc, "CPC": cpc, "NDP": ndp, "BQ": bq, "GPC": gpc, "OTH": oth}


def seats(lpc, cpc, ndp=20, bq=20, gpc=3, oth=2):
    return {"LPC": lpc, "CPC": cpc, "NDP": ndp, "BQ": bq, "GPC": gpc, "OTH": oth}


def odds(lpc):
    return {"LPC": lpc, "CPC": 0.0, "NDP": 0.0, "BQ": 0.0, "GPC": 0.0, "OTH": 0.0}


class NotesTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.data = temp.name

    def test_06_week_note_text(self):
        prev = body(averages(46.1, 30.0), seats(199, 99))
        cur = body(averages(47.2, 29.9), seats(201, 98))
        self.assertEqual(week_note(prev, cur, 2),
                         "Liberals up 1.1 points to 47.2%. Projection: Liberals 201 seats (+2), "
                         "Conservatives 98 (-1). 2 new polls this week.")

    def test_07_quiet_week_and_odds_sentence(self):
        prev = body(averages(46.1, 30.0), seats(199, 99), sim=dict(majority=odds(0.87)))
        cur = body(averages(46.2, 30.0), seats(199, 99), sim=dict(majority=odds(0.91)))
        text = week_note(prev, cur, 1)
        self.assertTrue(text.startswith("Little change in the polls."), text)
        self.assertIn("Liberal majority odds 91% (+4).", text)
        self.assertEqual(text, "Little change in the polls. Projection: Liberals 199 seats (no change), "
                               "Conservatives 99 (no change). Liberal majority odds 91% (+4). 1 new poll this week.")
        self.assertNotIn("majority odds", week_note(prev, body(averages(46.2, 30.0), seats(199, 99)), 0))

    def test_07b_movers_are_largest_first_and_never_name_others(self):
        prev = body(averages(46.0, 30.0, ndp=10.0, oth=4.0), seats(199, 99))
        cur = body(averages(47.0, 28.9, ndp=9.4, oth=6.0), seats(201, 98))
        text = week_note(prev, cur, 0)
        self.assertTrue(text.startswith("Conservatives down 1.1 points to 28.9%, Liberals up 1.0 points to 47.0%, "
                                        "NDP down 0.6 points to 9.4%."), text)
        self.assertNotIn("Others", text)
        self.assertTrue(text.endswith("No new polls this week."))

    def test_08_write_notes_writes_complete_weeks_only(self):
        with connect(self.data) as db, db:
            # Sunday 27 Sep has no Sunday 20 Sep before it, so its week gets no note.
            day = date(2026, 9, 21)
            while day <= date(2026, 10, 12):
                db.execute("INSERT INTO projections VALUES (?,?)",
                           (day.isoformat(), json.dumps(body(averages(46.0, 30.0), seats(199, 99)))))
                day += timedelta(days=1)
        with connect(self.data) as db, db:
            write_notes(db, date(2026, 10, 12))
            weeks = [row[0] for row in db.execute("SELECT week_of FROM opinion_notes ORDER BY week_of")]
        self.assertEqual(weeks, ["2026-09-28", "2026-10-05"])
        with connect(self.data) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM opinion_notes WHERE week_of='2026-10-12'").fetchone()[0], 0)

    def test_09_backfill_day_polls_do_not_count(self):
        rows = [("338:backfill:a", "CAN", "2026-10-05T12:00:00Z"),
                ("338:backfill:b", "CAN", "2026-10-05T12:00:00Z"),
                ("338:new:c", "CAN", "2026-10-07T13:00:00Z"),
                ("338:new:d", "CAN", "2026-10-07T13:00:00Z"),
                ("338:new:e", "ATL", "2026-10-07T13:00:00Z")]
        with connect(self.data) as db, db:
            for poll_id, region, seen in rows:
                db.execute("INSERT INTO opinion_polls (id,region,firm,end_date,sample,rolling,link,lpc,cpc,ndp,gpc,bq,oth,"
                           "fetched_at,first_seen) VALUES (?,?,'Firm','2026-10-01',1000,1,'l',40,30,10,5,8,7,?,?)",
                           (poll_id, region, seen, seen))
        with connect(self.data) as db, db:
            # The digest counts by first-seen day; the weekly note counts by end date (next test).
            self.assertEqual(new_polls_by_day(db), {"2026-10-07": 2})


if __name__ == "__main__":
    unittest.main()


class WeekPollCountTests(unittest.TestCase):
    def test_week_counts_polls_by_end_date(self):
        import tempfile
        from watch.store import connect
        with tempfile.TemporaryDirectory() as data:
            with connect(data) as db, db:
                body_json = json.dumps(body(averages(46.0, 30.0), seats(199, 99)))
                db.executemany("INSERT INTO projections VALUES (?,?)", [("2026-09-27", body_json), ("2026-10-04", body_json)])
                for i, end in enumerate(("2026-09-28", "2026-10-02", "2026-10-05")):
                    db.execute("INSERT INTO opinion_polls (id, region, firm, end_date, sample, rolling, link, lpc, cpc, ndp, gpc, bq, oth, fetched_at, first_seen) "
                               "VALUES (?, 'CAN', 'F', ?, 1000, 1, '', 45, 30, 10, 3, 7, 5, '2026-10-12T10:00:00Z', '2026-10-12T10:00:00Z')", (f"p{i}", end))
                write_notes(db, date(2026, 10, 12))
                text = db.execute("SELECT text FROM opinion_notes WHERE week_of='2026-09-28'").fetchone()[0]
            self.assertTrue(text.endswith("2 new polls this week."), text)

