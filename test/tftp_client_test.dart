import 'package:tftp/tftp.dart';

void main() async {
  var client = await TFtpClient.bind("0.0.0.0", 6789);
//  await client.put("d:/temp/bitbuck_https.PNG", "test.png", "127.0.0.1", 69);
  await client.get("d:/temp/test.PNG", "test.PNG", "127.0.0.1", 69);
  client.close();
}
