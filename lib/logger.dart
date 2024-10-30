// ignore_for_file: avoid_print

final class Logger {
  const Logger._();

  static const Logger _instance = Logger._();

  static Logger get instance => _instance;

  void log(Object? object) {
    print(object);
  }
}
