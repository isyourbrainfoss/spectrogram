import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:spectrogram/dsp/colormap.dart';
import 'package:spectrogram/dsp/freq_axis.dart';
import 'package:spectrogram/dsp/pcm.dart';
import 'package:spectrogram/dsp/stft_processor.dart';
import 'package:spectrogram/models/app_settings.dart';
import 'package:spectrogram/services/audio_capture_service.dart';

enum EngineStatus { idle, starting, running, error, noPermission }

/// Coordinates mic capture → STFT → ring buffers for the UI.
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

  /// Circular spectrogram color columns (ARGB) and parallel dB columns.
  late List<Uint32List> _colorColumns;
  late List<Float32List> _dbColumns;
  int _writeIndex = 0;
  int _filled = 0;
  int _fromBin = 0;

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

  AppSettings get settings => _settings;
  EngineStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isRunning => _status == EngineStatus.running;
  double? get peakFreqHz => _peakFreqHz;
  double? get peakDb => _peakDb;

  int get columnCount => _colorColumns.length;
  int get displayBins => _displayDb.length;
  int get filledColumns => _filled;
  int get writeIndex => _writeIndex;

  Float32List get latestDb => _latestDb;
  Float32List get displayDb => _displayDb;
  Float32List get displayFreqs => _displayFreqs;
  ColorMap get colorMap => _colorMap;

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

  Future<void> applySettings(AppSettings next) async {
    final restart = _settings.requiresPipelineRestart(next) ||
        _settings.timeWindowSec != next.timeWindowSec ||
        _settings.minFreqHz != next.minFreqHz ||
        _settings.maxFreqHz != next.maxFreqHz;
    // Freq scale only remaps display — no capture restart needed.
    final wasRunning = isRunning;
    if (restart && wasRunning) {
      await stop();
    }
    _settings = next;
    if (restart) {
      _rebuildPipeline();
    } else {
      // Colormap / scale / dB range can update live.
      _colorMap = ColorMap.of(_settings.colormap);
    }
    if (restart && wasRunning) {
      await start();
    } else {
      notifyListeners();
    }
  }

  void _rebuildPipeline() {
    _processor = StftProcessor(
      fftSize: _settings.fftSize,
      hopSize: _settings.hopSize,
    );
    _colorMap = ColorMap.of(_settings.colormap);
    final range = _computeDisplayBinRange();
    _fromBin = range.fromBin;
    final cols = _settings.columnCount;
    _colorColumns = List.generate(cols, (_) => Uint32List(range.count));
    _dbColumns = List.generate(cols, (_) => Float32List(range.count));
    _writeIndex = 0;
    _filled = 0;
    _latestDb = Float32List(_processor.binCount);
    _displayDb = Float32List(range.count);
    _displayFreqs = Float32List(range.count);
    for (var i = 0; i < range.count; i++) {
      _displayFreqs[i] =
          _processor.frequencyOfBin(range.fromBin + i, _settings.sampleRate);
    }
    _peakFreqHz = null;
    _peakDb = null;
  }

  ({int fromBin, int toBin, int count}) _computeDisplayBinRange() {
    final sr = _settings.sampleRate;
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
    _status = EngineStatus.starting;
    notifyListeners();

    final permitted = await _capture.hasPermission();
    if (!permitted) {
      _status = EngineStatus.noPermission;
      notifyListeners();
      return;
    }

    try {
      _processor.reset();
      await _capture.start(
        sampleRate: _settings.sampleRate,
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
    if (_status != EngineStatus.noPermission) {
      _status = EngineStatus.idle;
    }
    // History + last spectrum stay in memory so the user can place a crosshair
    // after stopping (no separate freeze control).
    notifyListeners();
  }

  void clearHistory() {
    for (var i = 0; i < _colorColumns.length; i++) {
      _colorColumns[i].fillRange(0, _colorColumns[i].length, 0);
      _dbColumns[i].fillRange(0, _dbColumns[i].length, _settings.minDb);
    }
    _writeIndex = 0;
    _filled = 0;
    _peakFreqHz = null;
    _peakDb = null;
    notifyListeners();
  }

  void _onPcm(Uint8List bytes) {
    if (_disposed) return;
    final samples = pcm16ToMonoFloat(bytes);
    if (samples.isEmpty) return;

    final rangeCount = displayBins;
    _processor.push(samples, (db) {
      _latestDb.setAll(0, db);

      final peak = StftProcessor.peakBin(
        db,
        from: _fromBin,
        to: _fromBin + rangeCount,
      );
      _peakFreqHz = _processor.frequencyOfBin(peak, _settings.sampleRate);
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
      _maybeNotify();
    });
  }

  void _maybeNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) >= _notifyInterval) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  /// Spectrogram sample: [normX] 0=oldest … 1=newest,
  /// [normY] 0=minFreq … 1=maxFreq (honours linear/log scale).
  ({double freqHz, double db, int colAge, int binIndex})? sampleSpectrogram({
    required double normX,
    required double normY,
  }) {
    if (_filled == 0 || displayBins == 0) return null;
    final age = (normX.clamp(0.0, 1.0) * (_filled - 1)).round();
    final hz = FreqAxis.normToFreq(
      normY,
      _settings.minFreqHz,
      _settings.maxFreqHz,
      _settings.freqScale,
    );
    final binIndex = FreqAxis.binForFreq(_displayFreqs, hz);
    final db = dbColumnAt(age)[binIndex];
    return (
      freqHz: _displayFreqs[binIndex],
      db: db,
      colAge: age,
      binIndex: binIndex,
    );
  }

  /// Spectrum sample: [normX] 0=minFreq … 1=maxFreq (honours linear/log scale).
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
