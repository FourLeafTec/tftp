import 'dart:convert';

typedef ProgressCallback = void Function(int count, int total);
typedef ErrorCallBack = void Function(int code, String message);

class TFtpException implements Exception {
  final int code;
  final String message;

  TFtpException(this.code, this.message);

  String toString() {
    return "TFtp Error[$code]: $message";
  }
}

Map<int, String> errorDic = {
  Error.NOT_DEFINED: 'Not defined, see error message(if any)',
  Error.FILE_NOT_FOUND: 'File not found',
  Error.ACCESS_VIOLATION: 'Access violation',
  Error.ALLOCATION_EXCEEDED: 'Disk full or allocation exceeded',
  Error.ILLEGAL_OPERATION: 'Illegal TFTP operation',
  Error.UNKNOWN_TRANSFER_ID: 'Unknown transfer ID',
  Error.FILE_ALREADY_EXISTS: 'File already exists',
  Error.NO_SUCH_USER: 'No such user',
};

class Error {
  static const int NOT_DEFINED = 0; //Not defined, see error message(if any)
  static const int FILE_NOT_FOUND = 1; //File not found
  static const int ACCESS_VIOLATION = 2; //Access violation
  static const int ALLOCATION_EXCEEDED = 3; //Disk full or allocation exceeded
  static const int ILLEGAL_OPERATION = 4; //Illegal TFTP operation
  static const int UNKNOWN_TRANSFER_ID = 5; //Unknown transfer ID
  static const int FILE_ALREADY_EXISTS = 6; //File already exists
  static const int NO_SUCH_USER = 7; //No such user
}

class OpCode {
  static const int RRQ_VALUE = 1;
  static const int WRQ_VALUE = 2;
  static const int DATA_VALUE = 3;
  static const int ACK_VALUE = 4;
  static const int ERROR_VALUE = 5;

  static const OpCode RRQ = const OpCode._(RRQ_VALUE);
  static const OpCode WRQ = const OpCode._(WRQ_VALUE);
  static const OpCode DATA = const OpCode._(DATA_VALUE);
  static const OpCode ACK = const OpCode._(ACK_VALUE);
  static const OpCode ERROR = const OpCode._(ERROR_VALUE);

  final int _value;

  const OpCode._(this._value);

  int get val => _value;
}

Utf8Encoder get encoder => const Utf8Encoder();

class TransType {
  static List<int> netascii = encoder.convert("netascii");
  static List<int> octet = encoder.convert("octet");
}

class TransInfo {
  String fileName;
  String transType;
}
