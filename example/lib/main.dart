import 'package:example/client.dart';
import 'package:example/server.dart';
import 'package:flutter/material.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TFtp Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'TFtp Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.title}) : super(key: key);

  final String? title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {
  TabController? controller;

  @override
  void initState() {
    super.initState();
    controller = new TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    controller!.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title??"TFtp Demo"),
        bottom: TabBar(
          controller: controller,
          tabs: [
            Tab(icon: Icon(Icons.wb_cloudy), child: Text("Server")),
            Tab(icon: Icon(Icons.phonelink_ring), child: Text("Client"))
          ],
        ),
      ),
      body: Center(
        child: TabBarView(
          controller: controller,
          children: [
            ServerDemo(),
            ClientDemo(),
          ],
        ),
      ),
    );
  }
}
