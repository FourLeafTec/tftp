import 'dart:async';
import 'dart:io';

import 'package:tftp/src/common.dart';

class TFtpClient {
  final String host;
  final int port;
  final int blockSize;

  RawDatagramSocket _socket;
  Stream<RawSocketEvent> _stream;

  TFtpClient(this.host, this.port, {this.blockSize = 512});

  static Future<TFtpClient> bind(String host, int port, {int blockSize = 512}) {
    Completer<TFtpClient> completer = Completer();
    RawDatagramSocket.bind(host, port).then((socket) {
      var client = new TFtpClient(host, port, blockSize: blockSize);
      client._socket = socket;
      client._stream = socket.asBroadcastStream();
      completer.complete(client);
    });
    return completer.future;
  }

  Future put(
      String localFile, String remoteFile, String remoteAddress, int remotePort,
      {ProgressCallback progressCallback, ErrorCallBack onError}) async {
    List<int> sendPacket = [
      [0, OpCode.WRQ_VALUE],
      encoder.convert(remoteFile),
      [0],
      TransType.octet,
      [0],
    ].expand((x) => x).toList();
    var _blockNum = 0;
    var _rp = await _sendPacket(sendPacket, _blockNum, remoteAddress, remotePort);

    RandomAccessFile _fileWait2Write = await File(localFile).open();
    var totalSize = _fileWait2Write.lengthSync();
    List<int> dataBlock;
    while ((dataBlock = await _fileWait2Write.read(blockSize)).length > 0) {
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

  void get(
      String localFile, String remoteFile, String remoteAddress, int remotePort,
      {ErrorCallBack onError}) async {
    List<int> sendPacket = [
      [0, OpCode.RRQ_VALUE],
      encoder.convert(localFile),
      [0],
      TransType.octet,
      [0],
    ].expand((x) => x).toList();
    await _sendPacket(sendPacket, 0, remoteAddress, remotePort);
  }

  Future<int> _sendPacket(List<int> sendPacket, int blockSeq, String remoteAddress,
      int remotePort) async {
    Completer<int> completer = Completer();
    StreamSubscription subscription;
    subscription = _stream.listen((ev) {
      if (RawSocketEvent.read == ev) {
        var data = _socket.receive();
        if (_checkAck(blockSeq, data.data)) {
          subscription.cancel();
          completer.complete(data.port);
          return;
        }
        _checkError(data.data);
      }
    });
    _socket.send(sendPacket, InternetAddress(remoteAddress), remotePort);
    return completer.future.timeout(Duration(seconds: 5), onTimeout: () {
      subscription.cancel();
      completer.completeError("time out.");
    });
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
      throw new TFtpException(code, msg);
    }
  }
  void close(){
    _socket.close();
  }
}
