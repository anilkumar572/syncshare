import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SignalingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// SENDER: creates a room, publishes the offer, and — crucially — listens for
  /// the remote answer and the callee's ICE candidates so the connection can
  /// actually complete.
  Future<String> createRoom(RTCPeerConnection pc) async {
    final roomRef = _db.collection('rooms').doc();

    // Publish our (caller) ICE candidates as they are gathered.
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      roomRef.collection('callerCandidates').add(candidate.toMap());
    };

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await roomRef.set({'offer': offer.toMap()});

    // Apply the answer as soon as the callee writes it.
    roomRef.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data == null || data['answer'] == null) return;
      final remote = await pc.getRemoteDescription();
      if (remote != null) return; // already applied
      final answer = data['answer'];
      await pc.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
    });

    // Add the callee's ICE candidates as they arrive.
    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        pc.addCandidate(
          RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ),
        );
      }
    });

    return roomRef.id;
  }

  /// RECEIVER: joins an existing room, answers the offer, and listens for the
  /// caller's ICE candidates.
  Future<bool> joinRoom(String roomId, RTCPeerConnection pc) async {
    final roomRef = _db.collection('rooms').doc(roomId.trim());
    final doc = await roomRef.get();
    if (!doc.exists) return false;

    // Publish our (callee) ICE candidates as they are gathered.
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      roomRef.collection('calleeCandidates').add(candidate.toMap());
    };

    final data = doc.data()!;
    final offer = data['offer'];
    await pc.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await roomRef.update({'answer': answer.toMap()});

    // Add the caller's ICE candidates as they arrive.
    roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final candidateData = change.doc.data();
        if (candidateData == null) continue;
        pc.addCandidate(
          RTCIceCandidate(
            candidateData['candidate'],
            candidateData['sdpMid'],
            candidateData['sdpMLineIndex'],
          ),
        );
      }
    });

    return true;
  }
}
