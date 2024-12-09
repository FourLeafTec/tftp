import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import './common.dart';

/// Callback for read event
///
/// file: the file path client want to read
/// progressCallback: callback for progress, trigger when transfer file
/// return: the true file path server read
typedef ReadFileCallBack = String Function(String file,
    void Function({ProgressCallback? progressCallback}) onProgress);

/// Callback for write event
///
/// file: the file path client want to write
/// doTransform: callback for transform, trigger when transfer file
/// return: the true file path server write
typedef WriteFileCallBack = String Function(
    String file,
    void Function(
        {bool overwrite,
        StreamTransformer<List<int>, List<int>>? transformer})
    doTransform);

/// TFtpServer is a server for TFTP protocol
class TFtpServer extends Stream<TFtpServerSocket> {
  TFtpServer(this.address, this.tftpGetMode, this.tftpPutMode, {this.port = 69}) {
    _controller = StreamController<TFtpServerSocket>(sync: true);
    RawDatagramSocket.bind(address, port).then(_init, onError: _initError);
  }

  static Future<TFtpServer> bind(address, getMode, putMode, {int port = 69}) async {
    return Future(() => TFtpServer(address, getMode, putMode, port: port));
  }

  late final HashMap<String, TFtpServerSocket> _socketDic = HashMap();
  late RawDatagramSocket _udpSocket;
  late StreamController<TFtpServerSocket> _controller;
  dynamic address;
  int port;
  bool tftpGetMode;
  bool tftpPutMode;

  void _init(RawDatagramSocket socket) {
    _udpSocket = socket;
    _udpSocket.listen((ev) {
      if (ev == RawSocketEvent.read) {
        var datagram = _udpSocket.receive();
        var tid = "${datagram?.address.toString()}:${datagram?.port}";
        if (null == _socketDic[tid]) {
          var socket =
          TFtpServerSocket(
              _udpSocket, datagram!.address, datagram.port, tftpGetMode, tftpPutMode);
          _socketDic[tid] = socket;
          _controller.add(socket);
        }
        _socketDic[tid]?._read(datagram!.data);
      }
    });
  }

  void _initError(error, stack) {
    close();
  }

  Future close({bool force = false}) {
    _socketDic.forEach((key, socket) {
      socket.close();
    });
    return _controller.close();
  }

  @override
  StreamSubscription<TFtpServerSocket> listen(void Function(TFtpServerSocket event)? onData,
      {Function? onError,
        void Function()? onDone,
        bool? cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

/// The socket for TFTP server
///
/// The server create a socket for client to connect
class TFtpServerSocket {
  TFtpServerSocket(this.socket, this.remoteAddress, this.remotePort, this.tftpGetMode,
      this.tftpPutMode,
      {this.blockSize = 512, this.onRead, this.onWrite, this.onError});

  /// The socket for client to connect
  RawDatagramSocket socket;

  /// The remote address for client
  InternetAddress remoteAddress;

  /// The remote port for client
  int remotePort;

  /// The block size for transfer file
  int blockSize;

  ///To allow read mode. Read mode allows to download file from the server
  bool tftpGetMode;

  ///To allow write mode. Write mode allows to upload file to the server
  bool tftpPutMode;

  /// Callback for read event
  ReadFileCallBack? onRead;

  /// Callback for write event
  WriteFileCallBack? onWrite;

  /// Callback for error event
  ErrorCallBack? onError;
  
  late File? _writeFile = null; //set null to handle lateinitializationerror
  late IOSink? _writeSink;
  late StreamController<List<int>>? _writeStreamCtrl = null;  //set null to handle lateinitializationerror

  late List<int>? _receivedBlock = List.empty(growable: true);

  /// Read data from client
  ///
  /// data: the data from client
  /// data format: [opcode, filename, 0, mode, 0]
  /// opcode: 2 bytes, the operation code of TFTP, see [OpCode]
  /// filename: the file name
  void _read(List<int> data) {
    switch (data[0] << 8 | data[1]) {
      case OpCode.RRQ_VALUE:
        //To block GET request from the client
        if (!tftpGetMode) {
          print("TFTP GET not allowed");
          throwError(0, "Permission denied.")
          return;
        }
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
        //To block PUT request from the client
        if (!tftpPutMode) {
          print("TFTP PUT not allowed");
          throwError(0, "Permission denied.")
          return;
        }
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
        _writeStreamCtrl = StreamController(sync: true); //To handle Null check operator used on a null value.
        var _stream = _writeStreamCtrl!.stream;
        if (null != onWrite) {
          info.fileName =
              onWrite!(info.fileName, ({overwrite = true, transformer}) {
                _overwrite = overwrite;
                if (null != transformer) {
                  _stream = _writeStreamCtrl!.stream.transform(transformer);
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
        _writeSink = _writeFile?.openWrite();
        _writeSink?.addStream(_stream);

        _receivedBlock = List.empty(growable: true);
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
    List.generate(2, (index) => List.empty(growable: true), growable: true);

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
          //Handling unhandled exception: Bad state: Future already completed
          if (!sendCompleter.completer!.isCompleted) {
            sendCompleter.completer!.complete(ackValue);
          }
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
        if (!await _send(sendSocket, _blockNum, sendPacket, onReceiveProgress,
            totalSize, sendCompleter)) {
          break; //Break the send process. This happens when the client breaks the transfer or the timeout happens
        }
        if (_blockNum * blockSize == totalSize) {
          _blockNum++;
          _blockNum = _blockNum > 65535 ? 0 : _blockNum;
          List<int> sendPacket = [
            [0, OpCode.DATA_VALUE],
            [_blockNum >> 8, _blockNum & 0xff],
          ].expand((x) => x).toList();
          if (await _send(sendSocket, _blockNum, sendPacket, onReceiveProgress,
              totalSize, sendCompleter)) {
            break; //Break the send process. This happens when the client breaks the transfer or the timeout happens
          }
        }
      }
      completer.complete();
    });

    return completer.future;
  }


  Future<bool> _send(RawDatagramSocket sendSocket
      int blockNum,
      List<int> sendPacket,
      ProgressCallback? onReceiveProgress,
      int totalSize,
      SendCompleter sendCompleter) async {
    int ack = -1; // Initialize with an invalid block number
    int sendTime = 0;
    bool result = false;
    do {
      sendTime++;
      sendSocket.send(sendPacket, remoteAddress, remotePort);
      if (null != onReceiveProgress) {
        var processed = blockNum * blockSize;
        processed = processed == totalSize ? processed - 1 : processed;
        processed = processed > totalSize ? totalSize : processed;
        onReceiveProgress(processed, totalSize);
      }
      sendCompleter.completer = Completer<int>();
      try {
        ack = await sendCompleter.completer!.future.timeout(
          const Duration(milliseconds: 5000), // Consider increasing the timeout
        );
        result = true;
      } catch (e) {
        print('Timeout waiting for ACK for block $blockNum (attempt $sendTime)');
        if (sendTime == 5) {
          print('Host connection timed out!');
          ack = blockNum;
          result = false;
          break;
        }
      }
    } while (ack != blockNum && sendTime < 5);
    if (ack != blockNum) {
      print('Failed to receive ACK for block $blockNum after 5 attempts.');
      result = false;
    }
    return result;
  }

  /// Close the socket
  void close() {
    socket.close();
  }

  /// Send error message to client
  ///
  /// [code] the error code, see [Error]
  /// [message] the error message, default is the error message of [code], see [errorDic]
  void throwError(int code, {String? message}) {
    if (null != onError) {
      onError!(code, errorDic[code]!);
    }
    List<int> sendPacket = [
      [0, OpCode.ERROR_VALUE],
      [code >> 8, code & 0xff],
      message != null
          ? encoder.convert(message)
          : encoder.convert(errorDic[code] ?? ''),
    ].expand((x) => x).toList();

    socket.send(sendPacket, remoteAddress, remotePort);
  }

  void _getError(int code, String message) {
    if (null != onError && code != 0) {
      onError!(code, message);
    }
  }

  /// Listen for read and write events
  ///
  /// [onRead] callback for read event, trigger when client read file
  ///
  /// [onWrite] callback for write event, trigger when client write file
  ///
  /// [onError] callback for error event, trigger when error occurred
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
