import unittest
from planner import validate, validate_context, validate_goal, validate_assessment, temporal_context, validate_review

class ValidationTests(unittest.TestCase):
    def test_accepts_only_known_tools(self):
        self.assertEqual(validate('{"kind":"search_mail","value":"Draper"}')['value'], 'Draper')
        for raw in ['{"kind":"shell","value":"rm -rf /"}', '{"kind":"press","target":"e1","script":"x"}', '{"kind":"open_app"}']:
            with self.assertRaises(ValueError): validate(raw)
    def test_rejects_empty_and_nonstring_arguments(self):
        for raw in ['{"kind":"ask","message":""}', '{"kind":"press","target":12}', '[]']:
            with self.assertRaises(ValueError): validate(raw)
        self.assertEqual(validate('{"kind":"set_text","target":"e1","value":""}')['value'], '')
    def test_handles_a_fenced_object_without_extracting_arbitrary_text(self):
        self.assertEqual(validate('```json\n{"kind":"wait"}\n```'), {'kind':'wait'})
        with self.assertRaises(ValueError): validate('explanation {"kind":"wait"}')
    def test_rejects_guessed_controls_and_app_names(self):
        context = {'installed_applications':[{'id':'com.apple.calculator'}], 'observation':{'elements':[]}, 'history':[]}
        for action in [{'kind':'open_app','app':'Calculator'}, {'kind':'press','target':'Clear'}, {'kind':'done','message':'Done'}]:
            with self.assertRaises(ValueError): validate_context(action, context)
        self.assertEqual(validate_context({'kind':'observe'}, context), {'kind':'observe'})
    def test_rejects_pressing_readonly_text(self):
        context = {'observation':{'elements':[{'id':'e1','enabled':True,'role':'AXStaticText','actions':[],'editable':False}]}}
        with self.assertRaises(ValueError): validate_context({'kind':'press','target':'e1'}, context)

    def test_exact_names_resolve_only_when_unambiguous(self):
        context = {'installed_applications':[{'id':'app.calc','name':'Calculator'}],
                   'observation':{'elements':[{'id':'e1','label':'Continue','enabled':True,'actions':['AXPress']}]}}
        self.assertEqual(validate_context({'kind':'open_app','app':'Calculator'},context)['app'],'app.calc')
        self.assertEqual(validate_context({'kind':'press','target':'Continue'},context)['target'],'e1')
        context['observation']['elements'].append({'id':'e2','label':'Continue','enabled':True,'actions':['AXPress']})
        with self.assertRaises(ValueError): validate_context({'kind':'press','target':'Continue'},context)

    def test_vision_requires_current_image_and_finite_normalized_point(self):
        action = {'kind':'vision_click','target':'capture-1','value':'750,600','message':'Continue'}
        with self.assertRaises(ValueError): validate_context(action, {'observation':{}})
        context = {'observation':{'vision':{'id':'capture-1'}}}
        self.assertEqual(validate_context(action, context), action)
        for value in ['nan,100', 'inf,100', '-1,100', '1000,500', '500', '1,2,3']:
            with self.assertRaises(ValueError): validate_context(dict(action, value=value), context)
        with self.assertRaises(ValueError): validate_context(dict(action, target='stale'), context)
        with self.assertRaises(ValueError): validate_context(dict(action, kind='vision_scroll', message='left'), context)

class CompletionTests(unittest.TestCase):
    def context(self):
        return {'goal': {'objective':'Verify a result','criteria':['Required outcome']},
                'current_observation_id':'o2', 'observation':{},
                'evidence':[{'id':'o2','app':'Test','window':'Result', 'image':False,
                             'elements':[{'id':'e1','label':'Departure','value':'16 November 2026'}]}]}
    def approved(self):
        return {'complete':True,'reason':'Observed required date', 'checks':[
            {'criterion':0,'satisfied':True,'evidence':[{'observation':'o2','element':'e1','quote':'16 November 2026'}]}]}
    def test_dates_resolve_in_local_zone_at_request_time(self):
        result = temporal_context({'current_date':'2026-11-15T23:30:00Z','time_zone':'Asia/Singapore'})
        self.assertEqual(result['local_today'], '2026-11-16')
        self.assertEqual(result['local_tomorrow'], '2026-11-17')
    def test_goal_rejects_empty_or_unbounded_criteria(self):
        self.assertEqual(validate_goal({'objective':'Open Calculator','criteria':['Calculator is open']})['criteria'], ['Calculator is open'])
        for criteria in [[], [''] , ['x'] * 9]:
            with self.assertRaises(ValueError): validate_goal({'objective':'Task','criteria':criteria})
    def test_completion_requires_real_citations_for_all_criteria(self):
        self.assertTrue(validate_assessment(self.approved(), self.context())['complete'])
        for field, value in [('observation','fake'), ('element','fake'), ('quote','17 November 2026')]:
            approved = self.approved(); approved['checks'][0]['evidence'][0][field] = value
            with self.assertRaises(ValueError): validate_assessment(approved, self.context())
        approved = self.approved(); approved['checks'] = []
        with self.assertRaises(ValueError): validate_assessment(approved, self.context())
    def test_tool_success_is_not_an_evidence_source(self):
        context = self.context(); context['history'] = [{'result':'Found your flight'}]
        approved = self.approved(); approved['checks'][0]['evidence'][0]['quote'] = 'Found your flight'
        with self.assertRaises(ValueError): validate_assessment(approved, context)
    def test_incomplete_review_cannot_approve(self):
        approved = self.approved(); approved['checks'][0]['satisfied'] = False
        with self.assertRaises(ValueError): validate_assessment(approved, self.context())
        approved['complete'] = False
        self.assertFalse(validate_assessment(approved, self.context())['complete'])
    def test_compact_review_uses_only_observed_sources(self):
        result = validate_review({'complete':True,'reason':'Date observed','sources':['o2/e1']}, self.context())
        self.assertEqual(result['checks'][0]['evidence'][0]['quote'], '16 November 2026')
        for sources in [[], ['o2/fake'], ['o1/e1']]:
            with self.assertRaises(ValueError):
                validate_review({'complete':True,'reason':'Claim','sources':sources}, self.context())
        with self.assertRaises(ValueError):
            validate_review({'complete':True,'sources':['o2/e1']}, self.context())
    def test_rejected_completion_requires_a_recovery_step(self):
        context = {'history':[{'result':'Search ran'}], 'completion_rejections':1}
        with self.assertRaises(ValueError):
            validate_context({'kind':'done','message':'Results are visible'}, context)
        self.assertEqual(validate_context({'kind':'observe'}, context)['kind'], 'observe')
        context['completion_rejections'] = 0
        self.assertEqual(validate_context({'kind':'done','message':'Verified answer'}, context)['kind'], 'done')
    def test_selection_requires_ax_selectable(self):
        context = {'observation':{'elements':[{'id':'e1','enabled':True,'selectable':True,'actions':[]}]}}
        self.assertEqual(validate_context({'kind':'select','target':'e1'}, context)['kind'], 'select')
        context['observation']['elements'][0]['selectable'] = False
        with self.assertRaises(ValueError): validate_context({'kind':'select','target':'e1'}, context)

if __name__ == '__main__': unittest.main()
