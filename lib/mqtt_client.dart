import 'dart:async';
import 'dart:convert';

import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqtt5_client/mqtt5_server_client.dart';

import 'logger.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
}

final class MqttClient {
  MqttClient._();

  static final MqttClient _instance = MqttClient._();

  static MqttClient get instance => _instance;
  final _connectionStream = StreamController<ConnectionStatus>.broadcast();
  final _lastConnectionTimeStream = StreamController<DateTime?>.broadcast();
  final _decoder = const Utf8Decoder();

  final _builder = MqttPayloadBuilder();

  Stream<ConnectionStatus> get connection => _connectionStream.stream;

  var _lastConnectionStreamValue = ConnectionStatus.disconnected;

  Stream<DateTime?> get lastConnectionTime => _lastConnectionTimeStream.stream;

  final Map<String, Function(String value)> _listeners = {};

  static const _ip = '192.168.1.10';
  static const _username = 'tracker20';
  static const _password = 'tracker20';
  var pongCount = 0;
  final _client = MqttServerClient.withPort(_ip, '', 1883);
  Function()? connected;

  bool _isConnected = false;

  void connect(Function() connected) async {
    if (isConnected) return;
    final isNotConnected =
        _lastConnectionStreamValue == ConnectionStatus.disconnected;
    if (!isNotConnected) return;
    this.connected = connected;
    _client.keepAlivePeriod = 60;
    _client.onConnected = _onConnected;
    _client.pongCallback = _pong;
    _client.onDisconnected = _onDisconnected;
    _client.websocketProtocols = MqttConstants.protocolsSingleDefault;
    Logger.instance.log('Client connecting....');
    try {
      _addConnectionStream(ConnectionStatus.connecting);
      await _client.connect(_username, _password);
      _addListener();
    } on MqttNoConnectionException catch (e) {
      Logger.instance.log('client exception - $e');
      _client.disconnect();
    } on Exception catch (e) {
      Logger.instance.log('Exception - $e');
      _client.disconnect();
    }
    if (!isConnected) {
      Logger.instance.log(
        'disconnecting, status is ${_client.connectionStatus}',
      );
      _client.disconnect();
      return;
    }
    Logger.instance.log('Client connected');
  }

  void sendMessage(String topic, String message) {
    if (!isConnected) return;
    _builder.clear();
    _builder.addString(message);
    _client.publishMessage(topic, MqttQos.exactlyOnce, _builder.payload!);
  }

  void subscribe(String topic, Function(String value) listener) async {
    _addListenerForTopics((topic, listener));
    if (!isConnected) return;
    Logger.instance.log('Subscribing to the $topic topic');
    _client.subscribe(topic, MqttQos.exactlyOnce);
  }

  Future<void> disconnect() async {
    Logger.instance.log('Sleeping....');
    await MqttUtilities.asyncSleep(2);
    Logger.instance.log('Unsubscribing');
    _unSubscribeTopics();
    await MqttUtilities.asyncSleep(2);
    Logger.instance.log('Disconnecting');
    _client.disconnect();
    Logger.instance.log('Exiting normally');
  }

  void _onDisconnected() {
    _addConnectionStream(ConnectionStatus.disconnected);
    if (isUnsolicitedDisconnected) {
      if (connected != null) connect(connected!);
      return;
    }
    if (_isConnected) {
      _isConnected = false;
    }
  }

  void _onConnected() {
    _isConnected = true;
    Logger.instance.log('Client connection was successful');
    _addConnectionStream(ConnectionStatus.connected);
    connected?.call();
    // if (_vehicleTopic != null) subscribe(_vehicleTopic!);
  }

  void _addListener() {
    _client.updates.listen((messages) {
      final lastMessage = messages.lastOrNull;
      if (lastMessage == null) return;
      final recMess = lastMessage.payload as MqttPublishMessage;
      final pt = MqttUtilities.bytesToStringAsString(recMess.payload.message!);
      String decodeMessage = _decoder.convert(pt.codeUnits);
      _handleListeners(lastMessage, decodeMessage);
      Logger.instance.log(pt);
    });
  }

  void _pong() {
    Logger.instance.log('Ping response client callback invoked');
    pongCount++;
  }

  bool get isConnected =>
      _client.connectionStatus!.state == MqttConnectionState.connected;

  bool get isUnsolicitedDisconnected =>
      _client.connectionStatus!.disconnectionOrigin ==
      MqttDisconnectionOrigin.unsolicited;

  void _addListenerForTopics((String, Function(String value)) listener) {
    Logger.instance.log('listen to ${listener.$1}...');
    _listeners[listener.$1] = listener.$2;
  }

  void removeListener(String topic) {
    _listeners.remove(topic);
  }

  void _handleListeners(
    MqttReceivedMessage<MqttMessage> message,
    String pt,
  ) {
    Logger.instance.log('receive message from ${message.topic}...');
    if (message.topic == null) return;
    _listeners[message.topic]?.call(pt);
  }

  void _unSubscribeTopics() {
    final keys = _listeners.keys.toList();
    for (int i = 0; i < keys.length; i++) {
      _client.unsubscribeStringTopic(keys[i]);
    }
  }

  void _addConnectionStream(ConnectionStatus status) {
    if (_connectionStream.isClosed) return;
    _connectionStream.add(status);
    _lastConnectionStreamValue = status;
  }
}
