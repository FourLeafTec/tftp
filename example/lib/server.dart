import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tftp/tftp.dart';

class ServerDemo extends StatefulWidget {
  @override
  _ServerDemoState createState() => _ServerDemoState();
}

class _ServerDemoState extends State<ServerDemo> {
  StreamController<double>? processController;
  StreamController<String>? infoController;
  TFtpServer? server;

  @override
  void initState() {
    super.initState();
    processController = StreamController();
    infoController = StreamController();
  }

  @override
  void dispose() {
    processController!.close();
    infoController!.close();
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
            stream: infoController?.stream,
            builder: (context, snapshot) {
              return snapshot.hasData ? Text(snapshot.data ?? '') : Container();
            },
          ),
          TextButton(
            onPressed: () async {
              Directory appDocDir = await getApplicationDocumentsDirectory();
              String appDocPath = appDocDir.path;

              server = await TFtpServer.bind("0.0.0.0", port: 6699);
              server?.listen((socket) {
                socket.listen(onRead: (file, onProcess) {
                  infoController?.add("read file from server:$file");
                  onProcess(progressCallback: (count, total) {
                    processController?.add(count / total);
                  });
                  return "$appDocPath/$file";
                }, onWrite: (file, doTransform) {
                  doTransform();
                  infoController?.add("write file to server:$file");
                  return "$appDocPath/$file";
                }, onError: (code, msg) {
                  infoController?.add("Error[$code]:$msg");
                });
              });
              infoController?.add("Server start.");
            },
            child: Text("Start"),
          ),
          TextButton(
            onPressed: () {
              if (null != this.server) {
                this.server?.close();
                infoController?.add("Server stop.");
              }
            },
            child: Text("Stop"),
          ),
          StreamBuilder<double>(
            stream: processController?.stream,
            builder: (context, snapshot) {
              return snapshot.hasData
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                            "Process:${(snapshot.data! * 100).toStringAsFixed(2)}%"),
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
