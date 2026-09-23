const guardianService = require('./guardian.service');

async function generateInvite(req, res, next) {
  try {
    if (req.user.role !== 'mother') {
      return res.status(403).json({ success: false, message: 'Only mothers can generate invite codes' });
    }
    let pending = await guardianService.getPendingInvite(req.user.userId);
    if (!pending) pending = await guardianService.generateInvite(req.user.userId);
    return res.status(200).json({
      success: true,
      data: {
        invite_code: pending.invite_code,
        generated_at: pending.created_at,
        expires_at: pending.expires_at,
        message: 'Share this code privately. It expires after 24 hours or after it is used.',
      },
    });
  } catch (error) {
    return next(error);
  }
}

async function refreshInvite(req, res, next) {
  try {
    if (req.user.role !== 'mother') {
      return res.status(403).json({ success: false, message: 'Only mothers can generate invite codes' });
    }
    const result = await guardianService.generateInvite(req.user.userId);
    return res.status(200).json({ success: true, data: result });
  } catch (error) {
    return next(error);
  }
}

async function acceptInvite(req, res, next) {
  try {
    if (req.user.role !== 'guardian') {
      return res.status(403).json({ success: false, message: 'Only guardian accounts can accept invite codes' });
    }
    const { invite_code, guardian_name, relationship } = req.body;
    const link = await guardianService.acceptInvite(
      req.user.userId,
      invite_code,
      guardian_name,
      relationship,
    );
    return res.status(200).json({
      success: true,
      message: 'Successfully linked to mother account',
      data: link,
    });
  } catch (error) {
    return next(error);
  }
}

async function getLink(req, res, next) {
  try {
    const link = await guardianService.getLink(req.user.userId, req.user.role);
    return res.status(200).json({
      success: true,
      data: link,
      message: link ? undefined : 'No active guardian link',
    });
  } catch (error) {
    return next(error);
  }
}

async function revokeLink(req, res, next) {
  try {
    if (req.user.role !== 'mother') {
      return res.status(403).json({ success: false, message: 'Only mothers can revoke guardian access' });
    }
    const result = await guardianService.revokeLink(req.user.userId);
    return res.status(200).json({ success: true, data: result });
  } catch (error) {
    return next(error);
  }
}

async function getDashboard(req, res, next) {
  try {
    if (req.user.role !== 'guardian') {
      return res.status(403).json({ success: false, message: 'Only guardians can view the dashboard' });
    }
    const data = await guardianService.getDashboard(req.user.userId, req.query.lang);
    return res.status(200).json({ success: true, data });
  } catch (error) {
    return next(error);
  }
}

async function getReports(req, res, next) {
  try {
    const reports = await guardianService.getReports(
      req.user.userId,
      req.user.role,
      req.query.type,
      req.query.limit,
    );
    return res.status(200).json({ success: true, data: reports });
  } catch (error) {
    return next(error);
  }
}

async function getReportById(req, res, next) {
  try {
    const report = await guardianService.getReportById(
      req.user.userId,
      req.user.role,
      req.params.id,
    );
    return res.status(200).json({ success: true, data: report });
  } catch (error) {
    return next(error);
  }
}

async function generateReport(req, res, next) {
  try {
    if (req.user.role !== 'mother') {
      return res.status(403).json({ success: false, message: 'Only mothers can generate reports' });
    }
    const report = await guardianService.generateReport(
      req.user.userId,
      req.body.period_type,
      req.body.anchor_date,
    );
    return res.status(201).json({ success: true, data: report });
  } catch (error) {
    return next(error);
  }
}

async function getAlerts(req, res, next) {
  try {
    if (req.user.role !== 'guardian') {
      return res.status(403).json({ success: false, message: 'Only guardians can view alerts' });
    }
    const alerts = await guardianService.getAlerts(req.user.userId, req.query.limit);
    return res.status(200).json({ success: true, data: alerts });
  } catch (error) {
    return next(error);
  }
}

async function markAlertsRead(req, res, next) {
  try {
    if (req.user.role !== 'guardian') {
      return res.status(403).json({ success: false, message: 'Only guardians can update alerts' });
    }
    const result = await guardianService.markAlertsRead(
      req.user.userId,
      req.body.alert_ids,
    );
    return res.status(200).json({ success: true, data: result });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  generateInvite,
  refreshInvite,
  acceptInvite,
  getLink,
  revokeLink,
  getDashboard,
  getReports,
  getReportById,
  generateReport,
  getAlerts,
  markAlertsRead,
};
