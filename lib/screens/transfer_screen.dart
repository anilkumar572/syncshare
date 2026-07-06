import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sharesyncapp/logic/file_receiver_manager.dart';
import 'package:sharesyncapp/logic/file_transfer_manager.dart';
import 'package:sharesyncapp/logic/file_transfer_platform.dart';
import 'package:sharesyncapp/logic/received_file.dart';
import 'package:sharesyncapp/servises/singnaling_service.dart';
import 'package:sharesyncapp/theme/app_theme.dart';
import 'package:sharesyncapp/widgets/animated_status_chip.dart';
import 'package:sharesyncapp/widgets/glass_card.dart';
import 'package:sharesyncapp/widgets/room_code_display.dart';
import 'package:sharesyncapp/widgets/transfer_status_card.dart';
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
  bool isHost = false;
  String status = 'Ready to connect';
  bool isConnected = false;
  ReceivedFile? receivedFile;

  TransferPhase phase = TransferPhase.idle;
  String? activeFileName;
  int totalBytes = 0;
  double speed = 0;
  DateTime _lastSampleTime = DateTime.now();
  int _lastSampleBytes = 0;

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
        isConnecting =
            state == RTCPeerConnectionState.RTCPeerConnectionStateConnecting;
        isConnected =
            state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
        if (isConnected) {
          status = 'Connected';
        }
      });
    };
  }

  Future<void> _createRoom() async {
    setState(() {
      isConnecting = true;
      isHost = true;
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
        status = 'Share this code with the other device';
      });
    } catch (e) {
      setState(() {
        status = 'Failed to create room: $e';
        isConnecting = false;
      });
    }
  }

  Future<void> _joinRoom() async {
    final code = roomIdController.text.trim();
    if (code.length != 6) {
      setState(() => status = 'Enter the 6-digit code');
      return;
    }

    setState(() {
      isConnecting = true;
      isHost = false;
      status = 'Joining room...';
    });

    try {
      await signaling.joinRoom(code, _peerConnection!);
      setState(() {
        roomId = code;
        status = 'Connecting to peer...';
      });
    } catch (e) {
      setState(() {
        status = 'Failed to join: $e';
        isConnecting = false;
      });
    }
  }

  void _setupDataChannelListeners() {
    _receiverManager = FileReceiverManager(
      onMeta: (name, size) {
        setState(() {
          phase = TransferPhase.receiving;
          activeFileName = name;
          totalBytes = size;
          progress = 0;
          receivedFile = null;
          _resetSpeedSampling();
        });
      },
      onStatusUpdate: (double p, String s, String? path) {
        setState(() {
          _recordProgress(p);
          status = s;
        });
      },
      onFileReceived: (file) {
        setState(() {
          phase = TransferPhase.done;
          progress = 1;
          speed = 0;
          receivedFile = file;
        });
      },
    );

    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      _receiverManager?.handleIncomingMessage(message);
    };

    _dataChannel!.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        setState(() {
          isConnected = true;
          isConnecting = false;
          status = 'Connected';
        });
      }
    };
  }

  Future<void> _startTransfer() async {
    final result = await FilePicker.platform.pickFiles(withReadStream: !kIsWeb);

    if (result == null || _dataChannel == null) {
      return;
    }

    final picked = result.files.single;

    setState(() {
      isTransferring = true;
      phase = TransferPhase.sending;
      activeFileName = picked.name;
      totalBytes = picked.size;
      progress = 0;
      receivedFile = null;
      status = 'Preparing transfer...';
      _resetSpeedSampling();
    });

    await WakelockPlus.enable();

    try {
      final manager = FileTransferManager(_dataChannel!);

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

      setState(() {
        phase = TransferPhase.done;
        progress = 1;
        speed = 0;
        status = 'File sent successfully';
      });
    } catch (e) {
      setState(() {
        phase = TransferPhase.idle;
        status = 'Transfer failed: $e';
      });
    } finally {
      await WakelockPlus.disable();
      setState(() => isTransferring = false);
    }
  }

  void _updateProgress(double value) {
    if (!mounted) {
      return;
    }
    setState(() => _recordProgress(value));
  }

  void _resetSpeedSampling() {
    _lastSampleTime = DateTime.now();
    _lastSampleBytes = 0;
    speed = 0;
  }

  void _recordProgress(double value) {
    progress = value;
    if (totalBytes <= 0) {
      return;
    }
    final now = DateTime.now();
    final currentBytes = (totalBytes * value.clamp(0, 1)).round();
    final elapsedMs = now.difference(_lastSampleTime).inMilliseconds;
    if (elapsedMs >= 300) {
      final deltaBytes = currentBytes - _lastSampleBytes;
      final instantSpeed = deltaBytes / (elapsedMs / 1000);
      speed = speed <= 0 ? instantSpeed : speed * 0.6 + instantSpeed * 0.4;
      _lastSampleTime = now;
      _lastSampleBytes = currentBytes;
    }
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
        width: 200,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Text('Code copied'),
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
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _HeroHeader(),
                      const SizedBox(height: 28),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            child: child,
                          ),
                        ),
                        child: isConnected
                            ? _buildTransferView()
                            : _buildConnectView(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectView() {
    return Column(
      key: const ValueKey('connect'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (roomId != null && isHost) ...[
                Text(
                  'Your room code',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                RoomCodeDisplay(code: roomId!),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyRoomId,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _StatusLine(
                  status: status,
                  showSpinner: isConnecting || !isConnected,
                ),
              ] else ...[
                Icon(
                  Icons.wifi_tethering_rounded,
                  size: 40,
                  color: AppTheme.secondary.withValues(alpha: 0.9),
                ),
                const SizedBox(height: 14),
                Text(
                  'Connect two devices',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create a code on one device and enter it on the other.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: isConnecting ? null : _createRoom,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create a room'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white24)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR JOIN',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.white24)),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: roomIdController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 10,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    hintStyle: TextStyle(
                      letterSpacing: 10,
                      color: Colors.white24,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: isConnecting ? null : _joinRoom,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Join room'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.surfaceLight,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                if (isConnecting) ...[
                  const SizedBox(height: 16),
                  _StatusLine(status: status, showSpinner: true),
                ] else if (status.startsWith('Failed') ||
                    status.startsWith('Enter')) ...[
                  const SizedBox(height: 12),
                  Text(
                    status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.accent),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransferView() {
    final showStatusCard = phase != TransferPhase.idle;
    final isBusy = phase == TransferPhase.sending ||
        phase == TransferPhase.receiving;

    return Column(
      key: const ValueKey('transfer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(sizeFactor: animation, child: child),
          ),
          child: showStatusCard
              ? Padding(
                  key: const ValueKey('status-card'),
                  padding: const EdgeInsets.only(bottom: 20),
                  child: TransferStatusCard(
                    phase: phase,
                    progress: progress,
                    fileName: activeFileName,
                    totalBytes: totalBytes,
                    speed: speed,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isBusy ? Icons.sync_rounded : Icons.cloud_upload_rounded,
                  color: AppTheme.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                phase == TransferPhase.receiving
                    ? 'Receiving from peer'
                    : 'Send a file',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                phase == TransferPhase.receiving
                    ? 'The file will download automatically when ready.'
                    : 'Pick a file to send it instantly to the connected device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isBusy ? null : _startTransfer,
                  icon: Icon(
                    isBusy
                        ? Icons.hourglass_top_rounded
                        : Icons.attach_file_rounded,
                  ),
                  label: Text(
                    phase == TransferPhase.sending
                        ? 'Sending...'
                        : phase == TransferPhase.receiving
                            ? 'Receiving...'
                            : 'Select & send file',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(sizeFactor: animation, child: child),
          ),
          child: receivedFile == null
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(receivedFile!.name),
                  padding: const EdgeInsets.only(top: 20),
                  child: _DownloadCard(
                    file: receivedFile!,
                    onDownload: () => _receiverManager?.redownload(),
                  ),
                ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.showSpinner});

  final String status;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showSpinner) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            status,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.secondary],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.4),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'ShareSync',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Fast, private device-to-device file transfer.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.file, required this.onDownload});

  final ReceivedFile file;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppTheme.secondary,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      file.readableSize,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (file.canRedownload)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Saved to: ${file.savedPath}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
