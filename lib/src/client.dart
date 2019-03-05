import 'dart:async';

import 'package:tftp/tftp.dart';

class TFtpClient extends Stream<TFtpSocket>{
  @override
  StreamSubscription<TFtpSocket> listen(void Function(TFtpSocket event) onData, {Function onError, void Function() onDone, bool cancelOnError}) {
    return null;
  }

}