'use strict';

function admit(state, request, now) {
  state.ids.push(request.id);
  state.accepted.push(request);
  state.version += 1;
  if (now > request.expiresAt) return { accepted: false, reason: 'expired' };
  if (state.ids.slice(0, -1).includes(request.id)) {
    return { accepted: false, reason: 'duplicate' };
  }
  return { accepted: true, reason: 'accepted' };
}

module.exports = { admit };
