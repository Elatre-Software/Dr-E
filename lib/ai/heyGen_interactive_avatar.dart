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
// import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audioplayers/audioplayers.dart' as ap;

class HeyGenHomePage extends StatefulWidget {
  const HeyGenHomePage({super.key});

  @override
  State<HeyGenHomePage> createState() => _HeyGenHomePageState();
}

class _HeyGenHomePageState extends State<HeyGenHomePage> {
  bool _isPlayingTTS = false;
  final _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];

  String? _sessionId;
  Room? _room;
  // RemoteVideoTrack? _videoTrack;
  // bool _isSessionActive = false;
  bool _micEnabled = true;
  bool isSocketReady = false;
  bool _isListening = false;

  WebSocketChannel? _channel;
  final _recorder = FlutterSoundRecorder();
  StreamController<Uint8List>? _audioStreamController;
  final TextEditingController _sendMessageController = TextEditingController();
  final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();

  final apiToken = dotenv.env['HEYGEN_API_KEY'] ?? '';
  final elevenLabsApiKey = dotenv.env['ELEVENLABS_API_KEY'] ?? '';
  final elevenLabsVoiceId = dotenv.env['ELEVENLABS_VOICE_ID'] ?? '';
  final heyGenVoiceID = dotenv.env['HEYGEN_VOICE_ID'] ?? 'EXAVITQu4vr4xnSDxMaL';
  final String agentId =
      dotenv.env['ELEVENLABS_AGENT_ID'] ?? 'EXAVITQu4vr4xnSDxMaL';

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerComplete.listen((_) async {
      // _isPlayingTTS = false;
      setState(() => _micEnabled = true);
      await _startRecording();
    });
    _initializeSession();
  }

  Future<void> _initializeSession() async {
    await _connectWebSocket();
    _greetUser();
  }

  Future<void> _connectWebSocket() async {
    try {
      final url = Uri.parse(
        'https://api.elevenlabs.io/v1/convai/conversation/get-signed-url?agent_id=$agentId',
      );
      final response = await http.get(
        url,
        headers: {'xi-api-key': elevenLabsApiKey},
      );
      final data = jsonDecode(response.body);

      final signedUrl = data['signed_url'];
      if (response.statusCode != 200 || signedUrl == null) {
        debugPrint('WebSocket URL error: ${response.body}');
        return;
      }

      _channel = WebSocketChannel.connect(Uri.parse(signedUrl));
      _channel!.sink.add(jsonEncode({'agent_id': agentId}));

      _channel!.stream.listen(
        _handleWebSocketData,
        onError: (e) => debugPrint('WebSocket error: $e'),
        onDone: () {
          debugPrint('WebSocket closed');
          _showSessionEndDialog();
        },
      );
    } catch (e) {
      debugPrint('WebSocket Exception: $e');
    }
  }

  void _handleWebSocketData(dynamic data) async {
    try {
      final response = jsonDecode(data);

      if (response['type'] == 'ping') return;
      if (response['event'] == 'ready') {
        setState(() {
          isSocketReady = true;
          // _isSessionActive = true;
        });
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
          print("dat$response");
        }
        return;
      }

      final aiText =
          response['agent_response_event']?['agent_response'] ??
          response['agent_response'] ??
          response['text'];

      if (aiText?.trim().isNotEmpty == true) {
        setState(() => _isListening = true);
        // small delay to simulate processing time
        // await Future.delayed(const Duration(milliseconds: 500));
        setState(() => _isListening = false);

        _scrollToBottom();
        _speakText(aiText.trim());
      }
    } catch (e) {
      debugPrint('Failed to parse WebSocket message: $e');
    }
  }

  Future<void> _speakText(String text) async {
    // If TTS is already playing, stop first
    // if (_isPlayingTTS) {
    //   await _audioPlayer.stop();
    // }
    final voiceId = elevenLabsVoiceId;
    final url = Uri.parse(
      "https://api.elevenlabs.io/v1/text-to-speech/$voiceId/stream",
    );
    try {
      // _isPlayingTTS = true;
      // Stop recording to prevent feedback
      if (_recorder.isRecording) {
        await _stopRecording();
      }
      setState(() => _micEnabled = false);

      final response = await http.post(
        url,
        headers: {
          "Accept": "audio/mpeg",
          "Content-Type": "application/json",
          "xi-api-key": elevenLabsApiKey,
        },
        body: jsonEncode({
          "text": text,
          "voice_settings": {
            "speaker_boost": true,
            "style": "0.40",
            "stability": 0.30,
            "similarity_boost": 1.00,
          },
        }),
      );
      if (response.statusCode == 200) {
        await _audioPlayer.play(ap.BytesSource(response.bodyBytes));
        setState(() {
          _messages.add({'sender': 'avatar', 'text': text.trim()});
        });
      } else {
        // _isPlayingTTS = false;
        setState(() => _micEnabled = true);
        await _startRecording();
      }
    } catch (e) {
      debugPrint('TTS error: $e');
      // _isPlayingTTS = false;
      setState(() => _micEnabled = true);
      await _startRecording();
    }
  }

  Future<void> _greetUser() async {
    if (_micEnabled) await _startRecording();
  }

  Future<void> _startRecording() async {
    // Prevent reinitializing stream controller
    if (_audioStreamController != null) return;

    await Permission.microphone.request();
    await _recorder.openRecorder();
    _audioStreamController = StreamController<Uint8List>();

    _audioStreamController!.stream.listen((buffer) {
      // if (buffer.isNotEmpty && !_isPlayingTTS) {
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
  }

  Future<void> _stopRecording() async {
    if (!_recorder.isRecording) return;
    await _recorder.stopRecorder();
    _audioStreamController?.close();
    _audioStreamController = null;
  }

  Future<void> _showSessionEndDialog() async {
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
                const Text(
                  "The session has ended.",
                  style: TextStyle(
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
    try {
      if (_recorder.isRecording) await _stopRecording();
      await _channel?.sink.close();
      if (_sessionId != null && apiToken.isNotEmpty) {
        await _disconnectWebSocket();
        await stopStreaming(_sessionId!, apiToken);
      }
      await _room?.disconnect();
      _scrollController.dispose();
      if (_audioStreamController != null) {
        _audioStreamController!.close();
        _audioStreamController = null;
      }
      setState(() {
        // _isSessionActive = false;
        // _videoTrack = null;
        isSocketReady = false;
        _sessionId = null;
      });
    } catch (e) {
      debugPrint('Error during cleanup: $e');
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_recorder.isRecording) {
        await _stopRecording();
      } else {
        await _startRecording();
      }
      setState(() => _micEnabled = !_micEnabled);
    } catch (e) {
      debugPrint('Error toggling recording: $e');
    }
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
      debugPrint(
        'Failed to stop streaming. Status code: ${response.statusCode}',
      );
      debugPrint('Response: ${response.body}');
    }
  }

  Widget elevenGif() {
    return Container(
      margin: const EdgeInsets.only(top: 25),
      child: SizedBox(
        width: 300,
        height: 300,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: Image.asset(
                AppAssets.elevenLabsGif,
                width: 300,
                height: 300,
                fit: BoxFit.fill,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Listening',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _micEnabled ? Icons.mic : Icons.mic_off,
                    color: Colors.black87,
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cleanupResources();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: AppColors.background,
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(margin: const EdgeInsets.only(top: 15), child: elevenGif()),
          if (_isListening)
            const Padding(
              padding: EdgeInsets.all(5),
              child: Text(
                "Listening...",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          Expanded(
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
                          padding: const EdgeInsets.only(right: 8.0, top: 4),
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black,
                            child: ClipOval(
                              child: Image.asset(
                                AppAssets.elevenLabsGif,
                                width: 24,
                                height: 24,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      Flexible(
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 16,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.grey[300] : Colors.grey[850],
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
          Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _sendMessageController,
                    // enabled: !_micEnabled || !_isPlayingTTS,
                    enabled: false,
                    decoration: InputDecoration(
                      fillColor: AppColors.background,
                      hintText: 'Say or type a clinical command...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onSubmitted: (_) =>
                        _sendTextToSocket(_sendMessageController.text.trim()),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _micEnabled ? Icons.mic : Icons.mic_off,
                    color: Colors.black,
                    size: 35,
                  ),
                  // onPressed: _isPlayingTTS
                  //     ? null
                  //     : () async => await _toggleRecording(),
                  onPressed: () async => await _toggleRecording(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.call, color: Colors.black, size: 35),
                  onPressed: () {
                    _cleanupResources();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendTextToSocket(String textMessage) async {
    if (!isSocketReady) {
      debugPrint('Cannot send: Socket not ready.');
      return;
    }
    _channel!.sink.add(
      jsonEncode({"type": "user_message", "text": textMessage}),
    );
    setState(() {
      _messages.add({'sender': 'user', 'text': textMessage});
    });
    _scrollToBottom();
    _sendMessageController.clear();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _disconnectWebSocket() async {
    try {
      if (_recorder.isRecording) await _stopRecording();
      await _channel?.sink.close();
      if (_sessionId != null && apiToken.isNotEmpty) {
        await stopStreaming(_sessionId!, apiToken);
      }
      await _room?.disconnect();
      setState(() {
        // _isSessionActive = false;
        // _videoTrack = null;
        isSocketReady = false;
        _sessionId = null;
      });
      debugPrint('Session ended and cleaned up.');
    } catch (e) {
      debugPrint('Error during disconnect: $e');
    }
  }
}
