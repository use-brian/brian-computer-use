import unittest
from mail_search import compile_search, resolve_date, date_variants

class SearchPlanTests(unittest.TestCase):
    clock = {'request_started':'2026-11-15T12:00:00Z','time_zone':'Asia/Singapore'}
    def draft(self, **updates):
        return dict({'topics':['flight','itinerary','booking confirmation'], 'date':'tomorrow', 'date_scope':'event', 'literal':False}, **updates)
    def test_undated_invoice_does_not_inherit_flight_dates(self):
        context = dict(self.clock, request='help me find my invoice sent to AOGB', conversation=[
            {'role':'user','content':'Find flights tomorrow'}, {'role':'assistant','content':'Found a flight on November 16'}])
        plan = compile_search(self.draft(topics=['invoice Nov 16', 'AOGB'], date='2026-11-16'), context)
        self.assertIsNone(plan['date'])
        self.assertEqual(plan['date_scope'], 'none')
        self.assertEqual(plan['date_variants'], [])
        self.assertEqual(plan['queries'], ['invoice', 'AOGB'])
    def test_explicit_date_and_date_followup_remain_supported(self):
        for task in ['Find flights tmr', 'Find invoices for November 16', 'Find invoices for 16 Nov', 'Find invoices for 2026-11-16', 'Find invoices for 16/11/2026']:
            self.assertEqual(compile_search(self.draft(date='2026-11-16'), dict(self.clock, request=task))['date'], '2026-11-16')
        context = dict(self.clock, request='Find invoices for that day', conversation=[{'role':'user','content':'Find flights tomorrow'}])
        self.assertIsNotNone(compile_search(self.draft(), context)['date'])
    def test_fresh_requests_do_not_receive_old_search_context(self):
        from mail_search import search_context
        context = {'conversation':[{'role':'user','content':'Find flights tomorrow'}]}
        self.assertEqual(search_context('help me find my invoice sent to AOGB', context)['conversation'], [])
        self.assertEqual(search_context('Find invoices for that day', context)['conversation'], context['conversation'])
    def test_tomorrow_aliases_and_date_combinations(self):
        for word in ('tomorrow','tmr','tmrw'):
            plan = compile_search(self.draft(date=word), self.clock)
            self.assertEqual(plan['date'], '2026-11-16')
            self.assertIn('flight Nov 16', plan['queries'])
            self.assertIn('flight November 16', plan['queries'])
            self.assertIn('flight 16 Nov', plan['queries'])
            self.assertIn('flight 2026-11-16', plan['queries'])
            self.assertIn('itinerary', plan['queries'])
            self.assertNotIn('tomorrow', ' '.join(plan['queries']))
            self.assertEqual(len(set(plan['queries'])), len(plan['queries']))
    def test_request_local_day_and_month_year_rollovers(self):
        c = {'request_started':'2026-12-31T15:59:59Z','time_zone':'Asia/Singapore'}
        self.assertEqual(str(resolve_date('tmr', c)), '2027-01-01')
        c['request_started'] = '2026-12-31T16:00:00Z'
        self.assertEqual(str(resolve_date('tomorrow', c)), '2027-01-02')
        self.assertEqual(str(resolve_date('tomorrow', dict(c, request_started='2028-02-28T00:00:00Z'))), '2028-02-29')
    def test_literal_query_is_preserved(self):
        plan = compile_search(self.draft(topics=['flights tomorrow'], literal=True), self.clock)
        self.assertIsNone(plan['date'])
        self.assertEqual(plan['queries'], ['flights tomorrow'])
    def test_non_email_task_has_no_search_plan(self):
        self.assertIsNone(compile_search(self.draft(topics=[]), {}))
    def test_event_dates_do_not_become_received_date_filters(self):
        plan = compile_search(self.draft(date='2026-11-16'), self.clock)
        self.assertEqual(plan['date_scope'], 'event')
        self.assertFalse(any('after:' in q or 'before:' in q for q in plan['queries']))
    def test_invalid_model_fields_and_impossible_dates_are_rejected(self):
        for draft in (self.draft(date='2026-02-30'), self.draft(topics=['x']*4), self.draft(topics=['bad\nquery']), {'topics':['flight']}):
            with self.assertRaises(ValueError): compile_search(draft, self.clock)


class CandidateTests(unittest.TestCase):
    def test_triage_uses_current_unselected_message_rows_only(self):
        from mail_search import unselected_candidates
        row = {'id':'e2','role':'AXRow','label':'Example Airline · Inbox · Yesterday · Booking confirmation','enabled':True,'selectable':True,'selected':False}
        context = {'observation':{'app':'com.apple.mail','elements':[row,dict(row,id='e3',label='Inbox')]},'mail_search':{'plan':{'date':'2026-11-16','literal':False},'attempts':[{'query':'flight Nov 16'}]}}
        self.assertEqual(unselected_candidates(context), [{'id':'e2','label':row['label']}])
        row['selected'] = True
        self.assertEqual(unselected_candidates(context), [])
        row['selected'] = False
        context['mail_search']['plan']['literal'] = True
        self.assertEqual(unselected_candidates(context), [])

class ReplyDateTests(unittest.TestCase):
    def test_relative_event_chronology_is_rejected_without_changing_other_answers(self):
        from mail_search import enforce_explicit_event_dates
        approved = {'complete':True,'reason':'Found departure','checks':[{'satisfied':True}]}
        context = {'mail_search':{'plan':{'date':'2026-11-16','date_scope':'event'}},'proposal':'Arrives the following day.'}
        self.assertFalse(enforce_explicit_event_dates(approved, context)['complete'])
        self.assertTrue(approved['complete'], 'Do not mutate the original assessment')
        self.assertTrue(enforce_explicit_event_dates(approved, dict(context, proposal='Departs 16 November at 20:15.'))['complete'])
        self.assertTrue(enforce_explicit_event_dates(approved, {'proposal':'The email says next day.'})['complete'])
        context['mail_search']['plan']['literal'] = True
        self.assertTrue(enforce_explicit_event_dates(approved, context)['complete'])

if __name__ == '__main__': unittest.main()
