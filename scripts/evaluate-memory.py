"""Synthetic, isolated evaluation: real Qwen translation + real pinned BGE.
Never opens applications or reads user email. Does not seed production memory.
"""
import argparse
import json
import os
from pathlib import Path
import sys
import tempfile
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'PlannerRuntime'))
from memory import BGEEmbedding, MemoryStore, QUERY_SYSTEM, validate_translation

parser=argparse.ArgumentParser()
parser.add_argument('--planner-model', required=True)
parser.add_argument('--embedding-model', required=True)
parser.add_argument('--output', required=True)
args=parser.parse_args()
cases=[
    ('fr', 'Retrouve le courriel contenant le reçu envoyé à ACME-42.', 'email_lookup', ['ACME-42']),
    ('de', 'Ändere die Überschrift im Dokument in "Projekt AB-17".', 'document_edit', ['Projekt','AB-17']),
    ('en', 'Find my invoice sent to AOGB', 'email_lookup', ['AOGB']),
    ('zh', '幫我找寄給 AOGB 的發票 INV-0042.pdf', 'email_lookup', ['AOGB','INV-0042.pdf']),
    ('es', 'Busca el correo con la factura enviada a AOGB, referencia INV-0042.', 'email_lookup', ['AOGB','INV-0042']),
    ('ja', '王小明に送った請求書 INV-0042.pdf のメールを探してください', 'email_lookup', ['王小明','INV-0042.pdf']),
    ('zh', '把文件的標題改成「AOGB 月報」', 'document_edit', ['AOGB','月報']),
    ('es', 'Cambia el título del documento a "Informe AOGB".', 'document_edit', ['Informe','AOGB']),
]
with tempfile.TemporaryDirectory(prefix='brian-memory-eval-') as temp:
    os.environ['BRIAN_MEMORY_DB']=str(Path(temp)/'memory.sqlite')
    from planner import Planner
    planner=Planner(args.planner_model)
    store=planner.memory
    store.embedder=BGEEmbedding(args.embedding_model)
    # All fixtures stay inside this temp database.
    for ident, kind, app, actions, template in [
        ('mail', 'email_lookup', 'com.apple.mail', ['search_mail','select','read'], 'email_verified'),
        ('doc', 'document_edit', 'com.apple.TextEdit', ['set_text','read'], 'document_verified')]:
        store.start(ident, 'Synthetic old task November 16 OldRecipient QX200', {'english_query':kind,'task_type':kind})
        store.finish(ident,'complete',{'app':app,'history':[{'app':app,'action':{'kind':a}} for a in actions],
                                     'evidence':[{'id':'fixture','elements':[{'value':'Synthetic verified fixture'}]}]})
    results=[]
    for n,(language,request,kind,terms) in enumerate(cases):
        started=time.monotonic()
        query=planner.structured(QUERY_SYSTEM, {'request':request}, lambda value: validate_translation(value, request),
                                 max_tokens=250, required_fields='english_query, task_type, exact_terms')
        ident='query-'+str(n); store.start(ident,request,query)
        app='com.apple.mail' if kind=='email_lookup' else 'com.apple.TextEdit'
        fts=store.retrieve(ident,app,hybrid=False)
        hybrid=store.retrieve(ident,app,hybrid=True)
        clean=all(term not in json.dumps(hybrid) for term in ['November 16','OldRecipient','QX200'])
        result={'language':language,'request':request,'query':query,'expected_task_type':kind,
                'task_type_correct':query['task_type']==kind,
                'source_terms_preserved':all(t in store.task(ident)['request'] for t in terms),
                'translation_terms_preserved':all(t in query['english_query'] for t in terms),
                'fts5_hits':len(fts['guidance']),'hybrid_hits':len(hybrid['guidance']),
                'retrieval_mode':hybrid['retrieval_mode'],'old_details_excluded':clean,
                'seconds':round(time.monotonic()-started,2)}
        results.append(result)
        print(json.dumps(result,ensure_ascii=False),flush=True)
    # Explicit lexical gap isolates BGE's value, independent of translation.
    store.start('paraphrase','correspondence',{'english_query':'Locate correspondence','task_type':'general'})
    fts=store.retrieve('paraphrase','com.apple.mail',hybrid=False)
    hybrid=store.retrieve('paraphrase','com.apple.mail',hybrid=True)
    report={'model':store.embedder.model,'revision':store.embedder.revision,'synthetic_only':True,
            'cases':results,'paraphrase':{'query':'Locate correspondence','fts5_hits':len(fts['guidance']),
                                         'hybrid_hits':len(hybrid['guidance'])}}
    Path(args.output).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    assert all(r['task_type_correct'] and r['source_terms_preserved'] and r['old_details_excluded'] and r['hybrid_hits'] for r in results)
