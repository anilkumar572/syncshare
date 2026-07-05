import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sharesyncapp/logic/file_receiver_manager.dart';
import 'package:sharesyncapp/logic/file_transfer_manager.dart';
import 'package:sharesyncapp/logic/file_transfer_platform.dart';
import 'package:sharesyncapp/servises/singnaling_service.dart';
import 'package:sharesyncapp/theme/app_theme.dart';
import 'package:sharesyncapp/widgets/animated_progress_section.dart';
import 'package:sharesyncapp/widgets/animated_status_chip.dart';
import 'package:sharesyncapp/widgets/glass_card.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen>
    with SingleTickerProviderStateMixin {
  final SignalingService signaling = SignalingService();
  final TextEditingController roomIdController = TextEditingController();

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  FileReceiverManager? _receiverManager;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  String? roomId;
  double progress = 0;
  bool isTransferring = false;
  bool isConnecting = false;
  String status = 'Ready to connect';
  bool isConnected = false;
  String? savedPath;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();
    _initWebRTC();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    roomIdController.dispose();
    _receiverManager?.dispose();
    super.dispose();
  }

  Future<void> _initWebRTC() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannelListeners();
    };

    _peerConnection!.onConnectionState = (state) {
      setState(() {
        status = 'Connection: ${_formatState(state.name)}';
        isConnecting = state ==
                RTCPeerConnectionState.RTCPeerConnectionStateConnecting ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateNew;
        isConnected =
            state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      });
    };
  }

  String _formatState(String raw) {
    return raw
        .replaceAll('RTCPeerConnectionState', '')
        .replaceAll('_', ' ')
        .trim();
  }

  Future<void> _createRoom() async {
    setState(() {
      isConnecting = true;
      status = 'Creating room...';
    });

    final dataChannelDict = RTCDataChannelInit()..ordered = true;

    _dataChannel = await _peerConnection!.createDataChannel(
      'fileTransfer',
      dataChannelDict,
    );
    _setupDataChannelListeners();

    try {
      final id = await signaling.createRoom(_peerConnection!);
      setState(() {
        roomId = id;
        roomIdController.text = id;
        status = 'Room created. Share the ID to connect.';
      });
    } catch (e) {
      setState(() => status = 'Failed to create room: $e');
    }
  }

  Future<void> _joinRoom() async {
    if (roomIdController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      isConnecting = true;
      status = 'Joining room...';
    });

    try {
      await signaling.joinRoom(roomIdController.text.trim(), _peerConnection!);
      setState(() => status = 'Joined room. Waiting for peer connection...');
    } catch (e) {
      setState(() => status = 'Failed to join room: $e');
    }
  }

  void _setupDataChannelListeners() {
    _receiverManager = FileReceiverManager(
      onStatusUpdate: (double p, String s, String? path) {
        setState(() {
          progress = p;
          status = s;
          if (path != null) {
            savedPath = path;
          }
        });
      },
    );

    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      _receiverManager?.handleIncomingMessage(message);
    };

    _dataChannel!.onDataChannelState = (state) {
      setState(() {
        status = 'Channel: ${_formatState(state.name)}';
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          isConnected = true;
        }
      });
    };
  }

  Future<void> _startTransfer() async {
    final result = await FilePicker.platform.pickFiles(withReadStream: !kIsWeb);

    if (result == null || _dataChannel == null) {
      return;
    }

    setState(() {
      isTransferring = true;
      progress = 0;
      savedPath = null;
      status = 'Preparing transfer...';
    });

    await WakelockPlus.enable();

    try {
      final manager = FileTransferManager(_dataChannel!);
      final picked = result.files.single;

      if (kIsWeb) {
        final bytes = picked.bytes;
        if (bytes == null) {
          throw StateError('Could not read selected file on web');
        }
        await manager.sendFromBytes(bytes, picked.name, _updateProgress);
      } else if (picked.path != null) {
        await sendFileFromDisk(_dataChannel!, picked.path!, _updateProgress);
      } else {
        throw StateError('Could not access selected file path');
      }

      setState(() => status = 'Transfer complete!');
    } catch (e) {
      setState(() => status = 'Transfer failed: $e');
    } finally {
      await WakelockPlus.disable();
      setState(() => isTransferring = false);
    }
  }

  void _updateProgress(double value) {
    if (!mounted) {
      return;
    }
    setState(() => progress = value);
  }

  Future<void> _copyRoomId() async {
    if (roomId == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: roomId!));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Text('Room ID copied'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('ShareSync'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: AnimatedStatusChip(
              label: isConnected ? 'Connected' : 'Offline',
              isConnected: isConnected,
            ),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.backgroundGradient(),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 88, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroHeader(isConnected: isConnected),
                  const SizedBox(height: 24),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Room',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Create a room or join with a shared ID to start P2P transfer.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: roomIdController,
                          decoration: const InputDecoration(
                            labelText: 'Room ID',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: isConnecting ? null : _createRoom,
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text('Create'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: isConnecting ? null : _joinRoom,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.surfaceLight,
                                ),
                                icon: const Icon(Icons.login_rounded),
                                label: const Text('Join'),
                              ),
                            ),
                          ],
                        ),
                        if (roomId != null) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _copyRoomId,
                            icon: const Icon(Icons.copy_rounded),
                            label: Text('Copy room ID: $roomId'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: isConnected
                        ? _TransferPanel(
                            key: const ValueKey('transfer'),
                            status: status,
                            progress: progress,
                            isTransferring: isTransferring,
                            onTransfer: _startTransfer,
                          )
                        : _WaitingPanel(
                            key: const ValueKey('waiting'),
                            status: status,
                            isConnecting: isConnecting,
                          ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    child: savedPath == null
                        ? const SizedBox.shrink()
                        : _SuccessPanel(
                            key: ValueKey(savedPath),
                            savedPath: savedPath!,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: isConnected ? 1 : 0.75),
          duration: const Duration(milliseconds: 500),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.secondary],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        Text(
          'Fast P2P file streaming',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Direct device-to-device transfer over WebRTC. No cloud upload.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _WaitingPanel extends StatelessWidget {
  const _WaitingPanel({
    super.key,
    required this.status,
    required this.isConnecting,
  });

  final String status;
  final bool isConnecting;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          if (isConnecting)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          Icon(
            Icons.hub_outlined,
            size: 42,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            status,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _TransferPanel extends StatelessWidget {
  const _TransferPanel({
    super.key,
    required this.status,
    required this.progress,
    required this.isTransferring,
    required this.onTransfer,
  });

  final String status;
  final double progress;
  final bool isTransferring;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Transfer',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              status,
              key: ValueKey(status),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
          ),
          const SizedBox(height: 20),
          AnimatedProgressSection(
            progress: progress,
            isActive: isTransferring || progress > 0,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: isTransferring ? null : onTransfer,
            icon: const Icon(Icons.cloud_upload_rounded),
            label: Text(
              isTransferring ? 'Transferring...' : 'Select & Send File',
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessPanel extends StatelessWidget {
  const _SuccessPanel({super.key, required this.savedPath});

  final String savedPath;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: GlassCard(
        child: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.8, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.secondary,
                    size: 56,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Transfer complete',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              savedPath,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
