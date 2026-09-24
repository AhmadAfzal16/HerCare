const { AppError } = require('../../middleware/error_handler');

function riskForScore(instrumentType, score) {
  if (instrumentType === 'epds') {
    if (score <= 8) return 'low';
    if (score <= 12) return 'moderate';
    if (score <= 18) return 'high';
    return 'severe';
  }
  if (instrumentType === 'phq9') {
    if (score <= 4) return 'low';
    if (score <= 9) return 'moderate';
    if (score <= 19) return 'high';
    return 'severe';
  }
  throw new AppError('Unsupported screening instrument.', 422);
}

function scoreAnswers(instrument, answers) {
  if (!Array.isArray(answers) || answers.length !== instrument.questions.length) {
    throw new AppError(`All ${instrument.questions.length} questions must be answered.`, 422);
  }
  const answerMap = new Map();
  answers.forEach((answer) => {
    if (answerMap.has(answer.question_number)) {
      throw new AppError('Each screening question can be answered only once.', 422);
    }
    answerMap.set(answer.question_number, answer.option_index);
  });

  const responses = instrument.questions.map((question) => {
    const optionIndex = answerMap.get(question.number);
    const option = Number.isInteger(optionIndex) ? question.options[optionIndex] : null;
    if (!option) throw new AppError(`Invalid answer for question ${question.number}.`, 422);
    return {
      question_number: question.number,
      option_index: optionIndex,
      score: option.score,
    };
  });
  const totalScore = responses.reduce((sum, item) => sum + item.score, 0);
  const crisisResponse = responses.find(
    (response) => response.question_number === instrument.crisis_question,
  );
  return {
    responses,
    total_score: totalScore,
    risk_level: riskForScore(instrument.type, totalScore),
    self_harm_positive: (crisisResponse?.score || 0) > 0,
  };
}

module.exports = { riskForScore, scoreAnswers };
