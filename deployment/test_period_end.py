"""Run against staged modules and a temporary SQLite DB; never imports app or live data."""
import datetime
import importlib.util
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from flask import Flask

STAGE = Path(sys.argv.pop(1)).resolve()
sys.path.insert(0, str(STAGE))
import db
import context
spec = importlib.util.spec_from_file_location('period_route_under_test', STAGE / 'daily.py')
route = importlib.util.module_from_spec(spec)
spec.loader.exec_module(route)

class PeriodContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        db.DB_PATH = str(Path(self.temp.name) / 'periods.db')
        c = sqlite3.connect(db.DB_PATH)
        c.execute("CREATE TABLE period_logs (id INTEGER PRIMARY KEY AUTOINCREMENT,start_date TEXT NOT NULL,note TEXT,created_at TEXT)")
        c.execute("INSERT INTO period_logs(start_date,note) VALUES('2026-10-01','preserve me')")
        c.commit(); c.close()
        db.init_db()
        db.init_db()  # Migration is repeatable and preserves legacy rows.
        self.app = Flask(__name__)
        self.app.register_blueprint(route.bp)
        self.client = self.app.test_client()

    def tearDown(self):
        self.temp.cleanup()

    def test_end_preserves_identity_and_context(self):
        before = self.client.get('/api/periods').json[0]
        self.assertIsNone(before['end_date'])
        self.assertEqual(self.client.post('/api/periods/end',json={'id':1,'end_date':'2026-10-05'}).status_code,200)
        self.assertEqual(self.client.post('/api/periods/end',json={'id':1,'end_date':'2026-10-05'}).status_code,200)
        rows = self.client.get('/api/periods').json
        self.assertEqual(len(rows),1)
        self.assertEqual(rows[0],dict(before,end_date='2026-10-05'))
        brief = '\n'.join(context._period_part(datetime.date(2026,10,5)))
        self.assertIn('已记录这次经期结束',brief)
        self.assertNotIn('很可能正在经期',brief)

    def test_validation_and_missing_record_do_not_mutate(self):
        for payload in [{'id':1,'end_date':'2026-09-30'},{'id':True,'end_date':'2026-10-02'},{'id':1,'end_date':'bad'}, {'id':1,'end_date':'2099-01-01'}, {'id':'1','end_date':'2026-10-02'}, ['unexpected']]:
            self.assertEqual(self.client.post('/api/periods/end',json=payload).status_code,400,payload)
        self.assertEqual(self.client.post('/api/periods/end',json={'id':999,'end_date':'2026-10-02'}).status_code,404)
        self.assertIsNone(db.recent_periods()[0]['end_date'])

    def test_start_retry_old_clients_and_delete(self):
        payload={'start_date':'2026-10-02','note':'new'}
        first=self.client.post('/api/periods',json=payload)
        retry=self.client.post('/api/periods',json=payload)
        self.assertEqual(first.status_code,200)
        self.assertEqual(first.json,retry.json)
        pid=first.json['id']
        self.assertEqual(self.client.post('/api/periods/end',json={'id':pid,'end_date':'2026-10-03'}).status_code,200)
        self.assertEqual(self.client.post('/api/periods/end',json={'id':pid,'end_date':'2026-10-04'}).status_code,400)
        self.client.post('/api/periods',json=payload)
        self.assertEqual(db.recent_periods()[0]['end_date'],'2026-10-03')
        self.assertEqual(self.client.post('/api/periods/delete',json={'id':pid}).status_code,200)
        self.assertEqual(len(db.recent_periods()),1)

if __name__ == '__main__':
    unittest.main(verbosity=2)
