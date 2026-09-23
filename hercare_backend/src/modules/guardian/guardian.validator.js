const Joi = require('joi');

const acceptInviteSchema = Joi.object({
  invite_code: Joi.string().alphanum().length(12).uppercase().required()
    .messages({
      'string.length': 'Invite code must be exactly 12 characters',
      'any.required': 'Invite code is required',
    }),
  guardian_name: Joi.string().trim().min(2).max(60).required(),
  relationship: Joi.string()
    .valid('husband', 'mother', 'sister', 'brother', 'father', 'friend', 'other')
    .required(),
});

const getReportsSchema = Joi.object({
  type: Joi.string().valid('daily', 'weekly', 'monthly').default('weekly'),
  limit: Joi.number().integer().min(1).max(30).default(7),
});

const generateReportSchema = Joi.object({
  period_type: Joi.string().valid('daily', 'weekly', 'monthly').required(),
  anchor_date: Joi.date().iso().max('now').optional(),
});

const reportIdSchema = Joi.object({
  id: Joi.string().uuid({ version: 'uuidv4' }).required(),
});

const getDashboardSchema = Joi.object({
  lang: Joi.string().valid('en', 'ur').default('en'),
});

const getAlertsSchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).default(20),
});

const markAlertsReadSchema = Joi.object({
  alert_ids: Joi.array()
    .items(Joi.string().uuid({ version: 'uuidv4' }))
    .max(100)
    .default([]),
});

function validate(schema, source = 'body') {
  return (req, res, next) => {
    const { error, value } = schema.validate(req[source], {
      abortEarly: false,
      stripUnknown: true,
      convert: true,
    });
    if (error) {
      return res.status(422).json({
        success: false,
        message: 'Validation failed',
        errors: error.details.map((detail) => detail.message),
      });
    }
    req[source] = value;
    return next();
  };
}

module.exports = {
  validateAcceptInvite: validate(acceptInviteSchema),
  validateGetReports: validate(getReportsSchema, 'query'),
  validateGenerateReport: validate(generateReportSchema),
  validateReportId: validate(reportIdSchema, 'params'),
  validateGetDashboard: validate(getDashboardSchema, 'query'),
  validateGetAlerts: validate(getAlertsSchema, 'query'),
  validateMarkAlertsRead: validate(markAlertsReadSchema),
};
