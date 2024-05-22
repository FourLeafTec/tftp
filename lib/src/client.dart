import 'dart:async';
import 'dart:io';

import './common.dart';

class TFtpClient {
  final String host;
  final int port;
  final int blockSize;

  late RawDatagramSocket _socket;
  late Stream<RawSocketEvent> _stream;

  List<int> _receivedBlock = List.empty(growable: true);

  TFtpClient(this.host, this.port, {this.blockSize = 512});

  static Future<TFtpClient> bind(String host, int port, {int blockSize = 512}) {
    Completer<TFtpClient> completer = Completer();
    RawDatagramSocket.bind(host, port).then((socket) {
      var client = TFtpClient(host, port, blockSize: blockSize);
      client._socket = socket;
      client._stream = socket.asBroadcastStream();
      completer.complete(client);
    });
    return completer.future;
  }

  Future put(
      String localFile, String remoteFile, String remoteAddress, int remotePort,
      {ProgressCallback? progressCallback, ErrorCallBack? onError}) async {
    List<int> sendPacket = [
      [0, OpCode.WRQ_VALUE],
      encoder.convert(remoteFile),
      [0],
      TransType.octet,
      [0],
    ].expand((x) => x).toList();
    var _blockNum = 0;
    var _rp =
        await _sendPacket(sendPacket, _blockNum, remoteAddress, remotePort);

    RandomAccessFile _fileWait2Write = await File(localFile).open();
    var totalSize = _fileWait2Write.lengthSync();
    List<int> dataBlock;
    while ((dataBlock = await _fileWait2Write.read(blockSize)).isNotEmpty) {
      ++_blockNum;
      _blockNum = _blockNum > 65535 ? 0 : _blockNum;

      List<int> sendPacket = [
        [0, OpCode.DATA_VALUE],
        [_blockNum >> 8, _blockNum & 0xff],
        dataBlock
      ].expand((x) => x).toList();

      await _sendPacket(sendPacket, _blockNum, remoteAddress, _rp);
      if (_blockNum * blockSize == totalSize) {
        ++_blockNum;
        _blockNum = _blockNum > 65535 ? 0 : _blockNum;
        List<int> sendPacket = [
          [0, OpCode.DATA_VALUE],
          [_blockNum >> 8, _blockNum & 0xff],
        ].expand((x) => x).toList();
        await _sendPacket(sendPacket, _blockNum, remoteAddress, remotePort);
      }
    }
  }

  Future get(
      String localFile, String remoteFile, String remoteAddress, int remotePort,
      {ErrorCallBack? onError}) async {
    Completer<int> completer = Completer();

    var file = File(localFile);
    var io = file.openWrite();
    late StreamSubscription subscription;
    subscription = _stream.listen((ev) {
      if (RawSocketEvent.read == ev) {
        var data = _socket.receive();
        var port = data!.port;
        if (data.data[1] == OpCode.DATA_VALUE) {
          var blockSeq = (data.data[2] << 8) + data.data[3];
          if (_receivedBlock.contains(blockSeq)) {
            List<int> sendPacket = [
              [0, OpCode.ACK_VALUE],
              [data.data[2], data.data[3]],
            ].expand((x) => x).toList();
            _socket.send(
                sendPacket, InternetAddress(remoteAddress), remotePort);
            return;
          }
          _receivedBlock.add(blockSeq);
          if (_receivedBlock.length > 20) {
            _receivedBlock.removeAt(0);
          }

          List<int> d = data.data.sublist(4);
          if (d.isNotEmpty) {
            io.add(d);
          }
          List<int> sendPacket = [
            [0, OpCode.ACK_VALUE],
            [data.data[2], data.data[3]],
          ].expand((x) => x).toList();
          _socket.send(sendPacket, InternetAddress(remoteAddress), port);

          if (d.length < blockSize) {
            io.close();
            subscription.cancel();
            // TODO complete return value should be more meaningful
            completer.complete(1);
          }
        }
        _checkError(data.data);
      }
    });

    List<int> sendPacket = [
      [0, OpCode.RRQ_VALUE],
      encoder.convert(remoteFile),
      [0],
      TransType.octet,
      [0],
    ].expand((x) => x).toList();
    _receivedBlock = List.empty(growable: true);
    _socket.send(sendPacket, InternetAddress(remoteAddress), remotePort);

    return completer.future;
  }

  Future<int> _sendPacket(List<int> sendPacket, int blockSeq,
      String remoteAddress, int remotePort) async {
    Completer<int> completer = Completer();
    late StreamSubscription subscription;
    subscription = _stream.listen((ev) {
      if (RawSocketEvent.read == ev) {
        var data = _socket.receive();
        if (_checkAck(blockSeq, data!.data)) {
          subscription.cancel();
          completer.complete(data.port);
          return;
        }
        _checkError(data.data);
      }
    });
    _socket.send(sendPacket, InternetAddress(remoteAddress), remotePort);
    return completer.future;
  }

  bool _checkAck(int blockSeq, List<int> data) {
    if (data[0] << 8 | data[1] == OpCode.ACK_VALUE) {
      var ackValue = data[2] << 8 | data[3];
      if (blockSeq == ackValue) {
        return true;
      }
    }
    return false;
  }

  void _checkError(List<int> data) {
    if (data[0] << 8 | data[1] == OpCode.ERROR_VALUE) {
      var code = data[2] << 8 | data[3];
      List<int> msgData = [];
      for (int i = 4; i < data.length; ++i) {
        if (0 == data[i]) {
          break;
        }
        msgData.add(data[i]);
      }
      var msg = String.fromCharCodes(msgData);
      throw TFtpException(code, msg);
    }
  }

  void close() {
    _socket.close();
  }
}
