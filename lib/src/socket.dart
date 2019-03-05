import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:tftp/tftp.dart';

class TFtpSocket extends Stream<TFtpPacket> {
  TFtpSocket(this.localAddress, this.remoteAddress, this.remotePort,
      {this.blockSize = 512}) {
    _controller = StreamController<TFtpPacket>();
    _stream = _controller.stream.asBroadcastStream();
    _workType = WorkType.IDLE;
  }

  InternetAddress localAddress;
  InternetAddress remoteAddress;
  int remotePort;
  int blockSize;
  StreamController<TFtpPacket> _controller;
  Stream<TFtpPacket> _stream;
  WorkType _workType;
  RandomAccessFile _fileWait2Write;
  int _blockNum;

  TFtpPacket read(List<int> data) {
    switch (data[0] << 8 | data[1]) {
      case OpCode.RRQ_VALUE:
        List<List<int>> packetData = List(2);
        packetData[0] = List<int>();
        packetData[1] = List<int>();

        int pos = -1;
        for (int val in data) {
          if (0 == val) {
            pos++;
          }
          if (pos > 1) {
            break;
          }
          packetData[pos].add(val);
        }

        List<int> fileNameData = packetData[0];
        String fileName =
            String.fromCharCodes(fileNameData, 2, fileNameData.length);
        List<int> transTypeData = packetData[1];
        String transType =
            String.fromCharCodes(transTypeData, 0, transTypeData.length);
        print("$fileName $transType");
        _workType = WorkType.READ;
        _controller.add(TFtpPacket(file: fileName));
        break;
      case OpCode.WRQ_VALUE:
        // 反ACK
        // todo: TO IMPLEMENT
        break;
      case OpCode.ACK_VALUE:
        // 当状态为读时有效
        break;
      case OpCode.DATA_VALUE:
        // 如果有WRQ做前置,写入文件,写文件完成后向下发写文件信息
        // todo: TO IMPLEMENT
        break;
      case OpCode.ERROR_VALUE:
        break;
      default:
        _controller.addError("Unknown Operator");
        break;
    }
    return null;
  }

  /// 客户端读取文件时用于写入文件内容
  void write(File file) async {
    if (_workType != WorkType.READ) {
      _controller.addError("Error Work Type");
      return;
    }

    RawDatagramSocket sendSocket = await RawDatagramSocket.bind(
        localAddress, Random().nextInt(40000) + 10000);
    _fileWait2Write = await file.open();
    _blockNum = 0;
    sendSocket.listen((ev) async {
      if (RawSocketEvent.read == ev) {
        var data = sendSocket.receive();
        if (data.data[0] << 8 | data.data[1] == OpCode.ACK_VALUE) {
          _blockNum++;
          _blockNum = _blockNum > 65535 ? 0 : _blockNum;
          List<int> data = await _fileWait2Write.read(blockSize);
          List<int> sendPacket = [
            [0, OpCode.DATA_VALUE],
            [_blockNum >> 8, _blockNum & 255],
            data
          ].expand((x) => x).toList();
          sendSocket.send(sendPacket, remoteAddress, remotePort);
        }
      }
    });
    _blockNum++;
    _blockNum = _blockNum > 65535 ? 0 : _blockNum;
    List<int> data = await _fileWait2Write.read(blockSize);
    List<int> sendPacket = [
      [0, OpCode.DATA_VALUE],
      [_blockNum >> 8, _blockNum & 255],
      data
    ].expand((x) => x).toList();
    sendSocket.send(sendPacket, remoteAddress, remotePort);
  }

  void close() {
    _controller.close();
  }

  @override
  StreamSubscription<TFtpPacket> listen(void Function(TFtpPacket event) onData,
      {Function onError, void Function() onDone, bool cancelOnError}) {
    return _stream.asBroadcastStream().listen(onData,
        onDone: onDone, onError: onError, cancelOnError: cancelOnError);
  }
}

enum WorkType { IDLE, READ, WRITE }
