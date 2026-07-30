// Smallest possible check that this org can reach an agent at all.
// Run with: sf apex run --file scripts/apex/ping-agent.apex --target-org <alias>
//
// If this fails, the problem is org configuration and no amount of Conduit code will fix
// it. Work through docs/TROUBLESHOOTING.md before touching anything else.

String agentApiName = 'REPLACE_WITH_YOUR_AGENT_API_NAME';

Invocable.Action action = Invocable.Action.createCustomAction('generateAiAgentResponse', agentApiName);
action.setInvocationParameter('userMessage', 'Say hello in one short sentence.');

List<Invocable.Action.Result> results = action.invoke();
Invocable.Action.Result result = results[0];

System.debug('success:   ' + result.isSuccess());
System.debug('errors:    ' + result.getErrors());
System.debug('output:    ' + result.getOutputParameters());
