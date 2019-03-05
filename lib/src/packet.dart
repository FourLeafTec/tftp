class TFtpPacket {
  TFtpPacket({this.file});

  String file;
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
