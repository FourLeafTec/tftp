import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:tftp/tftp.dart';

class TFtpServer extends Stream<TFtpSocket> {
  TFtpServer(this.address, this.port) {
    _controller = StreamController<TFtpSocket>();
    RawDatagramSocket.bind(address, port).then(_init, onError: _initError);
  }

  static Future<TFtpServer> bind(address, int port) async {
    return new Future(() => TFtpServer(address, port));
  }

  HashMap<String, TFtpSocket> _socketDic = new HashMap();
  RawDatagramSocket _udpSocket;
  StreamController<TFtpSocket> _controller;
  dynamic address;
  int port;

  void _init(RawDatagramSocket socket) {
    _udpSocket = socket;
    _udpSocket.listen((ev) {
      if (ev == RawSocketEvent.read) {
        var data = _udpSocket.receive();
        var tid = "${data.address.toString()}:${data.port}";
        if (null == _socketDic[tid]) {
          var socket = TFtpSocket(_udpSocket.address, data.address, data.port);
          socket.listen((packet) {}, onDone: () => _socketDic.remove(tid));
          _socketDic[tid] = socket;
          _controller.add(socket);
        }
        _socketDic[tid].read(data.data);
      }
    });
  }

  void _initError(error,stack) {
    close();
  }

  Future close({bool force: false}) {
    return _controller.close();
  }

  @override
  StreamSubscription<TFtpSocket> listen(void Function(TFtpSocket event) onData,
      {Function onError, void Function() onDone, bool cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
