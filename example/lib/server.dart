import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tftp/tftp.dart';

class ServerDemo extends StatefulWidget {
  @override
  _ServerDemoState createState() => _ServerDemoState();
}

class _ServerDemoState extends State<ServerDemo> {
  StreamController<double> processController;
  StreamController<String> infoController;
  TFtpServer server;

  @override
  void initState() {
    super.initState();
    processController = StreamController();
    infoController = StreamController();
  }

  @override
  void dispose() {
    processController.close();
    infoController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          StreamBuilder<String>(
            builder: (context, snapshot) {
              return snapshot.hasData ? Text(snapshot.data) : Container();
            },
          ),
          RaisedButton(
            onPressed: () async {
              server = await TFtpServer.bind("127.0.0.1", port: 6699);
              server.listen((socket) {
                socket.listen(onRead: (file, onProcess) {
                  infoController.add("read file from server:$file");
                  onProcess(progressCallback: (count, total) {
                    processController.add(count / total);
                  });
                  return file;
                }, onWrite: (file, doTransform) {
                  infoController.add("write file to server:$file");
                });
              });
            },
            child: Text("Start"),
          ),
          RaisedButton(
            onPressed: () {
              if (null != this.server) {
                this.server.close();
              }
            },
            child: Text("Stop"),
          ),
          StreamBuilder<double>(
            stream: processController.stream,
            builder: (context, snapshot) {
              return snapshot.hasData
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text("Process:${snapshot.data * 100}%"),
                        LinearProgressIndicator(
                          value: snapshot.data,
                        ),
                      ],
                    )
                  : Container();
            },
          )
        ],
      ),
    );
  }
}
