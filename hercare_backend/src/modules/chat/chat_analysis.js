const { analyzeJournal } = require('../mood/journal_analysis');

// M7 intentionally shares M5's deterministic multilingual safety layer so
// journal and chat escalation behave consistently. A versioned contextual NLP
// model can replace this adapter without changing message storage or clients.
function analyzeMessage(content) {
  const result = analyzeJournal(content);
  return { ...result, analysisVersion: `chat-${result.analysisVersion}` };
}

module.exports = { analyzeMessage };

