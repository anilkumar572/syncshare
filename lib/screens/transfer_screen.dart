import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sharesyncapp/logic/file_receiver_manager.dart';
import 'package:sharesyncapp/servises/singnaling_service.dart';
import '../logic/file_transfer_manager.dart';

enum TransferMode { send, receive }

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final SignalingService _signaling = SignalingService();
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  FileReceiverManager? _receiverManager;

  TransferMode _mode = TransferMode.send;
  final TextEditingController _roomIdController = TextEditingController();
  String? _roomId;
  bool _creatingRoom = false;
  bool _joiningRoom = false;

  RTCPeerConnectionState? _connectionState;
  bool _channelOpen = false;

  double _progress = 0.0;
  bool _isTransferring = false;
  String _status = 'Idle';
  String? _sendingFileName;
  String? _receivedLocation;

  bool get _isConnected =>
      _connectionState ==
      RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  @override
  void initState() {
    super.initState();
    _initWebRTC();
  }

  @override
  void dispose() {
    _roomIdController.dispose();
    _receiverManager?.dispose();
    _dataChannel?.close();
    _peerConnection?.close();
    super.dispose();
  }

  Future<void> _initWebRTC() async {
    final configuration = <String, dynamic>{
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ],
    };

    final pc = await createPeerConnection(configuration);

    pc.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannelListeners();
    };

    pc.onConnectionState = (state) {
      if (!mounted) return;
      setState(() => _connectionState = state);
    };

    _peerConnection = pc;
  }

  void _setupDataChannelListeners() {
    _receiverManager = FileReceiverManager(
      onStatusUpdate: (progress, status, location) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          _status = status;
          if (location != null) _receivedLocation = location;
        });
      },
    );

    _dataChannel!.onMessage = (message) {
      _receiverManager?.handleIncomingMessage(message);
    };

    _dataChannel!.onDataChannelState = (state) {
      if (!mounted) return;
      setState(() {
        _channelOpen = state == RTCDataChannelState.RTCDataChannelOpen;
      });
    };
  }

  Future<void> _createRoom() async {
    if (_peerConnection == null) return;
    setState(() => _creatingRoom = true);
    try {
      _dataChannel =
          await _peerConnection!.createDataChannel('fileTransfer', RTCDataChannelInit());
      _setupDataChannelListeners();

      final id = await _signaling.createRoom(_peerConnection!);
      setState(() {
        _roomId = id;
        _roomIdController.text = id;
        _status = 'Room created — waiting for peer…';
      });
    } catch (e) {
      _showSnack('Could not create room: $e');
    } finally {
      if (mounted) setState(() => _creatingRoom = false);
    }
  }

  Future<void> _joinRoom() async {
    final code = _roomIdController.text.trim();
    if (code.isEmpty || _peerConnection == null) return;
    setState(() => _joiningRoom = true);
    try {
      final ok = await _signaling.joinRoom(code, _peerConnection!);
      if (!ok) {
        _showSnack('Room "$code" was not found.');
      } else {
        setState(() {
          _roomId = code;
          _status = 'Joining room — connecting…';
        });
      }
    } catch (e) {
      _showSnack('Could not join room: $e');
    } finally {
      if (mounted) setState(() => _joiningRoom = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(
      withReadStream: !kIsWeb,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;

    setState(() {
      _isTransferring = true;
      _progress = 0.0;
      _sendingFileName = file.name;
      _status = 'Sending "${file.name}"…';
    });

    try {
      await FileTransferManager(_dataChannel!).sendFile(file, (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      });
      setState(() => _status = 'Sent "${file.name}"');
    } catch (e) {
      setState(() => _status = 'Error: $e');
      _showSnack('Transfer failed: $e');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF14152B), Color(0xFF0B0B16)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildStatusChip(),
                    const SizedBox(height: 16),
                    _buildModeSelector(),
                    const SizedBox(height: 16),
                    _buildConnectionCard(),
                    const SizedBox(height: 16),
                    _buildTransferCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.tertiary],
            ),
          ),
          child: const Icon(Icons.sync_alt_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 14),
        Text(
          'ShareSync',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Peer-to-peer file transfer, no size limits',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildStatusChip() {
    final (label, color, icon, spinner) = switch (_connectionState) {
      RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
        ('Connected', Colors.greenAccent, Icons.check_circle_rounded, false),
      RTCPeerConnectionState.RTCPeerConnectionStateConnecting ||
      RTCPeerConnectionState.RTCPeerConnectionStateNew when _roomId != null =>
        ('Connecting…', Colors.amberAccent, Icons.autorenew_rounded, true),
      RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
        ('Connection failed', Colors.redAccent, Icons.error_rounded, false),
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
      RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
        ('Disconnected', Colors.redAccent, Icons.link_off_rounded, false),
      _ => ('Not connected', Colors.white54, Icons.circle_outlined, false),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (spinner)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return SegmentedButton<TransferMode>(
      segments: const [
        ButtonSegment(
          value: TransferMode.send,
          label: Text('Send'),
          icon: Icon(Icons.arrow_upward_rounded),
        ),
        ButtonSegment(
          value: TransferMode.receive,
          label: Text('Receive'),
          icon: Icon(Icons.arrow_downward_rounded),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: _roomId != null
          ? null
          : (selection) => setState(() => _mode = selection.first),
      style: ButtonStyle(
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _mode == TransferMode.send
            ? _buildSendConnection()
            : _buildReceiveConnection(),
      ),
    );
  }

  Widget _buildSendConnection() {
    final scheme = Theme.of(context).colorScheme;
    if (_roomId == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Create a room', 'Generate a code to share'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _creatingRoom ? null : _createRoom,
            icon: _creatingRoom
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add_rounded),
            label: Text(_creatingRoom ? 'Creating…' : 'Create Room'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Share this code', 'The receiver enters it to connect'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  _roomId!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _roomId!));
                  _showSnack('Room code copied');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReceiveConnection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Join a room', 'Enter the code from the sender'),
        const SizedBox(height: 16),
        TextField(
          controller: _roomIdController,
          enabled: _roomId == null,
          textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(
            labelText: 'Room code',
            prefixIcon: Icon(Icons.vpn_key_rounded),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: (_joiningRoom || _roomId != null) ? null : _joinRoom,
          icon: _joiningRoom
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.login_rounded),
          label: Text(_joiningRoom ? 'Joining…' : 'Join Room'),
        ),
      ],
    );
  }

  Widget _buildTransferCard() {
    final scheme = Theme.of(context).colorScheme;

    if (!_isConnected) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _mode == TransferMode.send
                      ? 'Create a room and wait for the receiver to join.'
                      : 'Join a room to start receiving.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle(
              _mode == TransferMode.send ? 'Send a file' : 'Receiving',
              _status,
            ),
            const SizedBox(height: 16),
            if (_mode == TransferMode.send) ...[
              FilledButton.icon(
                onPressed: (_isTransferring || !_channelOpen)
                    ? null
                    : _pickAndSendFile,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(
                  _isTransferring ? 'Sending…' : 'Select & Send File',
                ),
              ),
              if (_sendingFileName != null) ...[
                const SizedBox(height: 12),
                _fileRow(_sendingFileName!),
              ],
            ],
            if (_isTransferring || _progress > 0) ...[
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
            if (_receivedLocation != null) ...[
              const SizedBox(height: 18),
              _successBanner(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _successBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Transfer complete',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Saved to $_receivedLocation',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileRow(String name) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.insert_drive_file_rounded,
            size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
