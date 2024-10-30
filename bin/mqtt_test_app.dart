import 'package:mqtt_test_app/logger.dart';
import 'package:mqtt_test_app/mqtt_client.dart';

void main(List<String> arguments) {
  const topic = '/topic/messages';
  MqttClient.instance.connect(() {
    Logger.instance.log('connected to server...');
    MqttClient.instance.subscribe(topic, (message) {
      Logger.instance.log(message);
    });
    Future.delayed(const Duration(seconds: 2)).then((_) {
      const message = 'Hello from me';
      Logger.instance.log('sending message $message');
      MqttClient.instance.sendMessage('/send', message);
    });
  });
}
