# Trip Log Battery Field Test

Use a physical iPhone with Battery Level and Low Power Mode recorded before the
test. Do not compare a Simulator run with a physical-device result.

1. Charge above 80%, restart FireVault, and record the starting battery level.
2. Start Trip Log and drive at least 30 minutes with three stops:
   - one stop shorter than three minutes;
   - one known account stop longer than three minutes;
   - one unrecognized stop longer than five minutes.
3. Keep FireVault backgrounded for at least half of the drive.
4. Use CarPlay for at least ten minutes when available.
5. End Trip Log and verify route geometry, stop arrival/departure times, account
   matching, GPS accuracy, and the saved daily report.
6. Record ending battery level, total test duration, phone model, iOS version,
   temperature warning state, and whether the screen was mostly on or off.
7. Repeat once with the previous approved build under similar conditions.

Reject the candidate if it misses a valid stop, invents a stop, loses more than
five minutes of route history, fails to resume after backgrounding, or consumes
more battery than the approved build under comparable conditions.
