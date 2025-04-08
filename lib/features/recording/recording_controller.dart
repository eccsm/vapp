import 'dart:async';
import 'dart:io' show File;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import 'package:voicenotes/shared/utils/js_utils_stub.dart'
    if (dart.library.html) 'package:voicenotes/shared/utils/js_utils.dart';

import '../../api/api_service.dart';
import '../../database/app_database.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Recording state with possible inMemoryData for web
class RecordingState {
  final bool isRecording;
  final bool isPaused;
  final Duration recordingDuration;
  final double currentAmplitude;
  final String? filePath;
  final Uint8List? inMemoryData;
  final String? errorMessage;

  const RecordingState({
    this.isRecording = false,
    this.isPaused = false,
    this.recordingDuration = Duration.zero,
    this.currentAmplitude = 0.0,
    this.filePath,
    this.inMemoryData,
    this.errorMessage,
  });

  RecordingState copyWith({
    bool? isRecording,
    bool? isPaused,
    Duration? recordingDuration,
    double? currentAmplitude,
    String? filePath,
    Uint8List? inMemoryData,
    String? errorMessage,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      isPaused: isPaused ?? this.isPaused,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      currentAmplitude: currentAmplitude ?? this.currentAmplitude,
      filePath: filePath ?? this.filePath,
      inMemoryData: inMemoryData ?? this.inMemoryData,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class RecordingController extends StateNotifier<RecordingState> {
  final ApiService _apiService;
  final AppDatabase _database;

  FlutterSoundRecorder? _recorder;
  final TextEditingController titleController = TextEditingController();

  // Timer for updating the recording duration
  Timer? _durationTimer;

  // Subscription to onProgress (for amplitude and progress updates)
  StreamSubscription<RecordingDisposition>? _amplitudeSubscription;

  // Minimum recording duration: 0.5 seconds
  static const Duration _minRecordingDuration = Duration(milliseconds: 500);

  // Buffers & streams for in-memory recording (web)
  final List<int> _recordedDataBuffer = [];
  final StreamController<Uint8List> _recordedDataController =
      StreamController<Uint8List>();

  bool _isInitialized = false;

  RecordingController(this._apiService, this._database)
      : super(const RecordingState()) {
    _initRecorder();
  }

  /// Chooses the best codec for the current web browser, falling back to AAC.
  Codec _getBestCodecForWeb() {
    final userAgent = getUserAgent().toLowerCase();
    if (userAgent.contains('chrome') || userAgent.contains('firefox')) {
      return Codec.opusWebM; // opus in webm container
    } else if (userAgent.contains('safari')) {
      return Codec.aacMP4;   // Safari typically needs AAC in MP4
    }
    return Codec.aacADTS;    // fallback
  }

  /// Configure the audio session for Android/iOS (non-web).
  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
      await session.setActive(true);
      debugPrint('Audio session configured successfully');
    } catch (e) {
      debugPrint('Error configuring audio session: $e');
    }
  }

  /// Initialize the recorder, request permissions, and open the recorder.
  Future<void> _initRecorder() async {
    if (_isInitialized) return;

    try {
      // For non-web, request microphone permission
      if (!kIsWeb) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          debugPrint('Microphone permission denied');
          state = state.copyWith(
            errorMessage:
                'Microphone permission denied. Please enable it in Settings.',
          );
          return;
        }
        await _configureAudioSession();
      }

      _recorder = FlutterSoundRecorder();

      if (kIsWeb) {
        debugPrint('Running on web: no explicit AudioSession configuration');
      }

      // Open the recorder
      await _recorder?.openRecorder();
      debugPrint('Recorder opened successfully');

      // We want amplitude updates every 100ms
      await _recorder?.setSubscriptionDuration(const Duration(milliseconds: 100));

      _isInitialized = true;
      debugPrint('Recorder initialized successfully');
    } catch (e) {
      debugPrint('Error initializing recorder: $e');
      state = state.copyWith(
        errorMessage: 'Failed to initialize recorder: $e',
      );
    }
  }

  Future<void> startRecording() async {
  if (state.isRecording) return;

  try {
    if (!_isInitialized) {
      await _initRecorder();
    }
    if (_recorder == null) {
      debugPrint('Recorder is null, cannot start recording');
      state = state.copyWith(errorMessage: 'Recorder not initialized');
      return;
    }

    _recordedDataBuffer.clear();
    if (kIsWeb) {
      _recordedDataController.stream.listen((data) {
        _recordedDataBuffer.addAll(data);
      });
    }

    String? path;
    if (!kIsWeb) {
      final directory = await getTemporaryDirectory();
      // Use .m4a extension for AAC-MP4
      path = '${directory.path}/${const Uuid().v4()}.m4a';
      debugPrint('Recording to path: $path');
    }

    // Use Codec.aacMP4 so it's recognized as .m4a (MP4 container)
    final codec = kIsWeb ? _getBestCodecForWeb() : Codec.aacMP4;

    await _recorder?.startRecorder(
      codec: codec,
      toFile: path,
      toStream: kIsWeb ? _recordedDataController.sink : null,
      audioSource: AudioSource.microphone,
      bitRate: 32000,
      sampleRate: 16000,
      numChannels: 1,
    );

    state = state.copyWith(
      isRecording: true,
      isPaused: false,
      filePath: path,
      recordingDuration: Duration.zero,
      errorMessage: null,
    );
    
    // Start timers & amplitude subscription
    _startTimers();
    _amplitudeSubscription = _recorder?.onProgress?.listen((event) {
      final decibels = event.decibels ?? 0.0;
      state = state.copyWith(currentAmplitude: decibels);
    });
  } catch (e) {
    debugPrint('Error starting recording: $e');
    state = state.copyWith(
      errorMessage: 'Failed to start recording: $e',
      isRecording: false,
      isPaused: false,
    );
  }
}


  /// Pause the recording
  Future<void> pauseRecording() async {
    if (!state.isRecording || state.isPaused || _recorder == null) return;
    try {
      state = state.copyWith(isPaused: true);
      _stopTimers();
      await _recorder?.pauseRecorder();
      debugPrint('Recording paused');
    } catch (e) {
      debugPrint('Error pausing recording: $e');
      if (state.isPaused) {
        // Revert if pause failed
        state = state.copyWith(
          isPaused: false,
          errorMessage: 'Failed to pause recording: $e',
        );
        _startTimers();
      }
    }
  }

  /// Resume the recording
  Future<void> resumeRecording() async {
    if (!state.isPaused || _recorder == null) return;
    try {
      await _recorder?.resumeRecorder();
      state = state.copyWith(isPaused: false);
      _startTimers();
      _amplitudeSubscription = _recorder?.onProgress?.listen((event) {
        state = state.copyWith(currentAmplitude: event.decibels ?? 0.0);
      });
      debugPrint('Recording resumed');
    } catch (e) {
      debugPrint('Error resuming recording: $e');
      state = state.copyWith(errorMessage: 'Failed to resume recording: $e');
    }
  }

  /// Whether the current recording has reached the minimum duration
  bool get isRecordingDurationSufficient =>
      state.recordingDuration >= _minRecordingDuration;

  /// Stop the recording, then process or transcribe the result.
  Future<void> stopRecording() async {
    if ((!state.isRecording && !state.isPaused) || _recorder == null) return;

    try {
      // Check duration first
      if (!isRecordingDurationSufficient) {
        state = state.copyWith(
          errorMessage:
              'Recording too short. Please record at least 0.5 seconds.',
        );
        return;
      }

      _stopTimers();
      final path = await _recorder?.stopRecorder();
      debugPrint('Recording stopped, path: $path');

      // Handle non-web
      if (!kIsWeb && state.filePath != null) {
        final file = File(state.filePath!);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint('Recorded file size: $fileSize bytes');
          if (fileSize <= 44) {
            debugPrint('WARNING: File is just a header with no audio data!');
            state = state.copyWith(
              errorMessage:
                  'No audio was captured. Please check your microphone and retry.',
            );
            return;
          }
          // Process if valid
          await _processRecording(filePath: state.filePath!);
        } else {
          debugPrint('ERROR: File not found at ${state.filePath}');
          state = state.copyWith(errorMessage: 'Recording file not found');
        }
      }
      // Handle web
      else if (kIsWeb && _recordedDataBuffer.isNotEmpty) {
        final recordedBytes = Uint8List.fromList(_recordedDataBuffer);
        state = state.copyWith(inMemoryData: recordedBytes);
        if (recordedBytes.lengthInBytes < 1000) {
          state = state.copyWith(
            errorMessage: 'Audio file is too short. Check your microphone.',
          );
          return;
        }
        await _processRecording(inMemoryData: recordedBytes);
      } else {
        debugPrint('ERROR: No valid recording data after stopping');
        state = state.copyWith(errorMessage: 'No valid recording data');
      }

      // Reset and clear
      state = const RecordingState();
      titleController.clear();
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      state = state.copyWith(errorMessage: 'Error stopping recording: $e');
    }
  }

  /// Cancel the recording. Deletes the file if it exists.
  Future<void> cancelRecording() async {
    if ((!state.isRecording && !state.isPaused) || _recorder == null) return;
    try {
      _stopTimers();
      await _recorder?.stopRecorder();

      if (!kIsWeb && state.filePath != null) {
        final file = File(state.filePath!);
        if (await file.exists()) {
          await file.delete();
          debugPrint('Recording file deleted: ${state.filePath}');
        }
      }

      _recordedDataBuffer.clear();
      state = const RecordingState();
      titleController.clear();
      debugPrint('Recording cancelled');
    } catch (e) {
      debugPrint('Error cancelling recording: $e');
      state = state.copyWith(errorMessage: 'Error cancelling recording: $e');
    }
  }

  /// Start a 100ms timer to track total recording duration
  void _startTimers() {
    _stopTimers(); // ensure no duplicates
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final newDuration =
          state.recordingDuration + const Duration(milliseconds: 100);
      state = state.copyWith(recordingDuration: newDuration);
    });
  }

  /// Stop all timers/subscriptions
  void _stopTimers() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
  }

  /// Process the recording (transcription + saving to DB).
  Future<void> _processRecording({
    String? filePath,
    Uint8List? inMemoryData,
  }) async {
    try {
      final title = titleController.text.trim();
      final defaultTitle =
          'Voice Note ${DateTime.now().toString().substring(0, 16)}';

      // 1) Web path (inMemoryData)
      if (kIsWeb && inMemoryData != null) {
        debugPrint('Processing web recording of size: ${inMemoryData.length}');
        if (inMemoryData.isEmpty) {
          state = state.copyWith(errorMessage: 'No data in web recording');
          return;
        }
        try {
          final transcription = await _apiService.transcribeAudioBytes(
            inMemoryData,
            fileName: '${const Uuid().v4()}.webm',
            title: title.isNotEmpty ? title : null,
          );
          await _database.noteDao.insertNote(
            NotesCompanion.insert(
              title: title.isNotEmpty ? title : defaultTitle,
              content: transcription.text,
              audioPath: const Value(null),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              isSynced: const Value(false),
              categoryId: const Value(null),
            ),
          );
          debugPrint('Web note saved successfully');
        } catch (e) {
          debugPrint('Error transcribing web audio: $e');
          // Save note with fallback content
          await _database.noteDao.insertNote(
            NotesCompanion.insert(
              title: title.isNotEmpty ? title : defaultTitle,
              content: "Audio recording (transcription failed: $e)",
              audioPath: const Value(null),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              isSynced: const Value(false),
              categoryId: const Value(null),
            ),
          );
        }
      }

      // 2) File path (non-web)
      else if (filePath != null) {
        final file = File(filePath);
        if (!await file.exists()) {
          debugPrint('ERROR: File does not exist: $filePath');
          state = state.copyWith(errorMessage: 'Recording file not found');
          return;
        }

        try {
          final fileSize = await file.length();
          debugPrint('File size: $fileSize bytes before transcription');

          final transcription = await _apiService.transcribeAudio(
            file,
            title.isNotEmpty ? title : null,
          );
          await _database.noteDao.insertNote(
            NotesCompanion.insert(
              title: title.isNotEmpty ? title : defaultTitle,
              content: transcription.text,
              audioPath: Value(filePath),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              isSynced: const Value(false),
              categoryId: const Value(null),
            ),
          );
          debugPrint('Note saved successfully with audio path');
        } catch (e) {
          debugPrint('Error in file transcription: $e');
          // Save note with fallback content
          await _database.noteDao.insertNote(
            NotesCompanion.insert(
              title: title.isNotEmpty ? title : defaultTitle,
              content: "Audio recording (transcription failed: $e)",
              audioPath: Value(filePath),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              isSynced: const Value(false),
              categoryId: const Value(null),
            ),
          );
        }
      } else {
        debugPrint('ERROR: No valid recording data');
        state = state.copyWith(errorMessage: 'No valid recording data provided');
      }
    } catch (e) {
      debugPrint('Critical error: $e');
      state = state.copyWith(errorMessage: 'Error processing recording: $e');
    }
  }

  /// Clear the current error message from state
  void clearErrorMessage() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }

  @override
  void dispose() {
    // Stop timers/subscriptions
    _stopTimers();

    // Close the data stream
    try {
      _recordedDataController.close();
    } catch (_) {
      // If already closed, ignore
    }

    // Release recorder resources
    _recorder?.closeRecorder();
    _recorder = null;
    _isInitialized = false;

    titleController.dispose();
    super.dispose();
  }
}

/// Provider for the RecordingController
final recordingControllerProvider =
    StateNotifierProvider<RecordingController, RecordingState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  final database = ref.watch(databaseProvider);
  return RecordingController(apiService, database);
});
