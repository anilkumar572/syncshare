import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SignalingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<String> createRoom(RTCPeerConnection pc) async {
    final roomRef = _db.collection('rooms').doc();

    pc.onIceCandidate = (candidate) {
      roomRef.collection('callerCandidates').add(candidate.toMap());
    };

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await roomRef.set({'offer': offer.toMap()});

    _listenForAnswer(roomRef, pc);
    _listenForCalleeCandidates(roomRef, pc);
    await _addExistingCandidates(roomRef.collection('calleeCandidates'), pc);

    return roomRef.id;
  }

  Future<void> joinRoom(String roomId, RTCPeerConnection pc) async {
    final roomRef = _db.collection('rooms').doc(roomId);
    final doc = await roomRef.get();

    if (!doc.exists) {
      throw StateError('Room $roomId does not exist');
    }

    pc.onIceCandidate = (candidate) {
      roomRef.collection('calleeCandidates').add(candidate.toMap());
    };

    final data = doc.data()!;
    await pc.setRemoteDescription(
      RTCSessionDescription(data['offer']['sdp'], data['offer']['type']),
    );

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await roomRef.update({'answer': answer.toMap()});

    await _addExistingCandidates(
      roomRef.collection('callerCandidates'),
      pc,
    );
    _listenForCallerCandidates(roomRef, pc);
  }

  void _listenForAnswer(DocumentReference roomRef, RTCPeerConnection pc) {
    var answerApplied = false;

    roomRef.snapshots().listen((snapshot) async {
      final answer = snapshot.data()?['answer'] as Map<String, dynamic>?;
      if (answer == null || answerApplied) {
        return;
      }

      answerApplied = true;
      await pc.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
    });
  }

  void _listenForCallerCandidates(
    DocumentReference roomRef,
    RTCPeerConnection pc,
  ) {
    roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _addCandidate(pc, change.doc.data()!);
        }
      }
    });
  }

  void _listenForCalleeCandidates(
    DocumentReference roomRef,
    RTCPeerConnection pc,
  ) {
    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          _addCandidate(pc, change.doc.data()!);
        }
      }
    });
  }

  Future<void> _addExistingCandidates(
    CollectionReference candidates,
    RTCPeerConnection pc,
  ) async {
    final snapshot = await candidates.get();
    for (final doc in snapshot.docs) {
      _addCandidate(pc, doc.data() as Map<String, dynamic>);
    }
  }

  void _addCandidate(RTCPeerConnection pc, Map<String, dynamic> data) {
    pc.addCandidate(
      RTCIceCandidate(
        data['candidate'] as String,
        data['sdpMid'] as String?,
        data['sdpMLineIndex'] as int?,
      ),
    );
  }
}
