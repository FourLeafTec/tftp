
import 'dart:async';

import 'package:tftp/tftp.dart';

class TFtpServer extends Stream<TFtpPacket>{
  @override
  StreamSubscription<TFtpPacket> listen(void Function(TFtpPacket event) onData, {Function onError, void Function() onDone, bool cancelOnError}) {
    // TODO: implement listen
    return null;
  }
}