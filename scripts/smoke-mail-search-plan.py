"""Actual local model: semantic extraction + compiled dates, no user mailbox data."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'PlannerRuntime'))
from planner import Planner
p = Planner(sys.argv[1])
clock = {'current_date':'2026-11-15T12:00:00Z','request_started':'2026-11-15T12:00:00Z','time_zone':'Asia/Singapore'}
for task in ['can you help me search for flights tomorrow at email', 'find my flight tmr in mail', 'Find the delivery confirmation for tomorrow in my emails']:
    goal = p.goal(task, clock)
    plan = goal['mail_search']
    print(task, plan, flush=True)
    assert plan and plan['date'] == '2026-11-16'
    assert any('Nov 16' in q for q in plan['queries'])
    assert any('November 16' in q for q in plan['queries'])
    assert all('tomorrow' not in q.lower() and 'tmr' not in q.lower() for q in plan['queries'])
assert p.goal('Open Calculator', clock)['mail_search'] is None
print('Non-email routing passed', flush=True)
rows = [
 {'id':'e1','role':'AXRow','label':'Industry News · Inbox · Today · Aviation market rally','enabled':True,'selectable':True,'selected':False,'actions':[],'editable':False,'value':''},
 {'id':'e2','role':'AXRow','label':'Example Airline · Inbox · 26/10/26 · Your confirmed booking from City A to City B','enabled':True,'selectable':True,'selected':False,'actions':[],'editable':False,'value':''},
 {'id':'e3','role':'AXRow','label':'Travel Deals · Inbox · Today · Winter sale','enabled':True,'selectable':True,'selected':False,'actions':[],'editable':False,'value':''}]
context = dict(clock, observation={'app':'com.apple.mail','name':'Mail','window':'Search, 3 results','elements':rows},
 mail_search={'plan':{'date':'2026-11-16','literal':False},'attempts':[{'query':'flight Nov 16'}]}, evidence=[],history=[{'action':{'kind':'search_mail','value':'flight Nov 16'}}])
action = p.predict('Find my flight tomorrow in my emails', context)
print('Candidate triage:', action, flush=True)
assert action == {'kind':'select','target':'e2'}
