import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:dio/dio.dart';

class SignalingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Dio _dio = Dio(); // Used for reporting stats or custom API auth

  Future<String> createRoom(RTCPeerConnection pc) async {
    var roomRef = _db.collection('rooms').doc();

    pc.onIceCandidate = (candidate) {
      roomRef.collection('callerCandidates').add(candidate.toMap());
    };

    var offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    await roomRef.set({'offer': offer.toMap()});
    return roomRef.id;
  }

  Future<void> joinRoom(String roomId, RTCPeerConnection pc) async {
    var roomRef = _db.collection('rooms').doc(roomId);
    var doc = await roomRef.get();

    if (doc.exists) {
      pc.onIceCandidate = (candidate) {
        roomRef.collection('calleeCandidates').add(candidate.toMap());
      };

      var data = doc.data()!;
      await pc.setRemoteDescription(RTCSessionDescription(data['offer']['sdp'], data['offer']['type']));
      
      var answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await roomRef.update({'answer': answer.toMap()});

      roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            pc.addCandidate(RTCIceCandidate(change.doc['candidate'], change.doc['sdpMid'], change.doc['sdpMLineIndex']));
          }
        }
      });
    }
  }
}