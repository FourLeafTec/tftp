import 'dart:async';

import 'package:tftp/tftp.dart';

class TFtpClient extends Stream<TFtpServerSocket>{
  @override
  StreamSubscription<TFtpServerSocket> listen(void Function(TFtpServerSocket event) onData, {Function onError, void Function() onDone, bool cancelOnError}) {
    return null;
  }
}