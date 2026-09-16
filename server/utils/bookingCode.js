// Booking code allocation is performed atomically inside PostgreSQL.
// This module is kept as a compatibility wrapper for callers that may still import it.
async function generateBookingCode() {
  throw new Error('Booking codes are generated atomically by the create_booking PostgreSQL function.');
}
module.exports = { generateBookingCode };
