import 'package:tftp/tftp.dart';


void main() {
  TFtpServer.bind("127.0.0.1", 6699).then((server) {
    server.listen((socket) {
      socket.listen(onRead: (file,onProcess) {
        onProcess((count,total){
          print("$count/$total");
        });
        return file;
      },onWrite: (file,onWriteFile){
      });
    });
  });
}
