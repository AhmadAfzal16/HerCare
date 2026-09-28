const onboardingService = require('./onboarding.service');

async function complete(req, res, next) {
  try {
    const data = await onboardingService.completeOnboarding(
      req.user.userId,
      req.body,
    );
    return res.status(200).json({
      success: true,
      message: 'Onboarding completed successfully.',
      data,
    });
  } catch (error) {
    return next(error);
  }
}

module.exports = { complete };
