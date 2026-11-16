import multiprocessing

if __name__ == '__main__':
    multiprocessing.freeze_support()
    import contextlib
    import sys
    from mac_policy import mcp_server as server
    from mac_policy.paths import ROOT
    from mcp.types import ToolAnnotations
    from planner import Planner

    if len(sys.argv) > 1 and sys.argv[1] == 'memory':
        from memory import main
        sys.argv.pop(1)
        main()
        sys.exit(0)
    if len(sys.argv) > 1 and sys.argv[1] == 'memory-self-test':
        import json, tempfile
        from pathlib import Path
        from memory import BGEEmbedding, MemoryStore
        with tempfile.TemporaryDirectory(prefix='brian-memory-smoke-') as temporary:
            store = MemoryStore(Path(temporary) / 'memory.sqlite', embedder=BGEEmbedding(ROOT / 'models/bge-small-en-v1.5'))
            store.start('fixture', 'Synthetic task', {'english_query':'email lookup','task_type':'email_lookup'})
            store.finish('fixture', 'complete', {'app':'test.mail',
                'history':[{'app':'test.mail','action':{'kind':k}} for k in ['search_mail','read']],
                'evidence':[{'id':'fixture','elements':[{'value':'Synthetic evidence'}]}]})
            store.start('query', 'Find an email', {'english_query':'find email','task_type':'email_lookup'})
            result = store.retrieve('query','test.mail')
            assert result['retrieval_mode'] == 'hybrid' and result['guidance']
            print(json.dumps({'ok':True,'model':store.embedder.model,'revision':store.embedder.revision,
                              'mode':result['retrieval_mode'],'memories':len(result['guidance'])}))
            store.close()
        sys.exit(0)

    planner = None

    @server.mcp.tool(annotations=ToolAnnotations(readOnlyHint=False, openWorldHint=False))
    async def brian_plan(task: str, context: dict) -> dict:
        """Interpret natural language and propose one validated tool call. Does not execute it."""
        global planner
        import json
        if not task.strip() or len(task) > 12000 or len(json.dumps(context)) > 4_200_000:
            raise ValueError('Request/context exceeds the local planner limit')
        with contextlib.redirect_stdout(sys.stderr):
            if planner is None:
                planner = Planner(str(ROOT / 'models/qwen3.5-4b-4bit'))
            return planner.predict(task, context)

    @server.mcp.tool(annotations=ToolAnnotations(readOnlyHint=False, openWorldHint=False))
    async def brian_goal(task: str, context: dict) -> dict:
        """Define observable success criteria for the user's complete request."""
        return review('goal', task, context)

    @server.mcp.tool(annotations=ToolAnnotations(readOnlyHint=True, openWorldHint=False))
    async def brian_assess(task: str, context: dict) -> dict:
        """Review a proposed completion against observed evidence. Executes no actions."""
        return review('assess', task, context)

    def review(method, task, context):
        global planner
        import json
        if not task.strip() or len(task) > 12000 or len(json.dumps(context)) > 4_200_000:
            raise ValueError('Request/context exceeds the local planner limit')
        with contextlib.redirect_stdout(sys.stderr):
            if planner is None:
                planner = Planner(str(ROOT / 'models/qwen3.5-4b-4bit'))
            return getattr(planner, method)(task, context)

    @server.mcp.tool(annotations=ToolAnnotations(readOnlyHint=False, openWorldHint=False))
    async def brian_memory(task_id: str, event: str, context: dict) -> dict:
        """Persist this task's checkpoint or harness-verified outcome locally."""
        import json
        if len(task_id) > 80 or len(json.dumps(context)) > 300_000:
            raise ValueError('Memory event exceeds limits')
        if planner is None:
            return {'saved': False}
        return planner.memory_event(task_id, event, context)

    server.main()
