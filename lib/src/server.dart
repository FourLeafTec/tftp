import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:tftp/tftp.dart';

typedef ReadFileCallBack = String Function(String file,
    void Function({ProgressCallback? progressCallback}) onProgress);
typedef WriteFileCallBack = String Function(
    String file,
    void Function(
            {bool overwrite,
            StreamTransformer<List<int>, dynamic>? transformer})
        doTransform);

class TFtpServer extends Stream<TFtpServerSocket> {
  TFtpServer(this.address, {this.port = 69}) {
    _controller = StreamController<TFtpServerSocket>(sync: true);
    RawDatagramSocket.bind(address, port).then(_init, onError: _initError);
  }

  static Future<TFtpServer> bind(address, {int port = 69}) async {
    return new Future(() => TFtpServer(address, port: port));
  }

  late final HashMap<String, TFtpServerSocket> _socketDic = HashMap();
  late RawDatagramSocket _udpSocket;
  late StreamController<TFtpServerSocket> _controller;
  dynamic address;
  int port;

  void _init(RawDatagramSocket socket) {
    _udpSocket = socket;
    _udpSocket.listen((ev) {
      if (ev == RawSocketEvent.read) {
        var datagram = _udpSocket.receive();
        var tid = "${datagram?.address.toString()}:${datagram?.port}";
        if (null == _socketDic[tid]) {
          var socket =
              TFtpServerSocket(_udpSocket, datagram!.address, datagram.port);
          _socketDic[tid] = socket;
          _controller.add(socket);
        }
        _socketDic[tid]?.read(datagram!.data);
      }
    });
  }

  void _initError(error, stack) {
    close();
  }

  Future close({bool force = false}) {
    return _controller.close();
  }

  @override
  StreamSubscription<TFtpServerSocket> listen(
      void Function(TFtpServerSocket event)? onData,
      {Function? onError,
      void Function()? onDone,
      bool? cancelOnError}) {
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

  ReadFileCallBack? onRead;
  WriteFileCallBack? onWrite;
  ErrorCallBack? onError;

  late File? _writeFile;
  late IOSink? _writeSink;
  late StreamController<List<int>>? _writeStreamCtrl;
  late List<int>? _receivedBlock = List.empty();

  void read(List<int> data) {
    switch (data[0] << 8 | data[1]) {
      case OpCode.RRQ_VALUE:
        var info = _readFileNameAndTransType(data);
        print("read server file:${info.fileName} with ${info.transType}");
        ProgressCallback? onReceive;
        if (null != onRead) {
          info.fileName = onRead!(info.fileName, ({progressCallback}) {
            onReceive = progressCallback;
          });
        }
        var file = File(info.fileName);
        if (!file.existsSync()) {
          throwError(Error.FILE_NOT_FOUND);
          return;
        }
        _write(file, onReceiveProgress: onReceive);
        return;
      case OpCode.WRQ_VALUE:
        var info = _readFileNameAndTransType(data);
        print("write server file:${info.fileName} with ${info.transType}");

        if (null != _writeStreamCtrl) {
          _writeStreamCtrl?.close().then((_) {
            if (null != _writeSink) {
              _writeSink?.close();
              _writeSink = null;
            }
          });
        }
        if (null != _writeFile) {
          _writeFile?.deleteSync();
        }

        bool _overwrite = true;
        if (null != onWrite) {
          info.fileName =
              onWrite!(info.fileName, ({overwrite = true, transformer}) {
            _overwrite = overwrite;
            if (null != transformer) {
              _writeStreamCtrl?.stream.transform(transformer);
            }
          });
        }
        _writeFile = File(info.fileName);

        if (!_overwrite && _writeFile!.existsSync()) {
          throwError(Error.FILE_ALREADY_EXISTS);
          return;
        }
        try {
          _writeFile?.createSync();
        } catch (e) {
          throwError(Error.ACCESS_VIOLATION);
          return;
        }
        _writeStreamCtrl = StreamController(sync: true);
        _writeSink = _writeFile?.openWrite();
        _writeSink?.addStream(_writeStreamCtrl!.stream);

        _receivedBlock = List.empty();
        List<int> sendPacket = [
          [0, OpCode.ACK_VALUE],
          [0x00, 0x00],
        ].expand((x) => x).toList();
        socket.send(sendPacket, remoteAddress, remotePort);
        return;
      case OpCode.ACK_VALUE:
        throwError(Error.ILLEGAL_OPERATION);
        return;
      case OpCode.DATA_VALUE:
        if (null == _writeFile) {
          throwError(Error.ILLEGAL_OPERATION);
          return;
        }
        var blockSeq = (data[2] << 8) + data[3];
        if (_receivedBlock!.contains(blockSeq)) {
          List<int> sendPacket = [
            [0, OpCode.ACK_VALUE],
            [data[2], data[3]],
          ].expand((x) => x).toList();
          socket.send(sendPacket, remoteAddress, remotePort);
          return;
        }
        _receivedBlock!.add(blockSeq);
        if (_receivedBlock!.length > 20) {
          _receivedBlock?.removeAt(0);
        }
        var d = data.sublist(4);
        _writeStreamCtrl?.add(d);
        List<int> sendPacket = [
          [0, OpCode.ACK_VALUE],
          [data[2], data[3]],
        ].expand((x) => x).toList();
        socket.send(sendPacket, remoteAddress, remotePort);
        if (d.length < blockSize) {
          _writeStreamCtrl?.close().then((_) {
            _writeSink?.close();
            _writeSink = null;
          });
          _writeStreamCtrl = null;
          _writeFile = null;
        }
        return;
      case OpCode.ERROR_VALUE:
        var code = data[2] << 8 | data[3];
        List<int> msgData = [];
        for (int i = 4; i < data.length; ++i) {
          if (0 == data[i]) {
            break;
          }
          msgData.add(data[i]);
        }
        var msg = String.fromCharCodes(msgData);
        _getError(code, msg);
        return;
      default:
        throwError(Error.ILLEGAL_OPERATION);
        return;
    }
  }

  TransInfo _readFileNameAndTransType(List<int> data) {
    List<List<int>> packetData =
        List.generate(2, (index) => List.empty(), growable: true);

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
    List<int> transTypeData = packetData[1];
    return TransInfo(String.fromCharCodes(fileNameData, 2, fileNameData.length),
        String.fromCharCodes(transTypeData, 0, transTypeData.length));
  }

  /// 客户端读取文件时用于写入文件内容
  Future _write(File file, {ProgressCallback? onReceiveProgress}) async {
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
        if (data!.data[0] << 8 | data.data[1] == OpCode.ACK_VALUE) {
          var ackValue = data.data[2] << 8 | data.data[3];
          sendCompleter.completer!.complete(ackValue);
        }
      }
    });

    Future.microtask(() async {
      List<int> dataBlock;
      while ((dataBlock = await _fileWait2Write.read(blockSize)).isNotEmpty) {
        _blockNum++;
        _blockNum = _blockNum > 65535 ? 0 : _blockNum;

        List<int> sendPacket = [
          [0, OpCode.DATA_VALUE],
          [_blockNum >> 8, _blockNum & 0xff],
          dataBlock
        ].expand((x) => x).toList();
        await _send(sendSocket, _blockNum, sendPacket, onReceiveProgress,
            totalSize, sendCompleter);
        if (_blockNum * blockSize == totalSize) {
          _blockNum++;
          _blockNum = _blockNum > 65535 ? 0 : _blockNum;
          List<int> sendPacket = [
            [0, OpCode.DATA_VALUE],
            [_blockNum >> 8, _blockNum & 0xff],
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
      ProgressCallback? onReceiveProgress,
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
      ack = await sendCompleter.completer!.future.timeout(
        const Duration(seconds: 1),
      );
    } while (ack != blockNum && sendTime < 5);
  }

  void close() {}

  void throwError(int code) {
    if (null != onError) {
      onError!(code, errorDic[code]!);
    }
    List<int> sendPacket = [
      [0, OpCode.ERROR_VALUE],
      [code >> 8, code & 0xff],
      encoder.convert(errorDic[code]!),
    ].expand((x) => x).toList();

    socket.send(sendPacket, remoteAddress, remotePort);
  }

  void _getError(int code, String message) {
    if (null != onError && code != 0) {
      onError!(code, message);
    }
  }

  void listen({
    ReadFileCallBack? onRead,
    WriteFileCallBack? onWrite,
    ErrorCallBack? onError,
  }) {
    this.onRead = onRead;
    this.onWrite = onWrite;
    this.onError = onError;
  }
}

class SendCompleter {
  Completer<int>? completer;
}

enum WorkType { IDLE, READ, WRITE }
