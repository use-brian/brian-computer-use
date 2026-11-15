import unittest
from planner import validate, validate_context

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

if __name__ == '__main__': unittest.main()
