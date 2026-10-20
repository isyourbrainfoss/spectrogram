# Changelog

## Unreleased

### Changed — dBFS readings are now ~6 dB higher

- **Heads-up:** every dBFS readout (crosshair, spectrum chip, CSV export and
  colour scaling) now reads **about +6 dB (6.02 dB) higher** than in 0.1.1 and
  older versions. Older versions ignored the Hann window's coherent gain, so a
  full-scale sine read −6 dBFS; it now correctly reads 0 dBFS. If you compare
  against CSV exports or screenshots from older versions, subtract ~6 dB from
  the new values (or add ~6 dB to the old ones). The default dB range may look
  "hotter" for the same input; adjust *Settings → dB range* if needed.
- The DC (0 Hz) and Nyquist (fs/2) bins are scaled by 1/Σw rather than 2/Σw,
  since they have no mirrored negative-frequency half. A full-scale DC offset
  or Nyquist tone now reads 0 dBFS instead of +6 dBFS.
