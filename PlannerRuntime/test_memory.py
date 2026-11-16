import json
from pathlib import Path
import tempfile
import time
import unittest
from memory import MemoryStore, exact_terms, validate_query, validate_translation


class FakeEmbedding:
    model = 'test-only'
    revision = 'v1'
    def encode(self, texts, query=False):
        return [[1.0, 0.0] if any(w in t.lower() for w in ['email', 'correspondence', 'message']) else [0.0, 1.0] for t in texts]


class MemoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'memory.sqlite'
        self.store = MemoryStore(self.path, embedder=FakeEmbedding())
    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()
    def start(self, ident='t1', request='Find invoice sent to AOGB', kind='email_lookup', query='Find email invoice'):
        self.store.start(ident, request, {'english_query':query, 'task_type':kind})
    def learn(self, ident='old', request='Find flights tomorrow November 16 for OldRecipient'):
        self.start(ident, request)
        self.store.finish(ident, 'complete', {'app':'com.apple.mail',
            'history':[{'app':'com.apple.mail','action':{'kind':k}} for k in ['search_mail','read']],
            'evidence':[{'id':'o1','elements':[{'label':'Original evidence','value':request}]}]})
        return self.store.db.execute('SELECT id FROM memories').fetchone()[0]
    def test_tasks_persist_by_exact_id_without_cross_task_lookup(self):
        self.start()
        self.store.checkpoint('t1', {'goal':{'objective':'AOGB'}, 'history':[]})
        self.store.close(); self.store = MemoryStore(self.path)
        self.assertIn('AOGB', self.store.task('t1')['state'])
        self.assertIsNone(self.store.task('other'))
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
    def test_current_request_preserves_original_names_identifiers_and_unicode(self):
        original = '幫我找 AOGB 的 INV-0042.pdf，寄給 王小明 <Joe+Ops@Example.com>'
        self.start(request=original)
        self.assertEqual(self.store.task('t1')['request'], original)
        terms = exact_terms(original)
        for term in ['AOGB', 'INV-0042.pdf', '王小明', 'Joe+Ops@Example.com']:
            self.assertIn(term, terms)
    def test_sources_never_supply_old_dates_or_recipients_to_planner(self):
        self.learn()
        self.start('new')
        found = self.store.retrieve('new', 'com.apple.mail')
        self.assertTrue(found['guidance'])
        for text in ['November 16','OldRecipient','tomorrow','flights']:
            self.assertNotIn(text, json.dumps(found))
        self.assertIn('November 16', self.store.task('old')['request'])
    def test_failed_or_unverified_tasks_cannot_promote_memory(self):
        self.start()
        for status in ['failed','needs_input','cancelled']:
            self.store.finish('t1', status, {'app':'com.apple.mail','history':[{'action':{'kind':'search_mail'}}]})
            with self.assertRaises(ValueError): self.store.remember_template('email_verified','com.apple.mail','t1')
        self.assertEqual(self.store.db.execute('SELECT count(*) FROM memories').fetchone()[0], 0)
    def test_user_app_type_and_expiry_filters_apply_to_both_search_paths(self):
        ident = self.learn(); self.start('new')
        self.assertFalse(self.store.retrieve('new', 'other.app')['guidance'])
        self.start('doc', kind='document_edit')
        self.assertFalse(self.store.retrieve('doc', 'com.apple.mail')['guidance'])
        other = MemoryStore(self.path, user='other', embedder=FakeEmbedding())
        other.start('new','Find email',{'english_query':'email','task_type':'email_lookup'})
        self.assertFalse(other.retrieve('new', 'com.apple.mail')['guidance']); other.close()
        with self.store.db: self.store.db.execute('UPDATE memories SET expires=? WHERE id=?',(time.time()-1,ident))
        self.assertFalse(self.store.retrieve('new','com.apple.mail')['guidance'])
    def test_hybrid_finds_paraphrase_missed_by_fts(self):
        self.learn(); self.start('new', request='correspondence', query='correspondence', kind='general')
        self.assertFalse(self.store.retrieve('new','com.apple.mail',hybrid=False)['guidance'])
        self.assertTrue(self.store.retrieve('new','com.apple.mail',hybrid=True)['guidance'])
    def test_vectors_rebuild_after_revision_change_and_forget_cascades(self):
        ident = self.learn(); self.start('new')
        self.store.retrieve('new','com.apple.mail')
        with self.store.db: self.store.db.execute("UPDATE vectors SET revision='obsolete'")
        self.store.retrieve('new','com.apple.mail')
        self.assertEqual(self.store.db.execute('SELECT revision FROM vectors').fetchone()[0], 'v1')
        self.store.forget(ident)
        for table in ['memories','memory_fts','vectors','retrievals']:
            self.assertEqual(self.store.db.execute('SELECT count(*) FROM '+table).fetchone()[0], 0)
    def test_preference_lookup_is_explicit_and_task_relevant(self):
        self.store.set_preference('email_app','com.apple.mail','User explicitly chose Apple Mail')
        self.assertEqual(self.store.preferences('email_lookup'), {'email_app':'com.apple.mail'})
        self.assertEqual(self.store.preferences('document_edit'), {})
    def test_screenshots_are_not_persisted(self):
        self.start()
        self.store.checkpoint('t1', {'vision':{'png':'PRIVATE_IMAGE'}, 'evidence':[{'id':'o1','image':True,'vision':{'png':'PRIVATE_IMAGE'}}]})
        self.assertNotIn('PRIVATE_IMAGE', self.store.task('t1')['state'])
    def test_translation_preserves_names_and_identifiers_even_if_model_omits_them(self):
        request = '王小明に送った INV-0042.pdf のメール'
        result = validate_translation({'english_query':'Find invoice email for Wang Xiaoming',
            'task_type':'email_lookup','exact_terms':['王小明']}, request)
        self.assertIn('王小明', result['english_query'])
        self.assertIn('INV-0042.pdf', result['english_query'])
        with self.assertRaises(ValueError):
            validate_translation({'english_query':'Find email','task_type':'email_lookup',
                                  'exact_terms':['invented@example.com']},request)
    def test_repeated_completion_event_is_idempotent(self):
        self.learn()
        state = json.loads(self.store.task('old')['state'])
        self.store.finish('old','complete',state)
        self.assertEqual(self.store.db.execute('SELECT successes FROM memories').fetchone()[0],1)
    def test_task_from_another_app_cannot_teach_this_app_a_procedure(self):
        self.start()
        self.store.finish('t1','complete',{'app':'com.apple.mail',
            'history':[{'app':'other.app','action':{'kind':k}} for k in ['search_mail','read']],
            'evidence':[{'id':'fixture'}]})
        self.assertEqual(self.store.db.execute('SELECT count(*) FROM memories').fetchone()[0],0)
    def test_query_schema_rejects_invented_fields(self):
        with self.assertRaises(ValueError): validate_query({'english_query':'email','task_type':'email_lookup','recipient':'invented'})
    def test_repeated_verified_outcomes_deduplicate(self):
        first=self.learn(); self.learn('second')
        rows=list(self.store.db.execute('SELECT * FROM memories'))
        self.assertEqual(len(rows),1); self.assertEqual(rows[0]['successes'],2)
    def test_clear_removes_source_evidence_and_indexes(self):
        self.learn(); self.start('new'); self.store.retrieve('new','com.apple.mail'); self.store.clear()
        for table in ['tasks','memories','vectors','memory_fts','preferences','retrievals']:
            self.assertEqual(self.store.db.execute('SELECT count(*) FROM '+table).fetchone()[0],0)

if __name__ == '__main__': unittest.main()
