import 'package:flutter/foundation.dart';
import 'package:sharesyncapp/utils/browser_file_stream.dart';

/// WebRTC send pacing: native apps and mobile browsers often report incorrect
/// [RTCDataChannel.bufferedAmount] and transfers stall if we wait on it.
bool get useTransferPacing => !kIsWeb || isMobileWebBrowser;
