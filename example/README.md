# example

## Flutter TFtp server

```dart
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
            stream: infoController.stream,
            builder: (context, snapshot) {
              return snapshot.hasData ? Text(snapshot.data) : Container();
            },
          ),
          RaisedButton(
            onPressed: () async {
              Directory appDocDir = await getApplicationDocumentsDirectory();
              String appDocPath = appDocDir.path;

              server = await TFtpServer.bind("0.0.0.0", port: 6699);
              server.listen((socket) {
                socket.listen(onRead: (file, onProcess) {
                  infoController.add("read file from server:$file");
                  onProcess(progressCallback: (count, total) {
                    processController.add(count / total);
                  });
                  return "$appDocPath/$file";
                }, onWrite: (file, doTransform) {
                  doTransform();
                  infoController.add("write file to server:$file");
                  return "$appDocPath/$file";
                }, onError: (code, msg) {
                  infoController.add("Error[$code]:$msg");
                });
              });
              infoController.add("Server start.");
            },
            child: Text("Start"),
          ),
          RaisedButton(
            onPressed: () {
              if (null != this.server) {
                this.server.close();
                infoController.add("Server stop.");
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
                        Text("Process:${(snapshot.data * 100).toStringAsFixed(2)}%"),
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
```

## Flutter TFtp client

```dart
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tftp/tftp.dart';

class ClientDemo extends StatefulWidget {
  @override
  _ClientDemoState createState() => _ClientDemoState();
}

class _ClientDemoState extends State<ClientDemo> {
  var host = TextEditingController();
  var port = TextEditingController();
  var local = TextEditingController();
  var remote = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
        child: Column(
      children: ListTile.divideTiles(
        context: context,
        tiles: [
          TextField(
            controller: host,
            decoration: InputDecoration(labelText: "Host"),
          ),
          TextField(
            controller: port,
            decoration: InputDecoration(labelText: "Port"),
          ),
          TextField(
            controller: local,
            decoration: InputDecoration(labelText: "Local File"),
          ),
          TextField(
            controller: remote,
            decoration: InputDecoration(labelText: "Remote File"),
          ),
          Row(
            children: <Widget>[
              RaisedButton(
                child: Text("Get"),
                onPressed: () async {
                  var client = await TFtpClient.bind(
                      "0.0.0.0", 40000 + Random().nextInt(10000));
                  Directory appDocDir =
                      await getApplicationDocumentsDirectory();
                  String appDocPath = appDocDir.path;
                  client.get("$appDocPath/${local.text}", remote.text,
                      host.text, int.parse(port.text));
                },
              ),
              RaisedButton(
                child: Text("Put"),
                onPressed: () async {
                  var client = await TFtpClient.bind(
                      "0.0.0.0", 40000 + Random().nextInt(10000));
                  Directory appDocDir =
                      await getApplicationDocumentsDirectory();
                  String appDocPath = appDocDir.path;
                  client.put("$appDocPath/${local.text}", remote.text,
                      host.text, int.parse(port.text));
                },
              ),
            ],
          ),
        ],
      ).toList(),
    ));
  }
}
```
