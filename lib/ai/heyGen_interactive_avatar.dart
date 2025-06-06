//////////////////////////////////////////////////////////////////Last give buiid///////////////////////////////////////////////////////////////////////////////////
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/constants/colors.dart';
import 'package:flutter_application_1/constants/images.dart';
import 'package:flutter_application_1/home_screen.dart';
import 'package:flutter_application_1/widgets/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

class HeyGenHomePage extends StatefulWidget {
  const HeyGenHomePage({super.key});

  @override
  State<HeyGenHomePage> createState() => _HeyGenHomePageState();
}

class _HeyGenHomePageState extends State<HeyGenHomePage> {
  final _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  final TextEditingController _sendMessageController = TextEditingController();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();
  StreamController<Uint8List>? _audioStreamController;

  WebSocketChannel? _channel;
  Room? _room;
  RemoteVideoTrack? _videoTrack;

  String? _sessionId;
  bool _micEnabled = true;
  bool _isRecordingAudio = false;
  bool _isListening = false;
  bool _isBusy = false;
  bool _isSessionActive = false;
  bool _isLoading = false; // ← Controls our loader
  bool isSocketReady = false;

  final String apiToken = dotenv.env['HEYGEN_API_KEY'] ?? '';
  final String elevenLabsApiKey = dotenv.env['ELEVENLABS_API_KEY'] ?? '';
  final String elevenLabsVoiceId = dotenv.env['ELEVENLABS_VOICE_ID'] ?? '';
  final String agentId = dotenv.env['ELEVENLABS_AGENT_ID'] ?? '';
  final String heyGenAvatarID =
      dotenv.env['HEYGEN_AVATAR'] ?? 'EXAVITQu4vr4xnSDxMaL';

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerComplete.listen((_) async {
      if (mounted) {
        setState(() => _micEnabled = true);
        await _startRecording();
      }
    });
    _initializeSession();
  }

  Future<void> _initializeSession() async {
    // Show loader while session spins up
    await _startSession();
    await _connectWebSocket();
    _greetUser();
  }

  Future<void> _withBusy(Future<void> Function() task) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _startSession() async => _withBusy(() async {
    setState(() => _isLoading = true); // ← Begin loading

    final sessionData = await _createHeyGenSession();
    _sessionId = sessionData['session_id'];
    final liveKitUrl = sessionData['url'];
    final liveKitToken = sessionData['access_token'];

    await _startHeyGenSession();

    _room = await _connectToLiveKit(liveKitUrl, liveKitToken);
    _room!.events.listen((event) {
      if (event is TrackSubscribedEvent) {
        final track = event.track;

        // 1) If it's video, show it
        if (track is RemoteVideoTrack && mounted) {
          setState(() {
            _videoTrack = track;
          });
        } else if (track is RemoteAudioTrack) {
          // track.setPlaybackEnabled(false);
        }
      } else if (event is RoomDisconnectedEvent && mounted) {
        // Unexpected disconnect: tell the user
        // _showSessionEndDialog("Session ended unexpectedly.");
      }
    });

    setState(() {
      _isSessionActive = true;
      _isLoading = false; // ← Loading done
    });
  });

  Future<void> _endSession() async => _withBusy(() async {
    if (_sessionId != null && _room != null) {
      await _stopHeyGenStreaming();
      setState(() {
        _sessionId = null;
        _room = null;
        _videoTrack = null;
        _messages.clear();
        _isSessionActive = false;
      });
    }
  });

  Future<void> _stopHeyGenStreaming() async {
    if (_sessionId == null) return;
    final response = await http.post(
      Uri.parse('https://api.heygen.com/v1/streaming.stop'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiToken',
      },
      body: jsonEncode({'session_id': _sessionId}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to stop session: ${response.body}');
    }
    await _room!.disconnect();
  }

  Future<Room> _connectToLiveKit(String url, String token) async {
    final room = Room();
    await room.connect(url, token);
    return room;
  }

  Future<void> _connectWebSocket() async {
    if (_channel != null) return;
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse(
          "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=$agentId",
        ),
      );
      _channel!.sink.add(jsonEncode({'agent_id': agentId}));

      _channel!.stream.listen(
        _handleWebSocketData,
        onError: (e) {
          debugPrint('WebSocket error: $e');
          _showSessionEndDialog("Session ended unexpectedly");
        },
        onDone: () {
          debugPrint('WebSocket closed');
          _showSessionEndDialog("Session ended unexpectedly");
        },
      );
    } catch (_) {
      // ignore silently
    }
  }

  void _handleWebSocketData(dynamic data) async {
    try {
      final response = jsonDecode(data);
      if (response['type'] == 'ping') return;
      if (response['event'] == 'ready') {
        setState(() => isSocketReady = true);
        return;
      }

      if (response['type'] == 'user_transcript' &&
          response['user_transcription_event']?['user_transcript'] != null) {
        final userTranscript =
            response['user_transcription_event']['user_transcript'];
        if (userTranscript.trim().isNotEmpty) {
          setState(() {
            _messages.add({'sender': 'user', 'text': userTranscript.trim()});
          });
          _scrollToBottom();
        }
        return;
      }

      final aiText =
          response['agent_response_event']?['agent_response'] ??
          response['agent_response'] ??
          response['text'];
      if (aiText?.trim().isNotEmpty == true) {
        setState(() => _isListening = true);
        if (mounted) setState(() => _isListening = false);
        _sendAvatar(aiText.trim());
        _scrollToBottom();
      }
    } catch (_) {
      // ignore parse errors
    }
  }

  Future<void> _greetUser() async {
    if (_micEnabled) await _startRecording();
  }

  Future<void> _startRecording() async {
    if (_audioStreamController != null) return;
    await Permission.microphone.request();
    await _recorder.openRecorder();
    _audioStreamController = StreamController<Uint8List>();
    _audioStreamController!.stream.listen((buffer) {
      if (buffer.isNotEmpty) {
        final message = jsonEncode({"user_audio_chunk": base64Encode(buffer)});
        _channel?.sink.add(message);
      }
    });
    await _recorder.startRecorder(
      codec: Codec.pcm16,
      sampleRate: 16000,
      numChannels: 1,
      toStream: _audioStreamController!.sink,
    );
    if (mounted) setState(() => _isRecordingAudio = true);
  }

  Future<void> _stopRecording() async {
    if (!_recorder.isRecording) return;
    await _recorder.stopRecorder();
    _audioStreamController?.close();
    _audioStreamController = null;
    if (mounted) setState(() => _isRecordingAudio = false);
  }

  Future<void> _showSessionEndDialog(String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                CommonWidgets.customButton(
                  onPressed: () {
                    _cleanupResources();
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HomeScreen(),
                      ),
                      (route) => false,
                    );
                  },
                  label: 'Ok',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cleanupResources() async {
    if (_recorder.isRecording) {
      await _stopRecording();
    }
    await _channel?.sink.close();
    if (_sessionId != null && apiToken.isNotEmpty) {
      await _disconnectWebSocket();
      await _endSession();
      await _stopHeyGenStreaming();
    }
    await _room?.disconnect();
    _scrollController.dispose();
    _audioPlayer.stop();
    _audioStreamController?.close();
    _audioStreamController = null;
    if (mounted) {
      setState(() {
        isSocketReady = false;
        _sessionId = null;
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_recorder.isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
    if (mounted) setState(() => _micEnabled = !_micEnabled);
  }

  Future<void> stopStreaming(String sessionId, String apiKey) async {
    final url = Uri.parse("https://api.heygen.com/v1/streaming.stop");
    final payload = jsonEncode({"session_id": sessionId});
    final headers = {
      "accept": "application/json",
      "content-type": "application/json",
      "x-api-key": apiKey,
    };
    final response = await http.post(url, headers: headers, body: payload);
    if (response.statusCode != 200) {
      debugPrint('Failed to stop streaming: ${response.body}');
    }
  }

  // Future<void> _sendTextToSocket(String textMessage) async {
  //   if (!isSocketReady) return;
  //   _channel!.sink.add(
  //     jsonEncode({"type": "user_message", "text": textMessage}),
  //   );
  //   setState(() {
  //     _messages.add({'sender': 'user', 'text': textMessage});
  //   });
  //   _scrollToBottom();
  //   _sendMessageController.clear();
  // }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _disconnectWebSocket() async {
    if (_recorder.isRecording) await _stopRecording();
    await _channel?.sink.close();
    if (_sessionId != null && apiToken.isNotEmpty) {
      await stopStreaming(_sessionId!, apiToken);
    }
    await _room?.disconnect();
    setState(() {
      isSocketReady = false;
      _sessionId = null;
    });
  }

  Future<Map<String, dynamic>> _createHeyGenSession() async {
    final response = await http.post(
      Uri.parse('https://api.heygen.com/v1/streaming.new'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiToken',
        'x-api-key': apiToken,
      },
      body: jsonEncode({
        'version': 'v2',
        'avatar_id': heyGenAvatarID,
        'quality': 'high',
      }),
    );
    final json = jsonDecode(response.body);
    if (response.statusCode == 200 && json['data'] != null) {
      return json['data'];
    } else {
      throw Exception('Session creation failed: ${response.body}');
    }
  }

  Future<void> _startHeyGenSession() async {
    final response = await http.post(
      Uri.parse('https://api.heygen.com/v1/streaming.start'),
      headers: {'Content-Type': 'application/json', 'x-api-key': apiToken},
      body: jsonEncode({'session_id': _sessionId}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to start session: ${response.body}');
    }
  }

  Future<void> _sendAvatar(String text) async {
    // 1) Immediately pause/stop the mic and disable the mic button:
    if (_recorder.isRecording) {
      setState(() => _micEnabled = false);
      await _stopRecording();
    }

    // 2) Send the text to HeyGen:
    final response = await http.post(
      Uri.parse('https://api.heygen.com/v1/streaming.task'),
      headers: {'Content-Type': 'application/json', 'x-api-key': apiToken},
      body: jsonEncode({'session_id': _sessionId, 'text': text}),
    );

    // 3) Show the avatar bubble immediately:
    setState(() {
      _messages.add({'sender': 'avatar', 'text': text.trim()});
    });
    _scrollToBottom();

    if (response.statusCode != 200) {
      throw Exception('Failed to send text to HeyGen: ${response.body}');
    }

    // // 4) Estimate how long the avatar will speak:
    // final wordCount = text.trim().split(RegExp(r'\s+')).length;
    // // Assume ~2.5 words per second
    // final double seconds = wordCount / 2.5;
    // final int delayMs = (seconds * 1000).toInt();

    final jsonResp = jsonDecode(response.body);
    final dynamic dur = jsonResp['duration_ms'];
    int durationMs = 0;
    if (dur is int) {
      durationMs = dur;
    } else if (dur is double) {
      durationMs = dur.toInt();
    }

    // 5) After that delay, restart recording:
    Future.delayed(Duration(milliseconds: durationMs), () async {
      if (mounted && !_recorder.isRecording && _isSessionActive) {
        await _startRecording();
        setState(() => _micEnabled = true);
      }
    });
  }

  // Future<void> _sendAvatar(String text) async {
  //   if (_recorder.isRecording) {
  //     setState(() {
  //       _micEnabled = false;
  //     });
  //     await _stopRecording();
  //   }

  //   final response = await http.post(
  //     Uri.parse('https://api.heygen.com/v1/streaming.task'),
  //     headers: {'Content-Type': 'application/json', 'x-api-key': apiToken},
  //     body: jsonEncode({'session_id': _sessionId, 'text': text}),
  //   );
  //   setState(() {
  //     _messages.add({'sender': 'avatar', 'text': text.trim()});
  //   });
  //   _scrollToBottom();
  //   if (response.statusCode != 200) {
  //     throw Exception('Failed to send text to HeyGen: ${response.body}');
  //   }
  //   // await Future.delayed(const Duration(seconds: 2));
  //   // if (mounted && !_recorder.isRecording) {
  //   //   await _startRecording();
  //   // }
  // }

  Widget _buildVideoWidget() {
    if (_videoTrack == null) {
      return const Center(
        child: Text(
          'Avatar loading...',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: VideoTrackRenderer(
          _videoTrack!,
          fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.onPlayerComplete.drain();
    _scrollController.dispose();
    _cleanupResources();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        centerTitle:
            true, // 👈 Ensure the title is centered on both Android & iOS
        title: Image.asset(
          AppAssets.appbarlogo, // Replace with your image path
          height: 50,
          width: 200, // Adjust size as needed
        ),
      ),
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              // HeyGen Avatar Section
              Expanded(flex: 3, child: Center(child: _buildVideoWidget())),
              if (_isLoading)
                Container(
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Colors.black),
                    ),
                  ),
                ),
              // Chat messages
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg['sender'] == 'user';

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: isUser
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (!isUser)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 8.0,
                                top: 4,
                              ),
                              child: CircleAvatar(
                                radius: 15,
                                child: ClipOval(
                                  child: Image(
                                    image: AssetImage(AppAssets.dre),
                                  ),
                                ),
                              ),
                            ),
                          Flexible(
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 16,
                              ),
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? Colors.grey[300]
                                    : Colors.grey[850],
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isUser ? 16 : 0),
                                  bottomRight: Radius.circular(isUser ? 0 : 16),
                                ),
                              ),
                              child: Text(
                                msg['text'] ?? '',
                                style: TextStyle(
                                  color: isUser ? Colors.black87 : Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // Input row
              Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _sendMessageController,
                        enabled: false,
                        decoration: InputDecoration(
                          fillColor: AppColors.background,
                          hintText: 'Say or type a clinical command...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onSubmitted: (_) => _sendTextToSocket(
                          _sendMessageController.text.trim(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _micEnabled ? Icons.mic : Icons.mic_off,
                        color: Colors.black,
                        size: 35,
                      ),
                      onPressed: _toggleRecording,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      iconSize: 35,
                      icon: Icon(Icons.call_end, color: Colors.red, size: 35),
                      onPressed: _cleanupResources,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sendTextToSocket(String textMessage) async {
    if (!isSocketReady) return;
    _channel!.sink.add(
      jsonEncode({"type": "user_message", "text": textMessage}),
    );
    setState(() {
      _messages.add({'sender': 'user', 'text': textMessage});
    });
    _scrollToBottom();
    _sendMessageController.clear();
  }
}

// import 'dart:async';
// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:flutter_application_1/constants/colors.dart';
// import 'package:flutter_application_1/constants/images.dart';
// import 'package:flutter_application_1/home_screen.dart';
// import 'package:flutter_application_1/widgets/widgets.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:http/http.dart' as http;
// import 'package:livekit_client/livekit_client.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:speech_to_text/speech_to_text.dart' as stt;
// import 'package:speech_to_text/speech_recognition_result.dart' as str;
// import 'package:web_socket_channel/web_socket_channel.dart';
// import 'package:audioplayers/audioplayers.dart' as ap;
// import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

// class HeyGenHomePage extends StatefulWidget {
//   const HeyGenHomePage({super.key});

//   @override
//   State<HeyGenHomePage> createState() => _HeyGenHomePageState();
// }

// class _HeyGenHomePageState extends State<HeyGenHomePage> {
//   final _scrollController = ScrollController();
//   final List<Map<String, String>> _messages = [];
//   final TextEditingController _sendMessageController = TextEditingController();
//   final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();

//   WebSocketChannel? _channel;
//   Room? _room;
//   RemoteVideoTrack? _videoTrack;

//   String? _sessionId;
//   bool _isListening = true; // Single boolean: true = mic is on (listening)
//   bool _isBusy = false;
//   bool _isSessionActive = false;
//   bool _isLoading = false;
//   bool isSocketReady = false;

//   // API keys & IDs from .env
//   final String apiToken = dotenv.env['HEYGEN_API_KEY'] ?? '';
//   final String elevenLabsApiKey = dotenv.env['ELEVENLABS_API_KEY'] ?? '';
//   final String elevenLabsVoiceId = dotenv.env['ELEVENLABS_VOICE_ID'] ?? '';
//   final String agentId = dotenv.env['ELEVENLABS_AGENT_ID'] ?? '';
//   final String heyGenAvatarID =
//       dotenv.env['HEYGEN_AVATAR'] ?? 'EXAVITQu4vr4xnSDxMaL';

//   // SpeechToText instance & flags
//   late stt.SpeechToText _speech;
//   bool _speechEnabled = false;

//   @override
//   void initState() {
//     super.initState();

//     // Initialize speech-to-text
//     _speech = stt.SpeechToText();
//     _initSpeech();

//     // Don’t automatically stop listening on playback
//     _audioPlayer.onPlayerComplete.drain();

//     _initializeSession();
//   }

//   Future<void> _initSpeech() async {
//     _speechEnabled = await _speech.initialize(
//       onStatus: (_) {
//         setState(() {
//           _isListening = true;
//         });
//       },
//       onError: (_) {
//         setState(() {
//           _isListening = false;
//         });
//       },
//     );

//     print('check $_speechEnabled');

//     if (!_speechEnabled && mounted) {
//       // If initialization fails, disable listening entirely
//       setState(() {
//         _isListening = false;
//       });
//     }
//   }

//   Future<void> _initializeSession() async {
//     await _startSession();
//     await _connectWebSocket();

//     // Start listening immediately if possible
//     if (_speechEnabled && !_isListening && _isSessionActive) {
//       await _startRecording();
//     }
//   }

//   Future<void> _withBusy(Future<void> Function() task) async {
//     if (_isBusy) return;
//     setState(() => _isBusy = true);
//     try {
//       await task();
//     } finally {
//       if (mounted) setState(() => _isBusy = false);
//     }
//   }

//   Future<void> _startSession() async => _withBusy(() async {
//     setState(() => _isLoading = true);

//     final sessionData = await _createHeyGenSession();
//     _sessionId = sessionData['session_id'];
//     final liveKitUrl = sessionData['url'];
//     final liveKitToken = sessionData['access_token'];

//     await _startHeyGenSession();

//     _room = await _connectToLiveKit(liveKitUrl, liveKitToken);
//     _room!.events.listen((event) {
//       if (event is TrackSubscribedEvent) {
//         final track = event.track;
//         if (track is RemoteVideoTrack && mounted) {
//           setState(() {
//             _videoTrack = track;
//           });
//         }
//         // Do not change mic here; mic state is controlled only by toggle
//       } else if (event is RoomDisconnectedEvent && mounted) {
//         // Handle unexpected disconnect if needed
//       }
//     });

//     setState(() {
//       _isSessionActive = true;
//       _isLoading = false;
//     });
//   });

//   Future<void> _endSession() async => _withBusy(() async {
//     if (_sessionId != null && _room != null) {
//       await _stopHeyGenStreaming();
//       setState(() {
//         _sessionId = null;
//         _room = null;
//         _videoTrack = null;
//         _messages.clear();
//         _isSessionActive = false;
//       });
//     }
//   });

//   Future<void> _stopHeyGenStreaming() async {
//     if (_sessionId == null) return;
//     final response = await http.post(
//       Uri.parse('https://api.heygen.com/v1/streaming.stop'),
//       headers: {
//         'Content-Type': 'application/json',
//         'Authorization': 'Bearer $apiToken',
//       },
//       body: jsonEncode({'session_id': _sessionId}),
//     );
//     if (response.statusCode != 200) {
//       throw Exception('Failed to stop session: ${response.body}');
//     }
//     await _room!.disconnect();
//   }

//   Future<Room> _connectToLiveKit(String url, String token) async {
//     final room = Room();
//     await room.connect(url, token);
//     return room;
//   }

//   Future<void> _connectWebSocket() async {
//     if (_channel != null) return;
//     try {
//       _channel = WebSocketChannel.connect(
//         Uri.parse(
//           "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=$agentId",
//         ),
//       );
//       _channel!.sink.add(jsonEncode({'agent_id': agentId}));

//       _channel!.stream.listen(
//         _handleWebSocketData,
//         onError: (e) {
//           debugPrint('WebSocket error: $e');
//           _showSessionEndDialog("Session ended unexpectedly");
//         },
//         onDone: () {
//           debugPrint('WebSocket closed');
//           _showSessionEndDialog("Session ended unexpectedly");
//         },
//       );
//     } catch (_) {
//       // ignore silently
//     }
//   }

//   void _handleWebSocketData(dynamic data) async {
//     try {
//       final response = jsonDecode(data);
//       if (response['type'] == 'ping') return;
//       if (response['event'] == 'ready') {
//         setState(() => isSocketReady = true);
//         return;
//       }

//       if (response['type'] == 'user_transcript' &&
//           response['user_transcription_event']?['user_transcript'] != null) {
//         final userTranscript =
//             response['user_transcription_event']['user_transcript'];
//         if (userTranscript.trim().isNotEmpty) {
//           setState(() {
//             _messages.add({'sender': 'user', 'text': userTranscript.trim()});
//           });
//           _scrollToBottom();
//         }
//         return;
//       }

//       final aiText =
//           response['agent_response_event']?['agent_response'] ??
//           response['agent_response'] ??
//           response['text'];
//       if (aiText?.trim().isNotEmpty == true) {
//         // Do not alter mic here; mic remains in whatever state toggle set
//         _sendAvatar(aiText.trim());
//         _scrollToBottom();
//       }
//     } catch (_) {
//       // ignore parse errors
//     }
//   }

//   /// Start continuous listening until manually muted.
//   Future<void> _startRecording() async {
//     if (!_speechEnabled || !_isListening) return;
//     await Permission.microphone.request();

//     print("status: $_isListening");

//     setState(() {
//       _isListening = true; // mic icon shows “on”
//     });

//     _speech.listen(
//       onResult: (str.SpeechRecognitionResult result) async {
//         if (result.finalResult) {
//           final recognizedText = result.recognizedWords.trim();
//           if (recognizedText.isNotEmpty && _channel != null) {
//             // Show user text in UI
//             setState(() {
//               _messages.add({'sender': 'user', 'text': recognizedText});
//             });
//             _scrollToBottom();

//             // Send over WebSocket
//             _channel!.sink.add(
//               jsonEncode({"type": "user_message", "text": recognizedText}),
//             );
//           }
//           // Restart listening if mic still on
//           // if (_isListening) {
//           //   await Future.delayed(const Duration(milliseconds: 100));
//           //   // _listenContinuously();
//           // }
//         }
//       },
//       listenFor: const Duration(minutes: 5),
//       localeId: 'en_US',
//       partialResults: false,
//       cancelOnError: true,
//       listenMode: stt.ListenMode.dictation,
//     );
//   }

//   /// Helper to re-listen each time a final_result arrives, as long as mic is on.
//   // void _listenContinuously() {
//   //   if (!_isListening) return; // If toggled off, stop

//   //   _speech.listen(
//   //     onResult: (str.SpeechRecognitionResult result) async {
//   //       if (result.finalResult) {
//   //         final recognizedText = result.recognizedWords.trim();
//   //         if (recognizedText.isNotEmpty && _channel != null) {
//   //           // Show user text in UI
//   //           setState(() {
//   //             _messages.add({'sender': 'user', 'text': recognizedText});
//   //           });
//   //           _scrollToBottom();

//   //           // Send over WebSocket
//   //           _channel!.sink.add(
//   //             jsonEncode({"type": "user_message", "text": recognizedText}),
//   //           );
//   //         }
//   //         // Restart listening if mic still on
//   //         if (_isListening) {
//   //           await Future.delayed(const Duration(milliseconds: 100));
//   //           _listenContinuously();
//   //         }
//   //       }
//   //     },
//   //     listenFor: const Duration(minutes: 5),
//   //     localeId: 'en_US',
//   //     partialResults: false,
//   //     cancelOnError: true,
//   //     listenMode: stt.ListenMode.dictation,
//   //   );
//   // }

//   /// Manually stop listening: user has muted the mic.
//   Future<void> _stopRecording() async {
//     if (!_isListening) return;
//     _isListening = false; // immediately mark mic off
//     await _speech.stop();
//     if (mounted) setState(() {}); // refresh icon
//   }

//   /// Sends text → HeyGen and updates UI. Does not change mic state.
//   Future<void> _sendAvatar(String text) async {
//     final response = await http.post(
//       Uri.parse('https://api.heygen.com/v1/streaming.task'),
//       headers: {'Content-Type': 'application/json', 'x-api-key': apiToken},
//       body: jsonEncode({'session_id': _sessionId, 'text': text}),
//     );

//     setState(() {
//       _messages.add({'sender': 'avatar', 'text': text.trim()});
//     });
//     _scrollToBottom();

//     if (response.statusCode != 200) {
//       throw Exception('Failed to send text to HeyGen: ${response.body}');
//     }
//     // Mic remains whatever state it was (on/off) based on toggle.
//   }

//   /// Toggle between listening on (unmuted) and off (muted).
//   Future<void> _toggleRecording() async {
//     if (!_isListening) {
//       await _stopRecording();
//     } else {
//       await _startRecording();
//     }
//   }

//   Future<void> _disconnectWebSocket() async {
//     if (_isListening) {
//       await _stopRecording();
//     }
//     await _channel?.sink.close();
//     if (_sessionId != null && apiToken.isNotEmpty) {
//       await stopStreaming(_sessionId!, apiToken);
//     }
//     await _room?.disconnect();
//     setState(() {
//       isSocketReady = false;
//       _sessionId = null;
//     });
//   }

//   Future<void> stopStreaming(String sessionId, String apiKey) async {
//     final url = Uri.parse("https://api.heygen.com/v1/streaming.stop");
//     final payload = jsonEncode({"session_id": sessionId});
//     final headers = {
//       "accept": "application/json",
//       "content-type": "application/json",
//       "x-api-key": apiKey,
//     };
//     final response = await http.post(url, headers: headers, body: payload);
//     if (response.statusCode != 200) {
//       debugPrint('Failed to stop streaming: ${response.body}');
//     }
//   }

//   Future<Map<String, dynamic>> _createHeyGenSession() async {
//     final response = await http.post(
//       Uri.parse('https://api.heygen.com/v1/streaming.new'),
//       headers: {
//         'Content-Type': 'application/json',
//         'Authorization': 'Bearer $apiToken',
//         'x-api-key': apiToken,
//       },
//       body: jsonEncode({
//         'version': 'v2',
//         'avatar_id': heyGenAvatarID,
//         'quality': 'high',
//       }),
//     );
//     final jsonBody = jsonDecode(response.body);
//     if (response.statusCode == 200 && jsonBody['data'] != null) {
//       return jsonBody['data'];
//     } else {
//       throw Exception('Session creation failed: ${response.body}');
//     }
//   }

//   Future<void> _startHeyGenSession() async {
//     final response = await http.post(
//       Uri.parse('https://api.heygen.com/v1/streaming.start'),
//       headers: {'Content-Type': 'application/json', 'x-api-key': apiToken},
//       body: jsonEncode({'session_id': _sessionId}),
//     );
//     if (response.statusCode != 200) {
//       throw Exception('Failed to start session: ${response.body}');
//     }
//   }

//   Widget _buildVideoWidget() {
//     if (_videoTrack == null) {
//       return const Center(
//         child: Text(
//           'Avatar loading...',
//           style: TextStyle(color: Colors.white70),
//         ),
//       );
//     }
//     return Container(
//       margin: const EdgeInsets.symmetric(horizontal: 15),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(15),
//         child: VideoTrackRenderer(
//           _videoTrack!,
//           fit: rtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
//         ),
//       ),
//     );
//   }

//   @override
//   void dispose() {
//     _scrollController.dispose();
//     _cleanupResources();
//     super.dispose();
//   }

//   Future<void> _cleanupResources() async {
//     if (_isListening) {
//       await _speech.stop();
//     }
//     await _channel?.sink.close();
//     if (_sessionId != null && apiToken.isNotEmpty) {
//       await _disconnectWebSocket();
//       await _endSession();
//       await _stopHeyGenStreaming();
//     }
//     await _room?.disconnect();
//     _audioPlayer.stop();
//     if (mounted) {
//       setState(() {
//         isSocketReady = false;
//         _sessionId = null;
//       });
//     }
//   }

//   void _scrollToBottom() {
//     if (!_scrollController.hasClients) return;
//     _scrollController.animateTo(
//       _scrollController.position.maxScrollExtent,
//       duration: const Duration(milliseconds: 300),
//       curve: Curves.easeOut,
//     );
//   }

//   Future<void> _sendTextToSocket(String textMessage) async {
//     if (!isSocketReady) return;
//     _channel!.sink.add(
//       jsonEncode({"type": "user_message", "text": textMessage}),
//     );
//     setState(() {
//       _messages.add({'sender': 'user', 'text': textMessage});
//     });
//     _scrollToBottom();
//     _sendMessageController.clear();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         backgroundColor: AppColors.background,
//         surfaceTintColor: AppColors.background,
//         centerTitle: true,
//         title: Image.asset(AppAssets.appbarlogo, height: 50, width: 200),
//       ),
//       backgroundColor: AppColors.background,
//       body: Stack(
//         children: [
//           Column(
//             children: [
//               // HeyGen Avatar Section
//               Expanded(flex: 3, child: Center(child: _buildVideoWidget())),
//               if (_isLoading)
//                 Container(
//                   child: const Center(
//                     child: CircularProgressIndicator(
//                       valueColor: AlwaysStoppedAnimation(Colors.black),
//                     ),
//                   ),
//                 ),
//               // Chat messages
//               Expanded(
//                 flex: 3,
//                 child: Padding(
//                   padding: const EdgeInsets.all(15),
//                   child: ListView.builder(
//                     controller: _scrollController,
//                     itemCount: _messages.length,
//                     itemBuilder: (context, index) {
//                       final msg = _messages[index];
//                       final isUser = msg['sender'] == 'user';

//                       return Row(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         mainAxisAlignment: isUser
//                             ? MainAxisAlignment.end
//                             : MainAxisAlignment.start,
//                         children: [
//                           if (!isUser)
//                             Padding(
//                               padding: const EdgeInsets.only(
//                                 right: 8.0,
//                                 top: 4,
//                               ),
//                               child: CircleAvatar(
//                                 radius: 15,
//                                 child: ClipOval(
//                                   child: Image(
//                                     image: AssetImage(AppAssets.dre),
//                                   ),
//                                 ),
//                               ),
//                             ),
//                           Flexible(
//                             child: Container(
//                               constraints: BoxConstraints(
//                                 maxWidth:
//                                     MediaQuery.of(context).size.width * 0.75,
//                               ),
//                               padding: const EdgeInsets.symmetric(
//                                 vertical: 10,
//                                 horizontal: 16,
//                               ),
//                               margin: const EdgeInsets.symmetric(vertical: 6),
//                               decoration: BoxDecoration(
//                                 color: isUser
//                                     ? Colors.grey[300]
//                                     : Colors.grey[850],
//                                 borderRadius: BorderRadius.only(
//                                   topLeft: const Radius.circular(16),
//                                   topRight: const Radius.circular(16),
//                                   bottomLeft: Radius.circular(isUser ? 16 : 0),
//                                   bottomRight: Radius.circular(isUser ? 0 : 16),
//                                 ),
//                               ),
//                               child: Text(
//                                 msg['text'] ?? '',
//                                 style: TextStyle(
//                                   color: isUser ? Colors.black87 : Colors.white,
//                                   fontSize: 16,
//                                 ),
//                               ),
//                             ),
//                           ),
//                         ],
//                       );
//                     },
//                   ),
//                 ),
//               ),
//               // Input row
//               Padding(
//                 padding: const EdgeInsets.all(15),
//                 child: Row(
//                   children: [
//                     Expanded(
//                       child: TextField(
//                         controller: _sendMessageController,
//                         enabled: false,
//                         decoration: InputDecoration(
//                           fillColor: AppColors.background,
//                           hintText: 'Say or type a clinical command...',
//                           border: OutlineInputBorder(
//                             borderRadius: BorderRadius.circular(15),
//                           ),
//                         ),
//                         onSubmitted: (_) => _sendTextToSocket(
//                           _sendMessageController.text.trim(),
//                         ),
//                       ),
//                     ),
//                     IconButton(
//                       icon: Icon(
//                         _isListening ? Icons.mic : Icons.mic_off,
//                         color: Colors.black,
//                         size: 35,
//                       ),
//                       onPressed: _toggleRecording, // Mute/unmute
//                     ),
//                     const SizedBox(width: 8),
//                     IconButton(
//                       iconSize: 35,
//                       icon: Icon(Icons.call_end, color: Colors.red, size: 35),
//                       onPressed: _cleanupResources,
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Future<void> _showSessionEndDialog(String message) async {
//     if (!mounted) return;
//     await showDialog(
//       context: context,
//       barrierDismissible: false,
//       barrierColor: Colors.black.withOpacity(0.5),
//       builder: (ctx) => Dialog(
//         backgroundColor: Colors.transparent,
//         child: ClipRRect(
//           borderRadius: BorderRadius.circular(12),
//           child: Container(
//             decoration: BoxDecoration(
//               color: AppColors.background,
//               borderRadius: BorderRadius.circular(12),
//             ),
//             padding: const EdgeInsets.all(20),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Text(
//                   message,
//                   style: const TextStyle(
//                     color: Colors.black,
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 const SizedBox(height: 20),
//                 CommonWidgets.customButton(
//                   onPressed: () {
//                     _cleanupResources();
//                     Navigator.pushAndRemoveUntil(
//                       context,
//                       MaterialPageRoute(
//                         builder: (context) => const HomeScreen(),
//                       ),
//                       (route) => false,
//                     );
//                   },
//                   label: 'Ok',
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }
