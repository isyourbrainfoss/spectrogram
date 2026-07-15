import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:spectrogram/audio/wav_io.dart';
import 'package:spectrogram/dsp/colormap.dart';
import 'package:spectrogram/dsp/freq_axis.dart';
import 'package:spectrogram/dsp/pcm.dart';
import 'package:spectrogram/dsp/stft_processor.dart';
import 'package:spectrogram/models/app_settings.dart';
import 'package:spectrogram/services/audio_capture_service.dart';

enum EngineStatus { idle, starting, running, error, noPermission }

/// Coordinates mic capture / file import → STFT → ring buffers for the UI.
class SpectrogramEngine extends ChangeNotifier {
  SpectrogramEngine({
    AudioCaptureService? capture,
    AppSettings? settings,
  })  : _capture = capture ?? AudioCaptureService(),
        _settings = settings ?? AppSettings.defaults {
    _rebuildPipeline();
  }

  final AudioCaptureService _capture;
  AppSettings _settings;
  late StftProcessor _processor;
  late ColorMap _colorMap;

  /// When set (imported file), overrides [AppSettings.sampleRate] for analysis.
  int? _sourceSampleRate;

  /// Circular spectrogram color columns (ARGB) and parallel dB columns.
  late List<Uint32List> _colorColumns;
  late List<Float32List> _dbColumns;
  int _writeIndex = 0;
  int _filled = 0;
  int _fromBin = 0;

  /// Visible window into history (for import pan/zoom; live always follows end).
  int _viewStart = 0;
  int _visibleColumns = 32;
  bool _followLive = true;

  late Float32List _latestDb;
  late Float32List _displayDb;
  late Float32List _displayFreqs;

  EngineStatus _status = EngineStatus.idle;
  String? _errorMessage;
  bool _disposed = false;

  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  static const _notifyInterval = Duration(milliseconds: 33);

  double? _peakFreqHz;
  double? _peakDb;

  // --- File recording (PCM while live) ---
  bool _recording = false;
  BytesBuilder? _recordBuffer;
  int? _recordSampleRate;
  String? _sourceLabel; // e.g. imported file name

  AppSettings get settings => _settings;
  EngineStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isRunning => _status == EngineStatus.running;
  double? get peakFreqHz => _peakFreqHz;
  double? get peakDb => _peakDb;
  bool get isRecordingToFile => _recording;
  String? get sourceLabel => _sourceLabel;

  /// Sample rate used for the current STFT / frequency axis.
  int get activeSampleRate => _sourceSampleRate ?? _settings.sampleRate;

  int get columnCount => _colorColumns.length;
  int get displayBins => _displayDb.length;
  int get filledColumns => _filled;
  int get writeIndex => _writeIndex;

  /// Leftmost visible column age (0 = oldest stored).
  int get viewStart => _viewStart.clamp(0, math.max(0, _filled - 1));

  /// Number of columns drawn in the spectrogram view.
  int get viewColumnCount {
    if (_filled == 0) return 0;
    return math.min(_visibleColumns, _filled);
  }

  bool get followLive => _followLive;
  bool get canPan => _filled > viewColumnCount;

  Float32List get latestDb => _latestDb;
  Float32List get displayDb => _displayDb;
  Float32List get displayFreqs => _displayFreqs;
  ColorMap get colorMap => _colorMap;

  /// Approximate recorded duration while recording (or 0).
  double get recordingSeconds {
    if (_recordBuffer == null || _recordSampleRate == null) return 0;
    final samples = _recordBuffer!.length ~/ 2;
    return samples / _recordSampleRate!;
  }

  Uint32List colorColumnAt(int age) {
    if (_filled == 0) return Uint32List(displayBins);
    return _colorColumns[_ageToIndex(age)];
  }

  Float32List dbColumnAt(int age) {
    if (_filled == 0) return Float32List(displayBins);
    return _dbColumns[_ageToIndex(age)];
  }

  int _ageToIndex(int age) {
    final clamped = age.clamp(0, _filled - 1);
    final idx = (_writeIndex - _filled + clamped) % columnCount;
    return idx < 0 ? idx + columnCount : idx;
  }

  /// Available capture devices (Android / Linux via `record`).
  Future<List<InputDevice>> listInputDevices() => _capture.listInputDevices();

  /// Request mic permission so platforms can populate the device list.
  Future<bool> hasPermissionForDevices() => _capture.hasPermission();

  Future<void> applySettings(AppSettings next) async {
    final prev = _settings;
    final structural = prev.sampleRate != next.sampleRate ||
        prev.fftSize != next.fftSize ||
        prev.hopSize != next.hopSize ||
        prev.timeWindowSec != next.timeWindowSec ||
        prev.minFreqHz != next.minFreqHz ||
        prev.maxFreqHz != next.maxFreqHz;
    final restartCapture = prev.requiresPipelineRestart(next);
    final wasRunning = isRunning;

    if ((restartCapture || structural) && wasRunning) {
      await stop();
    }

    _settings = next;
    if (structural && _sourceSampleRate == null) {
      _rebuildPipeline();
    } else if (structural && _sourceSampleRate != null) {
      // Keep imported sample rate override but rebuild bins.
      _rebuildPipeline();
    } else {
      _colorMap = ColorMap.of(_settings.colormap);
    }

    if ((restartCapture || structural) && wasRunning) {
      await start();
    } else {
      notifyListeners();
    }
  }

  InputDevice? _resolveInputDevice() {
    final id = _settings.inputDeviceId;
    if (id == null || id.isEmpty) return null;
    return InputDevice(
      id: id,
      label: _settings.inputDeviceLabel ?? id,
    );
  }

  void _rebuildPipeline({int? capacity}) {
    _processor = StftProcessor(
      fftSize: _settings.fftSize,
      hopSize: _settings.hopSize,
    );
    _colorMap = ColorMap.of(_settings.colormap);
    final range = _computeDisplayBinRange();
    _fromBin = range.fromBin;
    final defaultVis = _settings.columnCount;
    _visibleColumns = defaultVis;
    final cols = (capacity ?? defaultVis).clamp(32, 120000);
    _colorColumns = List.generate(cols, (_) => Uint32List(range.count));
    _dbColumns = List.generate(cols, (_) => Float32List(range.count));
    _writeIndex = 0;
    _filled = 0;
    _viewStart = 0;
    _followLive = true;
    _latestDb = Float32List(_processor.binCount);
    _displayDb = Float32List(range.count);
    _displayFreqs = Float32List(range.count);
    final sr = activeSampleRate;
    for (var i = 0; i < range.count; i++) {
      _displayFreqs[i] =
          _processor.frequencyOfBin(range.fromBin + i, sr);
    }
    _peakFreqHz = null;
    _peakDb = null;
  }

  /// Pan the visible window by [deltaColumns] (positive → newer / right).
  void panViewport(int deltaColumns) {
    if (_filled <= viewColumnCount) return;
    _followLive = false;
    final maxStart = _filled - viewColumnCount;
    _viewStart = (_viewStart + deltaColumns).clamp(0, maxStart);
    notifyListeners();
  }

  /// Zoom visible window. [factor] > 1 zooms in (fewer columns / shorter span).
  void zoomViewport(double factor) {
    if (_filled == 0 || factor <= 0 || !factor.isFinite) return;
    _followLive = false;
    final minVis = math.min(32, _filled);
    final maxVis = _filled;
    final next = (_visibleColumns / factor).round().clamp(minVis, maxVis);
    _visibleColumns = next;
    final maxStart = math.max(0, _filled - _visibleColumns);
    _viewStart = _viewStart.clamp(0, maxStart);
    notifyListeners();
  }

  /// Snap view to the live edge (right / newest).
  void followLiveEnd() {
    _followLive = true;
    _viewStart = math.max(0, _filled - _visibleColumns);
    notifyListeners();
  }

  /// Snap view to the start of stored history (oldest).
  void goToHistoryStart() {
    _followLive = false;
    _viewStart = 0;
    notifyListeners();
  }

  /// Visible time span in seconds (approximate).
  double get viewDurationSec => viewColumnCount * secondsPerColumn;

  /// Time of the left edge of the viewport relative to newest sample.
  double get viewLeftTimeSec {
    if (_filled == 0) return 0;
    return (viewStart - (_filled - 1)) * secondsPerColumn;
  }

  /// Time of the right edge of the viewport relative to newest sample.
  double get viewRightTimeSec {
    if (_filled == 0) return 0;
    final rightAge = viewStart + viewColumnCount - 1;
    return (rightAge - (_filled - 1)) * secondsPerColumn;
  }

  ({int fromBin, int toBin, int count}) _computeDisplayBinRange() {
    final sr = activeSampleRate;
    final nyquist = sr / 2.0;
    final minF = _settings.minFreqHz.clamp(0.0, nyquist);
    final maxF = _settings.maxFreqHz.clamp(minF + 1, nyquist);
    final fromBin = _processor.binOfFrequency(minF, sr);
    var toBin = _processor.binOfFrequency(maxF, sr);
    if (toBin <= fromBin) toBin = fromBin + 1;
    toBin = toBin.clamp(fromBin + 1, _processor.binCount - 1);
    return (fromBin: fromBin, toBin: toBin, count: toBin - fromBin + 1);
  }

  Future<void> start() async {
    if (_disposed) return;
    _errorMessage = null;
    _sourceSampleRate = null; // live mic uses settings sample rate
    _sourceLabel = null;
    _status = EngineStatus.starting;
    notifyListeners();

    final permitted = await _capture.hasPermission();
    if (!permitted) {
      _status = EngineStatus.noPermission;
      notifyListeners();
      return;
    }

    try {
      _rebuildPipeline();
      _processor.reset();
      await _capture.start(
        sampleRate: _settings.sampleRate,
        device: _resolveInputDevice(),
        onPcm: _onPcm,
        onError: (e) {
          _status = EngineStatus.error;
          _errorMessage = e.toString();
          notifyListeners();
        },
      );
      _status = EngineStatus.running;
      notifyListeners();
    } catch (e) {
      _status = EngineStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _capture.stop();
    // Keep file recording buffer until user saves or cancels.
    if (_status != EngineStatus.noPermission) {
      _status = EngineStatus.idle;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Recording
  // ---------------------------------------------------------------------------

  /// Start capturing raw PCM to a buffer (requires live mic to be running).
  void startFileRecording() {
    if (!isRunning) return;
    _recording = true;
    _recordBuffer = BytesBuilder(copy: false);
    _recordSampleRate = activeSampleRate;
    notifyListeners();
  }

  /// Stop recording and return a complete WAV (PCM16 mono), or null if empty.
  Uint8List? stopFileRecordingAsWav() {
    _recording = false;
    final buf = _recordBuffer;
    final sr = _recordSampleRate;
    _recordBuffer = null;
    _recordSampleRate = null;
    notifyListeners();
    if (buf == null || sr == null || buf.length < 2) return null;
    final pcm = buf.toBytes();
    return WavIo.encodeMonoPcm16Bytes(pcm16le: pcm, sampleRate: sr);
  }

  /// Discard an in-progress recording without saving.
  void cancelFileRecording() {
    _recording = false;
    _recordBuffer = null;
    _recordSampleRate = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Import / offline analysis
  // ---------------------------------------------------------------------------

  /// Decode [wavBytes] and run STFT offline into the ring buffer.
  Future<void> importWavBytes(Uint8List wavBytes, {String? label}) async {
    final wav = WavIo.decode(wavBytes);
    await analyzeMono(wav.samples, wav.sampleRate, label: label);
  }

  /// Run STFT on mono float samples (offline, as fast as possible).
  Future<void> analyzeMono(
    Float32List samples,
    int sampleRate, {
    String? label,
  }) async {
    if (_disposed) return;
    await stop();
    cancelFileRecording();
    _sourceSampleRate = sampleRate;
    _sourceLabel = label;

    // Size history for the whole file (capped), not just the live time window.
    final hop = _settings.hopSize;
    final fft = _settings.fftSize;
    final hops = samples.length <= fft
        ? 1
        : ((samples.length - fft) / hop).ceil().clamp(1, 120000);
    _rebuildPipeline(capacity: hops);
    _followLive = false;
    _processor.reset();

    // Feed in chunks to avoid huge temporary allocations in STFT.
    const chunk = 8192;
    for (var i = 0; i < samples.length; i += chunk) {
      final end = math.min(i + chunk, samples.length);
      final slice = samples.sublist(i, end);
      _processor.push(slice, _ingestFrame);
    }
    // Start at beginning of file so user can pan through the whole recording.
    _viewStart = 0;
    _visibleColumns = math.min(_settings.columnCount, _filled);
    notifyListeners();
  }

  void clearHistory() {
    for (var i = 0; i < _colorColumns.length; i++) {
      _colorColumns[i].fillRange(0, _colorColumns[i].length, 0);
      _dbColumns[i].fillRange(0, _dbColumns[i].length, _settings.minDb);
    }
    _writeIndex = 0;
    _filled = 0;
    _viewStart = 0;
    _followLive = true;
    _peakFreqHz = null;
    _peakDb = null;
    _sourceLabel = null;
    notifyListeners();
  }

  void _onPcm(Uint8List bytes) {
    if (_disposed) return;
    if (_recording && _recordBuffer != null) {
      _recordBuffer!.add(bytes);
    }
    final samples = pcm16ToMonoFloat(bytes);
    if (samples.isEmpty) return;
    _processor.push(samples, _ingestFrame);
  }

  void _ingestFrame(Float32List db) {
    final rangeCount = displayBins;
    final sr = activeSampleRate;
    _latestDb.setAll(0, db);

    final peak = StftProcessor.peakBin(
      db,
      from: _fromBin,
      to: _fromBin + rangeCount,
    );
    _peakFreqHz = _processor.frequencyOfBin(peak, sr);
    _peakDb = db[peak];

    final colorCol = _colorColumns[_writeIndex];
    final dbCol = _dbColumns[_writeIndex];
    for (var i = 0; i < rangeCount; i++) {
      final v = db[_fromBin + i];
      _displayDb[i] = v;
      dbCol[i] = v;
      colorCol[i] = _colorMap.mapDb(v, _settings.minDb, _settings.maxDb);
    }

    _writeIndex = (_writeIndex + 1) % columnCount;
    if (_filled < columnCount) _filled++;
    if (_followLive || isRunning) {
      _viewStart = math.max(0, _filled - _visibleColumns);
    }
    _maybeNotify();
  }

  void _maybeNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) >= _notifyInterval) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  /// Seconds per spectrogram column (hop duration).
  double get secondsPerColumn => _settings.hopSize / activeSampleRate;

  ({
    double freqHz,
    double db,
    int colAge,
    int binIndex,
    double timeSec,
  })? sampleSpectrogram({
    required double normX,
    required double normY,
  }) {
    if (_filled == 0 || displayBins == 0 || viewColumnCount == 0) return null;
    // Map [0,1] onto the *visible* window (pan/zoom aware).
    final vis = viewColumnCount;
    final local = vis <= 1
        ? 0
        : (normX.clamp(0.0, 1.0) * (vis - 1)).round().clamp(0, vis - 1);
    final age = (viewStart + local).clamp(0, _filled - 1);
    final hz = FreqAxis.normToFreq(
      normY,
      _settings.minFreqHz,
      _settings.maxFreqHz,
      _settings.freqScale,
    );
    final binIndex = FreqAxis.binForFreq(_displayFreqs, hz);
    final db = dbColumnAt(age)[binIndex];
    final timeSec = (age - (_filled - 1)) * secondsPerColumn;
    return (
      freqHz: _displayFreqs[binIndex],
      db: db,
      colAge: age,
      binIndex: binIndex,
      timeSec: timeSec,
    );
  }

  ({double freqHz, double db, int binIndex})? sampleSpectrum(double normX) {
    if (displayBins == 0) return null;
    final hz = FreqAxis.normToFreq(
      normX,
      _settings.minFreqHz,
      _settings.maxFreqHz,
      _settings.freqScale,
    );
    final binIndex = FreqAxis.binForFreq(_displayFreqs, hz);
    return (
      freqHz: _displayFreqs[binIndex],
      db: _displayDb[binIndex],
      binIndex: binIndex,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_capture.dispose());
    super.dispose();
  }
}
