import 'package:http/http.dart' as http;

const browserTransport = false;
http.Client createTransport() => http.Client();
