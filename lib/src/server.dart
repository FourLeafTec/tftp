import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:tftp/tftp.dart';

typedef ReadFileCallBack = String Function(
    String file, void Function(ProgressCallback progressCallback) onProgress);
typedef WriteFileCallBack = String Function(
    String file, void Function(StreamTransformer transformer) doTansform);
typedef ErrorCallBack = void Function(int code, String message);

typedef ProgressCallback = void Function(int count, int total);

class TFtpServer extends Stream<TFtpServerSocket> {
  TFtpServer(this.address, this.port) {
    _controller = StreamController<TFtpServerSocket>(sync: true);
    RawDatagramSocket.bind(address, port).then(_init, onError: _initError);
  }

  static Future<TFtpServer> bind(address, int port) async {
    return new Future(() => TFtpServer(address, port));
  }

  HashMap<String, TFtpServerSocket> _socketDic = new HashMap();
  RawDatagramSocket _udpSocket;
  StreamController<TFtpServerSocket> _controller;
  dynamic address;
  int port;

  void _init(RawDatagramSocket socket) {
    _udpSocket = socket;
    _udpSocket.listen((ev) {
      if (ev == RawSocketEvent.read) {
        var datagram = _udpSocket.receive();
        var tid = "${datagram.address.toString()}:${datagram.port}";
        if (null == _socketDic[tid]) {
          var socket =
              TFtpServerSocket(_udpSocket, datagram.address, datagram.port);
          _socketDic[tid] = socket;
          _controller.add(socket);
        }
        _socketDic[tid].read(datagram.data);
      }
    });
  }

  void _initError(error, stack) {
    close();
  }

  Future close({bool force: false}) {
    return _controller.close();
  }

  @override
  StreamSubscription<TFtpServerSocket> listen(
      void Function(TFtpServerSocket event) onData,
      {Function onError,
      void Function() onDone,
      bool cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class TFtpServerSocket {
  TFtpServerSocket(this.socket, this.remoteAddress, this.remotePort,
      {this.blockSize = 512, this.onRead, this.onWrite, this.onError});

  RawDatagramSocket socket;
  InternetAddress remoteAddress;
  int remotePort;
  int blockSize;

  ReadFileCallBack onRead;
  WriteFileCallBack onWrite;
  ErrorCallBack onError;

  File _writeFile;
  IOSink _writeSink;
  StreamController<List<int>> _writeStreamCtrl;

  void read(List<int> data) {
    switch (data[0] << 8 | data[1]) {
      case OpCode.RRQ_VALUE:
        var info = _readFileNameAndTransType(data);
        print("read server file:${info.fileName} with ${info.transType}");
        ProgressCallback onReceive;
        if (null != onRead) {
          info.fileName = onRead(info.fileName, (progressCallback) {
            onReceive = progressCallback;
          });
        }
        this._write(File(info.fileName), onReceiveProgress: onReceive);
        break;
      case OpCode.WRQ_VALUE:
        var info = _readFileNameAndTransType(data);
        print("write server file:${info.fileName} with ${info.transType}");

        if (null != _writeStreamCtrl) {
          _writeStreamCtrl.close();
        }
        if (null != _writeSink) {
          _writeSink.close();
        }
        if (null != _writeFile) {
          _writeFile.deleteSync();
        }

        _writeFile = File(info.fileName);
        _writeSink = _writeFile.openWrite(mode: FileMode.append);
        _writeStreamCtrl = StreamController(sync: true);
        if (null != onWrite) {
          info.fileName = onWrite(info.fileName, (transformer) {
            if (null != transformer) {
              _writeStreamCtrl.stream.transform(transformer);
            }
          });
        }
        _writeSink.addStream(_writeStreamCtrl.stream);

        List<int> sendPacket = [
          [0, OpCode.ACK_VALUE],
          [0x00, 0x00],
        ].expand((x) => x).toList();
        socket.send(sendPacket, remoteAddress, remotePort);
        break;
      case OpCode.ACK_VALUE:
        throwError(Error.ILLEGAL_OPERATION);
        break;
      case OpCode.DATA_VALUE:
        if (null == _writeFile) {
          throwError(Error.ILLEGAL_OPERATION);
          break;
        }
        var d = data.sublist(4);
        _writeStreamCtrl.add(d);
        List<int> sendPacket = [
          [0, OpCode.ACK_VALUE],
          [data[2], data[3]],
        ].expand((x) => x).toList();
        socket.send(sendPacket, remoteAddress, remotePort);
        break;
      case OpCode.ERROR_VALUE:
        // todo error message from data
        _getError(1," error message from data");
        break;
      default:
        throwError(Error.ILLEGAL_OPERATION);
        break;
    }
    return null;
  }

  TransInfo _readFileNameAndTransType(List<int> data) {
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

    TransInfo transInfo = TransInfo();
    List<int> fileNameData = packetData[0];
    transInfo.fileName =
        String.fromCharCodes(fileNameData, 2, fileNameData.length);
    List<int> transTypeData = packetData[1];
    transInfo.transType =
        String.fromCharCodes(transTypeData, 0, transTypeData.length);
    return transInfo;
  }

  /// 客户端读取文件时用于写入文件内容
  Future _write(File file, {ProgressCallback onReceiveProgress}) async {
    RandomAccessFile _fileWait2Write;
    int _blockNum;
    Completer completer = Completer();

    RawDatagramSocket sendSocket = await RawDatagramSocket.bind(
        socket.address, Random().nextInt(10000) + 40000);
    _fileWait2Write = await file.open();
    var totalSize = _fileWait2Write.lengthSync();
    _blockNum = 0;

    SendCompleter sendCompleter = SendCompleter();
    sendSocket.listen((ev) async {
      if (RawSocketEvent.read == ev) {
        var data = sendSocket.receive();
        if (data.data[0] << 8 | data.data[1] == OpCode.ACK_VALUE) {
          var ackValue = data.data[2] << 8 | data.data[3];
          if (null != sendCompleter) {
            sendCompleter.completer.complete(ackValue);
          }
        }
      }
    });

    Future.microtask(() async {
      List<int> dataBlock;
      while ((dataBlock = await _fileWait2Write.read(blockSize)).length > 0) {
        _blockNum++;
        _blockNum = _blockNum > 65535 ? 0 : _blockNum;

        List<int> sendPacket = [
          [0, OpCode.DATA_VALUE],
          [_blockNum >> 8, _blockNum & 255],
          dataBlock
        ].expand((x) => x).toList();
        await _send(sendSocket, _blockNum, sendPacket, onReceiveProgress,
            totalSize, sendCompleter);
        if (_blockNum * blockSize == totalSize) {
          _blockNum++;
          _blockNum = _blockNum > 65535 ? 0 : _blockNum;
          List<int> sendPacket = [
            [0, OpCode.DATA_VALUE],
            [_blockNum >> 8, _blockNum & 255],
            []
          ].expand((x) => x).toList();
          await _send(sendSocket, _blockNum, sendPacket, onReceiveProgress,
              totalSize, sendCompleter);
        }
      }
      completer.complete();
    });

    return completer.future;
  }

  Future _send(
      RawDatagramSocket sendSocket,
      int blockNum,
      List<int> sendPacket,
      ProgressCallback onReceiveProgress,
      int totalSize,
      SendCompleter sendCompleter) async {
    int ack;
    int sendTime = 0;
    do {
      sendTime++;
      sendSocket.send(sendPacket, remoteAddress, remotePort);
      if (null != onReceiveProgress) {
        var processed = blockNum * blockSize;
        processed = processed == totalSize ? processed - 1 : processed;
        processed = processed > totalSize ? totalSize : processed;
        onReceiveProgress(processed, totalSize);
      }
      sendCompleter.completer = Completer();
      ack = await sendCompleter.completer.future.timeout(
        Duration(seconds: 1),
        onTimeout: () => null,
      );
    } while (ack != blockNum && sendTime < 5);
  }

  void close() {}

  void throwError(int code) {
    if (null != onError) {
      onError(code, errorDic[code]);
    }
  }

  void _getError(int code,String message) {
    if (null != onError) {
      onError(code, errorDic[code]);
    }
  }

  void listen({
    ReadFileCallBack onRead,
    WriteFileCallBack onWrite,
    ErrorCallBack onError,
  }) {
    this.onRead = onRead;
    this.onWrite = onWrite;
  }
}

class TransInfo {
  String fileName;
  String transType;
}

class SendCompleter {
  Completer<int> completer;
}

enum WorkType { IDLE, READ, WRITE }
