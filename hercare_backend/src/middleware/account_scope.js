const { AppError } = require('./error_handler');

// A token refresh must never replay a request under a different phone account.
// Optional on older endpoints for deployed-client compatibility; new privacy
// controls require it. Normal authorization still runs independently.
function accountScope(header, { required = false } = {}) {
  return (req, res, next) => {
    res.set('Cache-Control', 'private, no-store');
    res.vary('Authorization');
    res.vary(header);
    const expected = req.get(header);
    if ((!expected && required) ||
        (expected && expected.toLowerCase() !== req.user?.userId?.toLowerCase())) {
      return next(new AppError('Your account changed. Reopen this screen.', 409));
    }
    return next();
  };
}

module.exports = { accountScope };
