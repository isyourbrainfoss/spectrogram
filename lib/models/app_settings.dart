/// User-configurable spectrogram settings with sane defaults.
class AppSettings {
  const AppSettings({
    this.sampleRate = 48000,
    this.fftSize = 2048,
    this.hopSize = 512,
    this.timeWindowSec = 8.0,

    /// How much live history to keep for pan/zoom after stop and for pre-roll WAV.
    this.historySec = 60.0,
    this.minFreqHz = 20.0,
    this.maxFreqHz = 12000.0,
    this.minDb = -90.0,
    this.maxDb = 0.0,
    this.colormap = ColormapKind.viridis,
    this.colorScheme = ThemePreference.system,
    // Logarithmic is the usual audio spectrogram default (more room for lows).
    this.freqScale = FreqScale.logarithmic,

    /// Spectrum peak-hold envelope (classic RTA). Off does not draw the ghost.
    this.peakHold = true,

    /// Decay of the hold envelope in dB/s. 0 = infinite hold until reset.
    this.peakHoldDecayDbPerSec = 6.0,

    /// Platform device id from `record` [InputDevice.id]. Null = system default.
    this.inputDeviceId,

    /// Last known label for display when the device list is not loaded yet.
    this.inputDeviceLabel,
  });

  final int sampleRate;
  final int fftSize;
  final int hopSize;
  final double timeWindowSec;
  final double historySec;
  final double minFreqHz;
  final double maxFreqHz;
  final double minDb;
  final double maxDb;
  final ColormapKind colormap;
  final ThemePreference colorScheme;
  final FreqScale freqScale;
  final bool peakHold;
  final double peakHoldDecayDbPerSec;
  final String? inputDeviceId;
  final String? inputDeviceLabel;

  static const defaults = AppSettings();

  static const allowedSampleRates = [16000, 22050, 44100, 48000];
  static const allowedFftSizes = [512, 1024, 2048, 4096, 8192];

  int get binCount => fftSize ~/ 2 + 1;

  double frequencyOfBin(int bin) => bin * sampleRate / fftSize;

  /// Columns needed for the *visible* live time window (approx).
  int get columnCount {
    final hopsPerSec = sampleRate / hopSize;
    return (timeWindowSec * hopsPerSec).ceil().clamp(32, 2048);
  }

  /// Columns kept in memory for pan/zoom / export (at least the visible window).
  int get historyColumnCount {
    final hopsPerSec = sampleRate / hopSize;
    final hist = (historySec * hopsPerSec).ceil();
    return hist.clamp(columnCount, 120000);
  }

  /// PCM samples kept in the live pre-roll ring (bytes = samples * 2 for PCM16).
  int get historyPcmSamples {
    return (historySec * sampleRate).ceil().clamp(sampleRate, 48000 * 600);
  }

  AppSettings copyWith({
    int? sampleRate,
    int? fftSize,
    int? hopSize,
    double? timeWindowSec,
    double? historySec,
    double? minFreqHz,
    double? maxFreqHz,
    double? minDb,
    double? maxDb,
    ColormapKind? colormap,
    ThemePreference? colorScheme,
    FreqScale? freqScale,
    bool? peakHold,
    double? peakHoldDecayDbPerSec,
    String? inputDeviceId,
    String? inputDeviceLabel,
    bool clearInputDevice = false,
  }) {
    return AppSettings(
      sampleRate: sampleRate ?? this.sampleRate,
      fftSize: fftSize ?? this.fftSize,
      hopSize: hopSize ?? this.hopSize,
      timeWindowSec: timeWindowSec ?? this.timeWindowSec,
      historySec: historySec ?? this.historySec,
      minFreqHz: minFreqHz ?? this.minFreqHz,
      maxFreqHz: maxFreqHz ?? this.maxFreqHz,
      minDb: minDb ?? this.minDb,
      maxDb: maxDb ?? this.maxDb,
      colormap: colormap ?? this.colormap,
      colorScheme: colorScheme ?? this.colorScheme,
      freqScale: freqScale ?? this.freqScale,
      peakHold: peakHold ?? this.peakHold,
      peakHoldDecayDbPerSec:
          peakHoldDecayDbPerSec ?? this.peakHoldDecayDbPerSec,
      inputDeviceId: clearInputDevice
          ? null
          : (inputDeviceId ?? this.inputDeviceId),
      inputDeviceLabel: clearInputDevice
          ? null
          : (inputDeviceLabel ?? this.inputDeviceLabel),
    );
  }

  Map<String, dynamic> toMap() => {
    'sample_rate': sampleRate,
    'fft_size': fftSize,
    'hop_size': hopSize,
    'time_window_sec': timeWindowSec,
    'history_sec': historySec,
    'min_freq_hz': minFreqHz,
    'max_freq_hz': maxFreqHz,
    'min_db': minDb,
    'max_db': maxDb,
    'colormap': colormap.name,
    'color_scheme': colorScheme.name,
    'freq_scale': freqScale.name,
    'peak_hold': peakHold,
    'peak_hold_decay_db_per_sec': peakHoldDecayDbPerSec,
    if (inputDeviceId != null) 'input_device_id': inputDeviceId,
    if (inputDeviceLabel != null) 'input_device_label': inputDeviceLabel,
  };

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    final d = defaults;
    return AppSettings(
      sampleRate: _asInt(map['sample_rate'], d.sampleRate),
      fftSize: _asInt(map['fft_size'], d.fftSize),
      hopSize: _asInt(map['hop_size'], d.hopSize),
      timeWindowSec: _asDouble(map['time_window_sec'], d.timeWindowSec),
      historySec: _asDouble(map['history_sec'], d.historySec),
      minFreqHz: _asDouble(map['min_freq_hz'], d.minFreqHz),
      maxFreqHz: _asDouble(map['max_freq_hz'], d.maxFreqHz),
      minDb: _asDouble(map['min_db'], d.minDb),
      maxDb: _asDouble(map['max_db'], d.maxDb),
      colormap: ColormapKind.values.firstWhere(
        (e) => e.name == map['colormap'],
        orElse: () => d.colormap,
      ),
      colorScheme: ThemePreference.values.firstWhere(
        (e) => e.name == map['color_scheme'],
        orElse: () => d.colorScheme,
      ),
      freqScale: FreqScale.values.firstWhere(
        (e) => e.name == map['freq_scale'],
        orElse: () => d.freqScale,
      ),
      peakHold: _asBool(map['peak_hold'], d.peakHold),
      peakHoldDecayDbPerSec: _asDouble(
        map['peak_hold_decay_db_per_sec'],
        d.peakHoldDecayDbPerSec,
      ).clamp(0.0, 48.0),
      inputDeviceId: map['input_device_id'] as String?,
      inputDeviceLabel: map['input_device_label'] as String?,
    );
  }

  /// Settings that require restarting the audio pipeline when changed.
  bool requiresPipelineRestart(AppSettings other) {
    return sampleRate != other.sampleRate ||
        fftSize != other.fftSize ||
        hopSize != other.hopSize ||
        historySec != other.historySec ||
        inputDeviceId != other.inputDeviceId;
  }

  static int _asInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  static double _asDouble(Object? v, double fallback) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return fallback;
  }

  static bool _asBool(Object? v, bool fallback) {
    if (v is bool) return v;
    return fallback;
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.sampleRate == sampleRate &&
        other.fftSize == fftSize &&
        other.hopSize == hopSize &&
        other.timeWindowSec == timeWindowSec &&
        other.historySec == historySec &&
        other.minFreqHz == minFreqHz &&
        other.maxFreqHz == maxFreqHz &&
        other.minDb == minDb &&
        other.maxDb == maxDb &&
        other.colormap == colormap &&
        other.colorScheme == colorScheme &&
        other.freqScale == freqScale &&
        other.peakHold == peakHold &&
        other.peakHoldDecayDbPerSec == peakHoldDecayDbPerSec &&
        other.inputDeviceId == inputDeviceId &&
        other.inputDeviceLabel == inputDeviceLabel;
  }

  @override
  int get hashCode => Object.hash(
    sampleRate,
    fftSize,
    hopSize,
    timeWindowSec,
    historySec,
    minFreqHz,
    maxFreqHz,
    minDb,
    maxDb,
    colormap,
    colorScheme,
    freqScale,
    peakHold,
    peakHoldDecayDbPerSec,
    inputDeviceId,
    inputDeviceLabel,
  );
}

enum ColormapKind { viridis, magma, turbo, grayscale }

enum ThemePreference { system, light, dark }

enum FreqScale { linear, logarithmic }
