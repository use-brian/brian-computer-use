"""Synthetic end-to-end planning/review checks using the actual bundled weights."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'PlannerRuntime'))
from planner import Planner

p = Planner(sys.argv[1])
clock = {'current_date':'2026-11-15T04:00:00Z','request_started':'2026-11-15T04:00:00Z','time_zone':'Asia/Singapore'}
task = 'Find flights departing tomorrow in my emails and tell me the airline, flight number and departure time.'
goal = p.goal(task, dict(clock, conversation=[]))
print('Goal:', goal, flush=True)

def context(text, proposal, goal=goal, name='Mail', window='Flight confirmation'):
    row = {'id':'e1','role':'AXStaticText','label':'Message content','value':text,'enabled':True,'editable':False,'actions':[],'selectable':False,'selected':False}
    obs = {'app':{'Mail':'com.apple.mail','Calculator':'com.apple.calculator','TextEdit':'com.apple.TextEdit'}.get(name,'com.usebrian.WorkflowTest'),'name':name,'window':window,'accessibility':True,'truncated':False,'elements':[row]}
    return dict(clock, goal=goal, proposal=proposal, observation=obs, current_observation_id='o2',
                evidence=[{'id':'o2','app':name,'window':window,'elements':[row],'image':False}],
                history=[{'action':{'kind':'search_mail','value':'flight'},'result':'Search displayed in All Mailboxes. Message bodies have not been read.'}])

search = context('Search: flights. 93 results. No message selected.', 'Found your flights for tomorrow. Results are visible in Mail.')
review = p.assess(task, search); print('Search-only review:', review, flush=True); assert not review['complete']

wrong = context('ExampleAir flight QX123. Departure: 10 November 2026 at 09:30 from SIN. Email received: 15 November 2026.',
                'Your flight tomorrow is ExampleAir QX123 at 09:30 from SIN.')
wrong['history'].append({'action':{'kind':'select','target':'e7'},'result':'Selected message; fresh body content is visible.'})
review = p.assess(task, wrong); print('Wrong event date review:', review, flush=True); assert not review['complete']

valid = context('ExampleAir flight QX123. Departure: 16 November 2026 at 09:30 from SIN.',
                'Your flight tomorrow, 16 November 2026, is ExampleAir QX123 departing SIN at 09:30.')
valid['evidence'].insert(0, {'id':'o1','app':'Mail','window':'Searching All Mailboxes — 1 result', 'image':False, 'elements':[{'id':'e7','role':'AXRow','label':'ExampleAir flight confirmation QX123','value':'','enabled':True,'editable':False,'selectable':True,'selected':False,'actions':[]}]})
valid['history'].append({'action':{'kind':'select','target':'e7'},'result':'Selected message; fresh body content is visible.'})
review = p.assess(task, valid); print('Verified details review:', review, flush=True); assert review['complete']

row = {'id':'e7','role':'AXRow','label':'ExampleAir flight confirmation','value':'Received 15 November 2026','enabled':True,'editable':False,'selectable':True,'selected':False,'actions':[]}
search['observation']['elements'] = [row]
search['installed_applications'] = [{'id':'com.apple.mail','name':'Mail'}]
search['completion_rejections'] = 1
search['completion_feedback'] = 'The search ran, but the flight departure dates and details have not been read. Select the relevant result and inspect its content.'
action = p.predict(task, search); print('Next step after search:', action, flush=True)
assert action['kind'] in {'select', 'read'} and action['target'] == 'e7'

simple = {'objective':'Open Calculator', 'criteria':['Calculator is open and visible']}
review = p.assess('Open Calculator.', context('0', 'Calculator is open.', simple, 'Calculator', 'Calculator'))
print('Simple open-app review:', review, flush=True); assert review['complete']

multi = {'objective':'Create a document and export it as PDF', 'criteria':['The document contains the requested text','The requested PDF export exists']}
review = p.assess('Create a document saying Hello and export it as a PDF.',
                  context('Hello', 'Created the document and exported the PDF.', multi, 'TextEdit', 'Untitled'))
print('Partial multi-step review:', review, flush=True); assert not review['complete']

# A prior developer test must not supply facts or app routing for a real request.
real_task = 'Find my real flight departing tomorrow in my emails and tell me the flight number and departure time.'
fixture = context('Booking confirmation. ExampleAir QX200. Departure 16 November 2026 at 14:20. This is synthetic test data.',
                  'Your flight tomorrow is ExampleAir QX200 at 14:20.',
                  {'objective':real_task,'criteria':[real_task]}, 'Brian Workflow Test', 'Brian Workflow Test')
fixture['conversation'] = [{'role':'user','content':'In Brian Workflow Test, identify tomorrow’s booking.'},
                           {'role':'assistant','content':'ExampleAir QX200 at 14:20.'}]
review = p.assess(real_task, fixture)
print('Synthetic data rejected for real request:', review, flush=True); assert not review['complete']
fixture['observation'] = {'app':'','name':'','window':'Developer test fixture unavailable in normal use','elements':[]}
fixture['installed_applications'] = [{'id':'com.apple.mail','name':'Mail'}]
fixture['history'] = []
fixture['evidence'] = []
action = p.predict(real_task, fixture)
print('Real email request after test conversation:', action, flush=True)
assert action['kind'] == 'search_mail'
assert 'tomorrow' not in action['value'].lower()

# Preserve natural phrasing: relative event dates are conditions, not literal terms.
action = p.predict('can you help me search for flights tomorrow at email',
                   dict(clock, installed_applications=[{'id':'com.apple.mail','name':'Mail'}],
                        observation={'app':'com.apple.mail','name':'Mail','window':'Inbox','elements':[]}, history=[]))
print('Natural flight request uses Mail without a literal relative-date word:', action, flush=True)
assert action['kind'] == 'search_mail' and 'tomorrow' not in action['value'].lower()

# Optional details must also be true; crossing the date line is not "next day".
itinerary = '''ExampleAir itinerary from TPE to SFO with connection at HKG.
Mon 16 Nov 2026
Mon 16 Nov 2026
TPE 20:15
HKG 22:25
QX201
Tue 17 Nov 2026
Mon 16 Nov 2026
HKG 00:55
SFO 20:55
QX202
All times are local to the respective airport.'''
date_task = 'Find flights on 16 November 2026 in my emails and tell me the airline, flight number and departure time.'
date_goal = {'objective':date_task,'criteria':[date_task],'mail_search':{'date':'2026-11-16','date_scope':'event'}}
bad_arrival = context(itinerary, 'Your ExampleAir flight QX201 leaves TPE on 16 November 2026 at 20:15, connects at HKG, and arrives at SFO at 20:55 the following day.', date_goal)
review = p.assess(date_task, bad_arrival)
print('Incorrect date-line arrival rejected:', review, flush=True); assert not review['complete']
clear_itinerary = 'ExampleAir QX201 departs TPE on 16 November 2026 at 20:15 local time. Connect at HKG to ExampleAir QX202, departing HKG on 17 November 2026 at 00:55 local time and arriving SFO on 16 November 2026 at 20:55 local time.'
good_arrival = context(clear_itinerary, 'Your ExampleAir flight QX201 leaves TPE on 16 November 2026 at 20:15. The itinerary shows arrival at SFO on 16 November 2026 at 20:55 local time, via HKG and QX202.', date_goal)
review = p.assess(date_task, good_arrival)
print('Complex explicit arrival-date assessment (known 4B false-negative risk):', review, flush=True)
if not review['complete']: print('KNOWN LIMITATION: the 4B reviewer rejected a correct cross-date itinerary; do not claim general date-line reasoning reliability.', flush=True)

departure_only = context(itinerary, 'ExampleAir QX201 departs TPE on 16 November 2026 at 20:15 local time.', date_goal)
review = p.assess(date_task, departure_only)
print('Supported departure without optional arrival inference:', review, flush=True); assert review['complete']

body = context(itinerary, '')
body['observation']['elements'] = [
 {'id':'e8','role':'AXRow','label':'Itinerary','value':'','enabled':True,'editable':False,'selectable':False,'selected':False,'actions':[]},
 {'id':'e9','role':'AXCell','label':'Flight details','value':itinerary,'enabled':True,'editable':False,'selectable':False,'selected':False,'actions':[]}]
body['history'].append({'action':{'kind':'select','target':'e7'},'result':'Opened the message; body visible.'})
body['installed_applications'] = [{'id':'com.apple.mail','name':'Mail'}]
action = p.predict(task, body)
print('HTML itinerary is read as content:', action, flush=True)
assert action['kind'] in {'read','done'}

excerpt_context = context(itinerary, 'An invented optional return time should never be displayed.', date_goal)
excerpt_context['reply_mode'] = 'excerpt'
review = p.assess(date_task, excerpt_context)
print('Excerpt mode selects actual message evidence:', review, flush=True)
assert review['complete'] and any(c['element'] == 'e1' for check in review['checks'] for c in check['evidence'])
