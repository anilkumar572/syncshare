import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:sharesyncapp/logic/file_receiver_manager.dart';
import 'package:sharesyncapp/servises/singnaling_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../logic/file_transfer_manager.dart';

class TransferScreen extends StatefulWidget {
  @override
  _TransferScreenState createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  // Services
  SignalingService signaling = SignalingService();
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final Dio _dio = Dio(); // For reporting stats to your backend

  // UI State
  String? roomId;
  TextEditingController roomIdController = TextEditingController();
  double progress = 0.0;
  bool isTransferring = false;
  String status = "Idle";
  bool isConnected = false;
  FileReceiverManager? _receiverManager;
  String? savedPath;

  @override
  void initState() {
    super.initState();
    _initWebRTC();
  }

  Future<void> _initWebRTC() async {
    // 1. Create Peer Connection with STUN/TURN configuration
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"url": "stun:stun.l.google.com:19302"},
        // Add TURN server here for cross-network 4GB transfers
      ],
    };

    _peerConnection = await createPeerConnection(configuration);

    // 2. Handle Data Channel (Receiver Side)
    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannelListeners();
    };

    // 3. Connection State Monitoring
    _peerConnection!.onConnectionState = (state) {
      setState(() {
        status = "Connection: ${state.name}";
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          isConnected = true;
        }
      });
    };
  }

  // SENDER: Create a room and a data channel
  void _createRoom() async {
    final dataChannelDict = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = null;
    _dataChannel = await _peerConnection!.createDataChannel(
      "fileTransfer",
      dataChannelDict,
    );
    _setupDataChannelListeners();

    String id = await signaling.createRoom(_peerConnection!);
    setState(() {
      roomId = id;
      roomIdController.text = id;
    });
  }

  // RECEIVER: Join an existing room
  void _joinRoom() async {
    if (roomIdController.text.isNotEmpty) {
      await signaling.joinRoom(roomIdController.text, _peerConnection!);
    }
  }

  void _setupDataChannelListeners() {
    // Initialize the manager with a callback to update this UI state
    _receiverManager = FileReceiverManager(
      onStatusUpdate: (double p, String s, String? path) {
        setState(() {
          progress = p;
          status = s;
          if (path != null) savedPath = path;
        });
      },
    );

    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      // Pass every message (Meta, Binary, EOF) to the manager
      _receiverManager?.handleIncomingMessage(message);
    };

    _dataChannel!.onDataChannelState = (state) {
      setState(() {
        status = "Channel State: ${state.name}";
      });
    };
  }

  Future<void> _startTransfer() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && _dataChannel != null) {
      File file = File(result.files.single.path!);

      setState(() {
        isTransferring = true;
        status = "Streaming 4GB File...";
      });

      WakelockPlus.enable(); // Keep screen/CPU awake

      try {
        await FileTransferManager(_dataChannel!).sendLargeFile(file, (p) {
          setState(() => progress = p);
        });

        // Use Dio to report a successful transfer to your API
        // await _dio.post("https://your-api.com/log", data: {
        //   "fileName": file.path.split('/').last,
        //   "size": await file.length(),
        //   "status": "success"
        // });

        setState(() => status = "Transfer Complete!");
      } catch (e) {
        setState(() => status = "Error: $e");
      } finally {
        WakelockPlus.disable();
        setState(() => isTransferring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("P2P File Stream (4GB+)")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Area
            Card(
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  children: [
                    TextField(
                      controller: roomIdController,
                      decoration: InputDecoration(
                        labelText: "Room ID",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _createRoom,
                            child: Text("Create Room"),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _joinRoom,
                            child: Text("Join Room"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 30),

            // Inside the Column in your build() method:
            if (savedPath != null) ...[
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(10),
                color: Colors.green.withOpacity(0.1),
                child: Column(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 50),
                    Text(
                      "Transfer Complete!",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Saved to: $savedPath",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                    SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        // Use open_filex package to open the 4GB file
                        print("Opening file: $savedPath");
                      },
                      child: Text("Open File"),
                    ),
                  ],
                ),
              ),
            ],

            // Transfer Area
            if (isConnected) ...[
              Text(
                "Status: $status",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              if (isTransferring) ...[
                LinearProgressIndicator(value: progress),
                SizedBox(height: 10),
                Text("${(progress * 100).toStringAsFixed(1)}% Completed"),
              ],
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: isTransferring ? null : _startTransfer,
                icon: Icon(Icons.upload_file),
                label: Text("Select & Send Large File"),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ] else
              Center(child: Text("Connect to a room to start transfer")),
          ],
        ),
      ),
    );
  }
}
