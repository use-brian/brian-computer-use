import multiprocessing

if __name__ == '__main__':
    multiprocessing.freeze_support()
    import contextlib
    import sys
    from mac_policy import mcp_server as server
    from mac_policy.paths import ROOT
    from mcp.types import ToolAnnotations
    from planner import Planner

    planner = None

    @server.mcp.tool(annotations=ToolAnnotations(readOnlyHint=True, openWorldHint=False))
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

    @server.mcp.tool(annotations=ToolAnnotations(readOnlyHint=True, openWorldHint=False))
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

    server.main()
