
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoiceMusicApp());
}

class VoiceMusicApp extends StatelessWidget {
  const VoiceMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Music Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF10111B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B87F5),
          brightness: Brightness.dark,
        ),
      ),
      home: const MusicHomePage(),
    );
  }
}

class MusicHomePage extends StatefulWidget {
  const MusicHomePage({super.key});

  @override
  State<MusicHomePage> createState() => _MusicHomePageState();
}

class _MusicHomePageState extends State<MusicHomePage> {
  final AudioPlayer _player = AudioPlayer();
  final SpeechToText _speech = SpeechToText();

  List<PlatformFile> _tracks = [];
  int _currentIndex = 0;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _busy = false;
  String _message = 'آهنگ انتخاب کن یا از فرمان صوتی استفاده کن.';
  String _recognizedWords = '';

  PlatformFile? get _currentTrack {
    if (_tracks.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _tracks.length) {
      return null;
    }
    return _tracks[_currentIndex];
  }

  @override
  void initState() {
    super.initState();
    _initializeSpeech();

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          _currentIndex + 1 < _tracks.length) {
        _playTrack(_currentIndex + 1);
      }
    });
  }

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            _isListening = _speech.isListening;
          });
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _message = 'خطای تشخیص صدا: ${error.errorMsg}';
            _isListening = false;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _speechAvailable = available;
        _message = available
            ? 'آماده هستم. یک فرمان صوتی بگو.'
            : 'تشخیص صدا در دسترس نیست.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'راه‌اندازی میکروفون ناموفق بود.';
      });
    }
  }

  Future<void> _pickMusic() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      final files = result.files
          .where((file) => file.path != null)
          .toList();

      if (files.isEmpty) {
        _showMessage('فایل قابل پخش پیدا نشد.');
        return;
      }

      setState(() {
        _tracks = files;
        _currentIndex = 0;
        _message = '${files.length} آهنگ انتخاب شد.';
      });

      await _playTrack(0);
    } catch (e) {
      _showMessage('باز کردن فایل‌ها ناموفق بود.');
    }
  }

  Future<void> _playTrack(int index) async {
    if (_tracks.isEmpty || index < 0 || index >= _tracks.length) {
      _showMessage('ابتدا آهنگ انتخاب کن.');
      return;
    }

    final path = _tracks[index].path;
    if (path == null) {
      _showMessage('مسیر فایل در دسترس نیست.');
      return;
    }

    setState(() {
      _busy = true;
      _currentIndex = index;
      _message = 'در حال آماده‌سازی موسیقی...';
    });

    try {
      await _player.setFilePath(path);
      await _player.play();

      if (!mounted) return;
      setState(() {
        _message = 'در حال پخش موسیقی';
      });
    } catch (e) {
      _showMessage('پخش این فایل ناموفق بود.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_tracks.isEmpty) {
      await _pickMusic();
      return;
    }

    if (_player.playing) {
      await _player.pause();
      _showMessage('پخش متوقف شد.');
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
      _showMessage('پخش موسیقی ادامه یافت.');
    }
  }

  Future<void> _nextTrack() async {
    if (_currentIndex + 1 < _tracks.length) {
      await _playTrack(_currentIndex + 1);
    } else {
      _showMessage('آهنگ بعدی وجود ندارد.');
    }
  }

  Future<void> _previousTrack() async {
    if (_currentIndex > 0) {
      await _playTrack(_currentIndex - 1);
    } else {
      _showMessage('آهنگ قبلی وجود ندارد.');
    }
  }

  Future<void> _toggleVoiceControl() async {
    if (!_speechAvailable) {
      await _initializeSpeech();
      if (!_speechAvailable) {
        _showMessage('تشخیص صدا در دسترس نیست.');
        return;
      }
    }

    if (_speech.isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
      return;
    }

    setState(() {
      _recognizedWords = '';
      _message = 'گوش می‌دهم...';
      _isListening = true;
    });

    try {
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;

          setState(() {
            _recognizedWords = result.recognizedWords;
          });

          if (result.finalResult) {
            _handleVoiceCommand(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
      );
    } catch (e) {
      _showMessage('شروع تشخیص صدا ناموفق بود.');
    }
  }

  Future<void> _handleVoiceCommand(String words) async {
    final command = words.toLowerCase().trim();

    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }

    if (command.contains('بعدی') ||
        command.contains('بعد') ||
        command.contains('next')) {
      await _nextTrack();
    } else if (command.contains('قبلی') ||
        command.contains('previous')) {
      await _previousTrack();
    } else if (command.contains('توقف') ||
        command.contains('ایست') ||
        command.contains('مکث') ||
        command.contains('pause') ||
        command.contains('stop')) {
      await _player.pause();
      _showMessage('پخش متوقف شد.');
    } else if (command.contains('پخش') ||
        command.contains('ادامه') ||
        command.contains('play') ||
        command.contains('شروع')) {
      if (_tracks.isEmpty) {
        await _pickMusic();
      } else {
        await _togglePlayback();
      }
    } else if (command.contains('آهنگ') ||
        command.contains('موسیقی') ||
        command.contains('music')) {
      await _pickMusic();
    } else {
      _showMessage('فرمان شناخته نشد. دوباره امتحان کن.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() {
      _message = message;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _speech.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = _currentTrack;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Voice Music Player',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF5947A8),
                    Color(0xFF242448),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.album_rounded,
                    size: 110,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    track?.name ?? 'هیچ آهنگی انتخاب نشده',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    track == null
                        ? 'یک آهنگ از گوشی انتخاب کن'
                        : 'آهنگ ${_currentIndex + 1} از ${_tracks.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration =
                          _player.duration ?? Duration.zero;

                      final max = duration.inMilliseconds > 0
                          ? duration.inMilliseconds.toDouble()
                          : 1.0;

                      final value = position.inMilliseconds
                          .toDouble()
                          .clamp(0.0, max);

                      return Column(
                        children: [
                          Slider(
                            value: value,
                            max: max,
                            onChanged: duration.inMilliseconds > 0
                                ? (newValue) {
                                    _player.seek(
                                      Duration(
                                        milliseconds: newValue.round(),
                                      ),
                                    );
                                  }
                                : null,
                          ),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_formatDuration(position)),
                              Text(_formatDuration(duration)),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _previousTrack,
                        icon: const Icon(Icons.skip_previous_rounded),
                        iconSize: 42,
                      ),
                      const SizedBox(width: 12),
                      StreamBuilder<PlayerState>(
                        stream: _player.playerStateStream,
                        builder: (context, snapshot) {
                          final playing =
                              snapshot.data?.playing ?? false;

                          return FilledButton(
                            onPressed:
                                _busy ? null : _togglePlayback,
                            style: FilledButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(22),
                            ),
                            child: Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 38,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _nextTrack,
                        icon: const Icon(Icons.skip_next_rounded),
                        iconSize: 42,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickMusic,
              icon: const Icon(Icons.library_music_rounded),
              label: const Text('انتخاب آهنگ از گوشی'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(17),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _toggleVoiceControl,
              icon: Icon(
                _isListening ? Icons.mic : Icons.mic_none_rounded,
              ),
              label: Text(
                _isListening ? 'توقف گوش دادن' : 'فرمان صوتی',
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(17),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: const Color(0xFF1D1E2D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'وضعیت برنامه',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_message),
                    if (_recognizedWords.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('صدای تشخیص داده‌شده: $_recognizedWords'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'فرمان‌های صوتی',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text('• «پخش کن» یا «ادامه بده»'),
            const Text('• «توقف کن» یا «مکث»'),
            const Text('• «آهنگ بعدی»'),
            const Text('• «آهنگ قبلی»'),
            const SizedBox(height: 12),
            const Text(
              'برای فرمان صوتی، زبان تشخیص گفتار گوشی را روی فارسی یا انگلیسی تنظیم کن.',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
