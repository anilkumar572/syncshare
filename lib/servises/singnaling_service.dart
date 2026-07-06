import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SignalingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Random _random = Random.secure();

  // Buffer remote ICE candidates that arrive before the remote description is
  // set, then flush them. Adding a candidate before setRemoteDescription is a
  // common cause of connections silently never establishing.
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  Future<String> createRoom(RTCPeerConnection pc) async {
    final roomRef = await _reserveRoom();

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) {
        return;
      }
      roomRef.collection('callerCandidates').add(candidate.toMap());
    };

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await roomRef.set({
      'offer': offer.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    _listenForAnswer(roomRef, pc);
    _listenForCandidates(roomRef.collection('calleeCandidates'), pc);

    return roomRef.id;
  }

  Future<void> joinRoom(String roomId, RTCPeerConnection pc) async {
    final roomRef = _db.collection('rooms').doc(roomId);
    final doc = await roomRef.get();

    if (!doc.exists) {
      throw StateError('Room $roomId not found. Check the code.');
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) {
        return;
      }
      roomRef.collection('calleeCandidates').add(candidate.toMap());
    };

    final data = doc.data()!;
    final offer = data['offer'] as Map<String, dynamic>;
    await pc.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
    );
    _remoteDescriptionSet = true;
    await _flushPendingCandidates(pc);

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await roomRef.update({'answer': answer.toMap()});

    _listenForCandidates(roomRef.collection('callerCandidates'), pc);
  }

  Future<DocumentReference<Map<String, dynamic>>> _reserveRoom() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final code = (100000 + _random.nextInt(900000)).toString();
      final ref = _db.collection('rooms').doc(code);
      final snapshot = await ref.get();
      if (!snapshot.exists) {
        return ref;
      }
    }
    throw StateError('Could not allocate a room code. Please try again.');
  }

  void _listenForAnswer(
    DocumentReference<Map<String, dynamic>> roomRef,
    RTCPeerConnection pc,
  ) {
    roomRef.snapshots().listen((snapshot) async {
      final answer = snapshot.data()?['answer'] as Map<String, dynamic>?;
      if (answer == null || _remoteDescriptionSet) {
        return;
      }

      await pc.setRemoteDescription(
        RTCSessionDescription(
          answer['sdp'] as String,
          answer['type'] as String,
        ),
      );
      _remoteDescriptionSet = true;
      await _flushPendingCandidates(pc);
    });
  }

  void _listenForCandidates(
    CollectionReference<Map<String, dynamic>> candidates,
    RTCPeerConnection pc,
  ) {
    candidates.snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _handleCandidate(pc, change.doc.data()!);
        }
      }
    });
  }

  void _handleCandidate(RTCPeerConnection pc, Map<String, dynamic> data) {
    final candidate = RTCIceCandidate(
      data['candidate'] as String?,
      data['sdpMid'] as String?,
      (data['sdpMLineIndex'] as num?)?.toInt(),
    );

    if (_remoteDescriptionSet) {
      pc.addCandidate(candidate);
    } else {
      _pendingCandidates.add(candidate);
    }
  }

  Future<void> _flushPendingCandidates(RTCPeerConnection pc) async {
    for (final candidate in _pendingCandidates) {
      await pc.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }
}
