# tftp plugin

A lib for Trivial File Transfer Protocol(TFtp) server and client.

## How To Use

### Server

We can start a tftp server, and then a tftp client could download/upload file from server.

The server has `onRead`,`onWrite` and `onError` event.

For example:

```dart
  var server = await TFtpServer.bind("0.0.0.0", port: 6699);
  server.listen((socket) {
    socket.listen(onRead: (file, onProcess) {
      print("read file from server:$file");
      onProcess(progressCallback: (count, total) {
        print("read:${count / total}%");
      });
      return "$readAblePath/$file"; // server will read file from return value
    }, onWrite: (file, doTransform) {
      doTransform();
      infoController.add("write file to server:$file");
      return "$writeAblePath/$file"; // server will write file to return value
    }, onError: (code, msg) {
      infoController.add("Error[$code]:$msg");
    });
  });
```

### client

We can create a tftp client to download/upload file to a tftp server.

1. init

> var client = await TFtpClient.bind("0.0.0.0", port);

2. Get 

> client.get(localFilePath, remoteFilePath,remoteHost, remotePort);

3. Put

> client.put(localFilePath, remoteFilePath,remoteHost, remotePort);

### Topic:

If you want to read/write file to `EXTERNAL STORAGE`,you should 
Add permissions in `AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
```