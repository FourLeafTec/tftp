import 'dart:io';

import 'package:tftp/tftp.dart';

void main() {
//  RawDatagramSocket.bind("127.0.0.1", 6699).then((socket) {
//    print("new socket:${socket.port}.");
//    socket.listen((ev) {
//      if (ev == RawSocketEvent.read) {
//        print("${ev.toString()},${socket.receive().data.length}");
//      }
//    });
//  });
  TFtpServer.bind("127.0.0.1", 6699).then((server) {
    server.listen((socket) {
      socket.listen((packet) {
        socket.write(File("D:\\temp\\${packet.file}")).then((_){
          print("write done");
          socket.close();
        });
      }, onDone: () {
        print("socket done");
        server.close();
      });
    });
  });
//  test("RawDatagramSocket",(){
//    RawDatagramSocket.bind("127.0.0.1", 6699).then((socket){
//      socket.listen((ev){
//        ev.toString();
//      });
//    });
//  });
//  test('Server bind', () {
//    TFtpServer.bind("127.0.0.1",80).then((server){
//      server.listen((socket){
//        socket.listen((packet){
//
//        });
//      });
//    });
//  });
}
