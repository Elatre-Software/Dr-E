// import 'dart:async';
// import 'dart:convert';
// import 'dart:typed_data';

// import 'package:flutter/material.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:flutter_sound/flutter_sound.dart';
// import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
// import 'package:http/http.dart' as http;
// import 'package:livekit_client/livekit_client.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';

// import 'package:flutter_application_1/constants/images.dart';
// import 'package:flutter_application_1/widgets/widgets.dart';

// class HeyGenHomePage extends StatefulWidget {
//   const HeyGenHomePage({super.key});

//   @override
//   State<HeyGenHomePage> createState() => _HeyGenHomePageState();
// }

// class _HeyGenHomePageState extends State<HeyGenHomePage> {
//   final _scrollController = ScrollController();
//   final List<Map<String, String>> _messages = [];

//   String? _sessionId;
//   Room? _room;
//   RemoteVideoTrack? _videoTrack;
//   bool _isSessionActive = false;
//   bool _micEnabled = true;
//   bool isSocketReady = false;

//   WebSocketChannel? _channel;
//   final _recorder = FlutterSoundRecorder();
//   late StreamController<Uint8List> _audioStreamController;
//   final TextEditingController _sendMessageController = TextEditingController();

//   final apiToken = dotenv.env['HEYGEN_API_KEY'] ?? '';
//   final elevenLabsApiKey = dotenv.env['ELEVENLABS_API_KEY'] ?? '';
//   final heyGenVoiceID = dotenv.env['HEYGEN_VOICE_ID'] ?? 'EXAVITQu4vr4xnSDxMaL';
//   final String agentId =
//       dotenv.env['ELEVENLABS_AGENT_ID'] ?? 'EXAVITQu4vr4xnSDxMaL';

//   @override
//   void initState() {
//     super.initState();
//     _startSession().then((_) {
//       _connectWebSocket();
//       _greetUser();
//     });
//   }

//   Future<void> _connectWebSocket() async {
//     final url = Uri.parse(
//       'https://api.elevenlabs.io/v1/convai/conversation/get-signed-url?agent_id=$agentId',
//     );

//     try {
//       final response = await http.get(
//         url,
//         headers: {'xi-api-key': elevenLabsApiKey},
//       );
//       final data = jsonDecode(response.body);

//       final signedUrl = data['signed_url'];
//       if (response.statusCode != 200 || signedUrl == null) {
//         debugPrint('WebSocket URL error: ${response.body}');
//         return;
//       }

//       _channel = WebSocketChannel.connect(Uri.parse(signedUrl));
//       _channel!.sink.add(jsonEncode({'agent_id': agentId}));

//       _channel!.stream.listen(
//         _handleWebSocketData,
//         onError: (e) => debugPrint('WebSocket error: $e'),
//         onDone: () => debugPrint('WebSocket closed'),
//       );
//     } catch (e) {
//       debugPrint('WebSocket Exception: $e');
//     }
//   }

//   void _handleWebSocketData(dynamic data) {
//     debugPrint('Received from WebSocket: $data');
//     try {
//       final response = jsonDecode(data);

//       if (response['type'] == 'ping') return;
//       if (response['event'] == 'ready') {
//         setState(() => isSocketReady = true);
//         return;
//       }

//       final aiText =
//           response['agent_response_event']?['agent_response'] ??
//           response['agent_response'] ??
//           response['text'];

//       if (aiText?.trim().isNotEmpty == true) {
//         _handleAIResponse(aiText!.trim());
//       }
//     } catch (e) {
//       debugPrint('Failed to parse WebSocket message: $e');
//     }
//   }

//   Future<void> _greetUser() async {
//     if (_micEnabled) _startRecording();
//   }

//   Future<void> _startRecording() async {
//     await Permission.microphone.request();
//     await _recorder.openRecorder();
//     _audioStreamController = StreamController<Uint8List>();

//     _audioStreamController.stream.listen((buffer) {
//       if (buffer.isNotEmpty) {
//         final message = jsonEncode({"user_audio_chunk": base64Encode(buffer)});
//         _channel?.sink.add(message);
//       }
//     });

//     await _recorder.startRecorder(
//       codec: Codec.pcm16,
//       sampleRate: 16000,
//       numChannels: 1,
//       toStream: _audioStreamController.sink,
//     );
//   }

//   Future<void> _sendTextToSocket(String textMessage) async {
//     if (_isSessionActive && isSocketReady) {
//       final message = jsonEncode({"user_message": textMessage});
//       _channel?.sink.add(message);
//     } else {
//       debugPrint('❌ Cannot send: Session inactive or socket not ready.');
//     }
//   }

//   Future<void> _stopRecording() async {
//     await _recorder.stopRecorder();
//     _channel?.sink.add(
//       jsonEncode({"type": "user_audio_chunk", "audio": null, "is_final": true}),
//     );
//   }

//   void _handleAIResponse(String aiReply) async {
//     setState(() => _messages.add({'sender': 'avatar', 'text': aiReply}));
//     try {
//       await _sendTextToAvatar(aiReply);
//     } catch (e) {
//       debugPrint('Error sending to HeyGen: $e');
//     }
//     _scrollToBottom();
//   }

//   Future<void> _startSession() async {
//     try {
//       final session = await _createHeyGenSession();
//       _sessionId = session['session_id'];
//       final liveKitUrl = session['url'];
//       final liveKitToken = session['access_token'];

//       await _startHeyGenSession();
//       _room = await _connectToLiveKitRoom(liveKitUrl, liveKitToken);

//       _room!.events.listen((event) {
//         if (event is TrackSubscribedEvent) {
//           final track = event.track;
//           if (track is RemoteVideoTrack && mounted) {
//             setState(() => _videoTrack = track);
//           }
//         }
//       });

//       setState(() => _isSessionActive = true);
//     } catch (e) {
//       debugPrint('Failed to start session: $e');
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
//         'quality': 'medium',
//         'avatar_id': '2382f04c12af45cba82b53d1a60f9091',
//         'voice': {'voice_id': heyGenVoiceID},
//       }),
//     );
//     final json = jsonDecode(response.body);
//     if (response.statusCode == 200 && json['data'] != null) {
//       return json['data'];
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

//   Future<Room> _connectToLiveKitRoom(String url, String token) async {
//     final room = Room();
//     await room.connect(url, token);
//     return room;
//   }

//   Future<void> _sendTextToAvatar(String text) async {
//     if (_sessionId == null) return;
//     try {
//       final response = await http.post(
//         Uri.parse('https://api.heygen.com/v1/streaming.task'),
//         headers: {'Content-Type': 'application/json', 'x-api-key': apiToken},
//         body: jsonEncode({'session_id': _sessionId, 'text': text}),
//       );
//       if (response.statusCode != 200) {
//         debugPrint('Failed to send text to avatar: ${response.body}');
//       }
//     } catch (e) {
//       debugPrint('Exception sending text to avatar: $e');
//     }
//   }

//   void _scrollToBottom() {
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (_scrollController.hasClients) {
//         _scrollController.animateTo(
//           _scrollController.position.maxScrollExtent,
//           duration: const Duration(milliseconds: 300),
//           curve: Curves.easeOut,
//         );
//       }
//     });
//   }

//   Widget _buildVideoWidget() {
//     if (!_isSessionActive) {
//       return const Center(child: CircularProgressIndicator());
//     }
//     if (_videoTrack == null) {
//       return const SizedBox();
//     }
//     return Container(
//       margin: const EdgeInsets.all(15),
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
//   Widget build(BuildContext context) {
//     return SafeArea(
//       child: Scaffold(
//         body: Column(
//           children: [
//             Expanded(child: Center(child: _buildVideoWidget())),
//             Expanded(
//               child: Padding(
//                 padding: const EdgeInsets.all(15),
//                 child: ListView.builder(
//                   controller: _scrollController,
//                   itemCount: _messages.length,
//                   itemBuilder: (context, index) {
//                     final msg = _messages[index];
//                     final isUser = msg['sender'] == 'user';
//                     return Align(
//                       alignment: isUser
//                           ? Alignment.centerRight
//                           : Alignment.centerLeft,
//                       child: Container(
//                         padding: const EdgeInsets.symmetric(
//                           vertical: 10,
//                           horizontal: 16,
//                         ),
//                         margin: const EdgeInsets.symmetric(vertical: 4),
//                         decoration: BoxDecoration(
//                           color: isUser ? Colors.blue : Colors.grey[200],
//                           borderRadius: BorderRadius.only(
//                             topLeft: const Radius.circular(16),
//                             topRight: const Radius.circular(16),
//                             bottomLeft: Radius.circular(isUser ? 16 : 0),
//                             bottomRight: Radius.circular(isUser ? 0 : 16),
//                           ),
//                         ),
//                         child: Text(
//                           msg['text'] ?? '',
//                           style: TextStyle(
//                             color: isUser ? Colors.white : Colors.black87,
//                             fontSize: 16,
//                           ),
//                         ),
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             ),
//             Container(
//               margin: const EdgeInsets.only(left: 15, right: 15),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   CommonWidgets.customButton(
//                     assetIconPath: AppAssets.uploadIcon,
//                     onPressed: () {},
//                     label: 'Upload',
//                   ),
//                   CommonWidgets.AppRoundedIconButton(
//                     onPressed: () {},
//                     label: 'Start New Diagnosis',
//                     assetPath: AppAssets.searchIcon,
//                   ),
//                 ],
//               ),
//             ),
//             Padding(
//               padding: const EdgeInsets.all(15),
//               child: Row(
//                 children: [
//                   Expanded(
//                     child: TextField(
//                       controller: _sendMessageController,
//                       enabled: !_micEnabled,
//                       decoration: InputDecoration(
//                         hintText: 'Say or type a clinical command...',
//                         border: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(15),
//                         ),
//                       ),
//                       onSubmitted: (_) =>
//                           _sendTextToSocket(_sendMessageController.text),
//                     ),
//                   ),
//                   IconButton(
//                     icon: Icon(
//                       _micEnabled ? Icons.mic : Icons.mic_off,
//                       color: Colors.blue,
//                     ),
//                     onPressed: () async => await _toggleRecording(),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Future<void> _toggleRecording() async {
//     try {
//       if (_recorder.isRecording) {
//         await _stopRecording();
//       } else {
//         await _startRecording();
//       }
//       if (mounted) setState(() => _micEnabled = !_micEnabled);
//     } catch (e) {
//       debugPrint('Error toggling recording: $e');
//     }
//   }

//   @override
//   void dispose() {
//     _recorder.closeRecorder();
//     _audioStreamController.close();
//     _channel?.sink.close();
//     super.dispose();
//   }
// }

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/constants/colors.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class HeyGenHomePage extends StatefulWidget {
  const HeyGenHomePage({super.key});

  @override
  State<HeyGenHomePage> createState() => _HeyGenHomePageState();
}

class _HeyGenHomePageState extends State<HeyGenHomePage> {
  final _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];

  String? _sessionId;
  Room? _room;
  RemoteVideoTrack? _videoTrack;
  bool _isSessionActive = false;
  bool _micEnabled = true;
  bool isSocketReady = false;
  bool _isListening = false;

  ///Pre Text Content
  String preTextholisticPlan = 'Dr E,thoughts about holistic';
  String preTextDental = 'Dr E, about Dental health and hygiene';

  WebSocketChannel? _channel;
  final _recorder = FlutterSoundRecorder();
  late StreamController<Uint8List> _audioStreamController;
  // final TextEditingController _sendMessageController = TextEditingController();

  final apiToken = dotenv.env['HEYGEN_API_KEY'] ?? '';
  final elevenLabsApiKey = dotenv.env['ELEVENLABS_API_KEY'] ?? '';
  final heyGenVoiceID = dotenv.env['HEYGEN_VOICE_ID'] ?? 'EXAVITQu4vr4xnSDxMaL';
  final String agentId =
      dotenv.env['ELEVENLABS_AGENT_ID'] ?? 'EXAVITQu4vr4xnSDxMaL';

  @override
  void initState() {
    super.initState();
    _startSession().then((_) {
      _connectWebSocket();
      _greetUser();
    });
  }

  Future<void> _connectWebSocket() async {
    final url = Uri.parse(
      'https://api.elevenlabs.io/v1/convai/conversation/get-signed-url?agent_id=$agentId',
    );

    try {
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
        onDone: () => debugPrint('WebSocket closed'),
      );
    } catch (e) {
      debugPrint('WebSocket Exception: $e');
    }
  }

  void _handleWebSocketData(dynamic data) async {
    debugPrint('Received from WebSocket: $data');
    try {
      final response = jsonDecode(data);

      if (response['type'] == 'ping') return;
      if (response['event'] == 'ready') {
        setState(() => isSocketReady = true);
        return;
      }

      final aiText =
          response['agent_response_event']?['agent_response'] ??
          response['agent_response'] ??
          response['text'];

      if (aiText?.trim().isNotEmpty == true) {
        setState(() => _isListening = true);
        await Future.delayed(const Duration(milliseconds: 1000));
        setState(() => _isListening = false);
        _handleAIResponse(aiText!.trim());
      }
    } catch (e) {
      debugPrint('Failed to parse WebSocket message: $e');
    }
  }

  Future<void> _greetUser() async {
    if (_micEnabled) _startRecording();
  }

  Future<void> _startRecording() async {
    await Permission.microphone.request();
    await _recorder.openRecorder();
    _audioStreamController = StreamController<Uint8List>();

    _audioStreamController.stream.listen((buffer) {
      if (buffer.isNotEmpty) {
        final message = jsonEncode({"user_audio_chunk": base64Encode(buffer)});
        _channel?.sink.add(message);
      }
    });

    await _recorder.startRecorder(
      codec: Codec.pcm16,
      sampleRate: 16000,
      numChannels: 1,
      toStream: _audioStreamController.sink,
    );
  }

  // Future<void> _sendTextToSocket(String textMessage) async {
  //   if (_isSessionActive && isSocketReady) {
  //     final message = jsonEncode({"user_message": textMessage});
  //     _channel?.sink.add(message);
  //   } else {
  //     debugPrint('❌ Cannot send: Session inactive or socket not ready.');
  //   }
  // }

  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();
    _channel?.sink.add(
      jsonEncode({"type": "user_audio_chunk", "audio": null, "is_final": true}),
    );
  }

  void _handleAIResponse(String aiReply) async {
    setState(() => _messages.add({'sender': 'avatar', 'text': aiReply}));
    try {
      await _sendTextToAvatar(aiReply);
    } catch (e) {
      debugPrint('Error sending to HeyGen: $e');
    }
    _scrollToBottom();
  }

  Future<void> _startSession() async {
    try {
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

      setState(() => _isSessionActive = true);
    } catch (e) {
      debugPrint('Failed to start session: $e');
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
        'avatar_id': '2382f04c12af45cba82b53d1a60f9091',
        'voice': {'voice_id': heyGenVoiceID},
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

  Future<Room> _connectToLiveKitRoom(String url, String token) async {
    final room = Room();
    await room.connect(url, token);
    return room;
  }

  Future<void> _sendTextToAvatar(String text) async {
    if (_sessionId == null) return;
    try {
      final response = await http.post(
        Uri.parse('https://api.heygen.com/v1/streaming.task'),
        headers: {'Content-Type': 'application/json', 'x-api-key': apiToken},
        body: jsonEncode({'session_id': _sessionId, 'text': text}),
      );
      if (response.statusCode != 200) {
        debugPrint('Failed to send text to avatar: ${response.body}');
      }
    } catch (e) {
      debugPrint('Exception sending text to avatar: $e');
    }
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

  Widget _buildVideoWidget() {
    if (!_isSessionActive) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_videoTrack == null) {
      return const SizedBox();
    }
    return Container(
      margin: const EdgeInsets.all(15),
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
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            Expanded(child: Center(child: _buildVideoWidget())),
            if (_isListening)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  "Listening...",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                //  CircularProgressIndicator(),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask something to Dr E, He is here to help you with your dental queries.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Wrap(
                    //   spacing: 10,
                    //   runSpacing: 10,
                    //   alignment: WrapAlignment.start,
                    //   children: [
                    //     CommonWidgets.AppRoundedIconButton(
                    //       onPressed: () {
                    //         _sendTextToSocket(preTextholisticPlan);
                    //       },
                    //       label: preTextholisticPlan,
                    //       assetPath: AppAssets.searchIcon,
                    //     ),
                    //     CommonWidgets.AppRoundedIconButton(
                    //       onPressed: () {
                    //         _sendTextToSocket(preTextDental);
                    //       },
                    //       label: preTextDental,
                    //       assetPath: AppAssets.searchIcon,
                    //     ),
                    //   ],
                    // ),
                  ],
                ),
              ),
            ),

            // Expanded(
            //   child: Padding(
            //     padding: const EdgeInsets.all(15),
            //     child: ListView.builder(
            //       controller: _scrollController,
            //       itemCount: _messages.length,
            //       itemBuilder: (context, index) {
            //         final msg = _messages[index];
            //         final isUser = msg['sender'] == 'user';
            //         return Align(
            //           alignment: isUser
            //               ? Alignment.centerRight
            //               : Alignment.centerLeft,
            //           child: Container(
            //             padding: const EdgeInsets.symmetric(
            //               vertical: 10,
            //               horizontal: 16,
            //             ),
            //             margin: const EdgeInsets.symmetric(vertical: 4),
            //             decoration: BoxDecoration(
            //               color: isUser ? Colors.blue : Colors.grey[200],
            //               borderRadius: BorderRadius.only(
            //                 topLeft: const Radius.circular(16),
            //                 topRight: const Radius.circular(16),
            //                 bottomLeft: Radius.circular(isUser ? 16 : 0),
            //                 bottomRight: Radius.circular(isUser ? 0 : 16),
            //               ),
            //             ),
            //             child: Text(
            //               msg['text'] ?? '',
            //               style: TextStyle(
            //                 color: isUser ? Colors.white : Colors.black87,
            //                 fontSize: 16,
            //               ),
            //             ),
            //           ),
            //         );
            //       },
            //     ),
            //   ),
            // ),
            // Container(
            //   margin: const EdgeInsets.only(left: 15, right: 15),
            //   child: Row(
            //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
            //     children: [
            //       CommonWidgets.customButton(
            //         assetIconPath: AppAssets.uploadIcon,
            //         onPressed: () {},
            //         label: 'Upload',
            //       ),
            //       CommonWidgets.AppRoundedIconButton(
            //         onPressed: () {},
            //         label: 'Start New Diagnosis',
            //         assetPath: AppAssets.searchIcon,
            //       ),
            //     ],
            //   ),
            // ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Expanded(
                  //   child: TextField(
                  //     controller: _sendMessageController,
                  //     enabled: !_micEnabled,
                  //     decoration: InputDecoration(
                  //       hintText: 'Say or type a clinical command...',
                  //       border: OutlineInputBorder(
                  //         borderRadius: BorderRadius.circular(15),
                  //       ),
                  //     ),
                  //     onSubmitted: (_) =>
                  //         _sendTextToSocket(_sendMessageController.text),
                  //   ),
                  // ),
                  // IconButton(
                  //   icon: Icon(
                  //     size: 30,
                  //     _micEnabled ? Icons.mic : Icons.mic_off,
                  //     color: Colors.blue,
                  //   ),
                  //   onPressed: () async => await _toggleRecording(),
                  // ),
                  Column(
                    children: [
                      IconButton(
                        icon: Icon(
                          _micEnabled ? Icons.mic : Icons.mic_off,
                          color: _micEnabled ? Colors.blue : Colors.red,
                          size: 35,
                        ),
                        onPressed: () async => await _toggleRecording(),
                      ),
                      Text(
                        _micEnabled ? 'Listening...' : 'Listening stopped',
                        style: TextStyle(fontSize: 16, color: Colors.blue),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleRecording() async {
    try {
      if (_recorder.isRecording) {
        await _stopRecording();
      } else {
        await _startRecording();
      }
      if (mounted) setState(() => _micEnabled = !_micEnabled);
    } catch (e) {
      debugPrint('Error toggling recording: $e');
    }
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _audioStreamController.close();
    _channel?.sink.close();
    super.dispose();
  }
}
