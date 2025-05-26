import 'package:flutter/material.dart';
import 'package:flutter_application_1/constants/colors.dart';
import 'package:flutter_application_1/constants/images.dart';
import 'package:flutter_application_1/widgets/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

class HeyGenHomePage extends StatefulWidget {
  const HeyGenHomePage({super.key});

  @override
  State<HeyGenHomePage> createState() => _HeyGenHomePageState();
}

class _HeyGenHomePageState extends State<HeyGenHomePage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = stt.SpeechToText();

  double _padding = 10;

  Room? _room;
  String? _sessionId;
  RemoteVideoTrack? _videoTrack;
  bool _isListening = false;
  bool _isSessionActive = false;
  bool _isBusy = false;
  bool _isLoading = false;

  final List<Map<String, String>> _messages = [];

  final apiToken = dotenv.env['HEYGEN_API_KEY'].toString();
  final openAiApiKey = dotenv.env['OPENAI_API_KEY'].toString();
  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _room?.disconnect();
    _speech.stop();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _withBusy(Future<void> Function() task) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await task();
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<String> _getAIResponse(String userInput) async {
    final url = Uri.parse('https://api.openai.com/v1/chat/completions');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $openAiApiKey',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'system',
            'content': 'You are a helpful AI assistant for a dentist.',
          },
          {'role': 'user', 'content': userInput},
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'];
    } else {
      throw Exception('OpenAI error: ${response.body}');
    }
  }

  Future<void> _startSession() async => _withBusy(() async {
    setState(() => _isLoading = true);
    final session = await _createHeyGenSession();
    _sessionId = session['session_id'];
    final liveKitUrl = session['url'];
    final liveKitToken = session['access_token'];

    await _startHeyGenSession();
    _room = await _connectToLiveKitRoom(liveKitUrl, liveKitToken);

    _room!.events.listen((event) {
      if (event is TrackSubscribedEvent) {
        final track = event.track;
        if (track is RemoteVideoTrack && mounted) {
          setState(() => _videoTrack = track);
        }
      }
    });

    setState(() {
      _isSessionActive = true;
      _isLoading = false;
    });
  });

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (_sessionId != null && text.isNotEmpty) {
      await _withBusy(() async {
        setState(() {
          _messages.add({'sender': 'user', 'text': text});
          _textController.clear();
          _messages.add({'sender': 'typing', 'text': ''});
        });

        final aiReply = await _getAIResponse(text);
        await _sendTextToAvatar(aiReply);

        setState(() {
          _messages.removeWhere((msg) => msg['sender'] == 'typing');
          _messages.add({'sender': 'avatar', 'text': aiReply});
        });

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      });
    }
  }

  Future<void> _endSession() async => _withBusy(() async {
    if (_sessionId != null && _room != null) {
      await _closeHeyGenSession();
      setState(() {
        _sessionId = null;
        _room = null;
        _videoTrack = null;
        _messages.clear();
        _isSessionActive = false;
      });
    }
  });

  Future<void> _startListening() async {
    if (!_isSessionActive || _isBusy) return;
    try {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (result) async {
            if (result.finalResult && result.recognizedWords.isNotEmpty) {
              await _stopListening();
              await _handleVoiceInput(result.recognizedWords);
            }
          },
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 2),
        );
      } else {
        _showError("Speech recognition not available.");
      }
    } catch (e) {
      _showError("Speech error: $e");
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) setState(() => _isListening = false);
  }

  Future<void> _handleVoiceInput(String spokenText) async {
    if (_sessionId != null && spokenText.isNotEmpty) {
      await _withBusy(() async {
        setState(() {
          _messages.add({'sender': 'user', 'text': spokenText});
          _messages.add({'sender': 'typing', 'text': ''});
        });

        final aiReply = await _getAIResponse(spokenText);
        await _sendTextToAvatar(aiReply);

        setState(() {
          _messages.removeWhere((msg) => msg['sender'] == 'typing');
          _messages.add({'sender': 'avatar', 'text': aiReply});
        });

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      });
    }
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
        'quality': 'medium',
        'avatar_id': 'Katya_Chair_Sitting_public',
        'voice': {
          'voice_id': 'd1d0df0e12f64cfe9e93dff67a774c42',
          'emotion': 'Friendly',
        },
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

  Future<void> _sendTextToAvatar(String text) async {
    final response = await http.post(
      Uri.parse('https://api.heygen.com/v1/streaming.task'),
      headers: {'Content-Type': 'application/json', 'x-api-key': apiToken},
      body: jsonEncode({'session_id': _sessionId, 'text': text}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send text: ${response.body}');
    }
  }

  Future<void> _closeHeyGenSession() async {
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
    if (_room != null) {
      await _room!.disconnect();
    }
  }

  Future<Room> _connectToLiveKitRoom(String url, String token) async {
    final room = Room();
    await room.connect(url, token);
    return room;
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.whitebackground,
      appBar: AppBar(
        leading: CommonWidgets.backButton(
          color: AppColors.surface,
          image: AppAssets.iconBack,
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: AppColors.whitebackground,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _isLoading
                  ? const CircularProgressIndicator(
                      backgroundColor: AppColors.buttonColor,
                      color: AppColors.primaryColor,
                    )
                  : (_videoTrack != null
                        ? Container(
                            margin: EdgeInsets.only(
                              left: _padding,
                              right: _padding,
                            ),
                            padding: EdgeInsets.all(_padding),
                            child: ClipRRect(
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(40.0),
                                bottomLeft: Radius.circular(40.0),
                              ),
                              child: SizedBox(
                                child: VideoTrackRenderer(
                                  _videoTrack!,
                                  fit: rtc
                                      .RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                ),
                              ),
                            ),
                          )
                        : const Text(
                            'Start a session to see the avatar',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          )),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              padding: EdgeInsets.all(_padding),
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['sender'] == 'user';
                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blue : Colors.grey[200],
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
                        color: isUser ? Colors.white : Colors.black87,
                        fontSize: 16,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isSessionActive)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening ? Colors.red : Colors.black,
                    ),
                    onPressed: _isBusy
                        ? null
                        : (_isListening ? _stopListening : _startListening),
                  ),
                  Expanded(
                    child: CommonWidgets().commonTextField(
                      controller: _textController,
                      hintText: 'Say or type something...',
                      onSubmitted: (_) => _sendText(),
                      enabled: !_isBusy,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _isBusy ? null : _sendText,
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(_padding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CommonWidgets.customButton(
                  size: 18,
                  fontWeight: FontWeight.bold,
                  onPressed: _isSessionActive || _isBusy ? null : _startSession,
                  label: 'Start Session',
                ),
                CommonWidgets.customButton(
                  size: 18,
                  fontWeight: FontWeight.bold,
                  onPressed: _isSessionActive ? _endSession : null,
                  label: 'End Session',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
