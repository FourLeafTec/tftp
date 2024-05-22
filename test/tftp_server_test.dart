import 'dart:io';

import 'package:tftp/tftp.dart';

void main() async {
  var server = await TFtpServer.bind("127.0.0.1", port: 6699);
  server.listen((socket) {
    socket.listen(onRead: (file, onProcess) {
      if (File(file).existsSync() == false) {
        // throw custom exception
        socket.throwError(Error.NOT_DEFINED, message: "File not found");
      }
      onProcess(progressCallback: (count, total) {
        print("$count/$total");
      });
      return file;
    }, onWrite: (file, doTransform) {
      doTransform(overwrite: false);
      return file;
    }, onError: (code, message) {
      print("Scoket error[$code]: $message");
    });
  }, onError: (e) {
    print("Server error: $e");
  }, onDone: () {
    print("Server done");
  });
  Future.delayed(const Duration(seconds: 30),()=>server.close());
}
